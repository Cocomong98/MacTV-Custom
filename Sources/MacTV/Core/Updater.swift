import AppKit
import CryptoKit
@preconcurrency import Security // SecRequirement is immutable, so passing it to the install queue is safe.

/// Keeps Mac TV up to date from its GitHub releases. It checks at launch and once a day. With
/// automatic updates on (the default), a new version downloads straight away and installs only while
/// nothing is in use, so the restart never interrupts watching. Otherwise it waits for Settings › About.
///
/// A downloaded update is installed only if it's signed by the same certificate as the running app
/// (its designated requirement), so nothing but a real Mac TV release can replace it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let preferences: Preferences

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case downloading(Double)
        /// Downloaded and waiting for Mac TV to be idle.
        case ready(version: String, image: URL)
        case installing
        case failed(String)
    }

    struct Release: Equatable, Sendable {
        let version: String
        let download: URL
        var sha256: String? = nil
        var notes: String? = nil
    }

    @Published private(set) var state: State = .idle {
        didSet {
            switch state {
            case .failed(let message): Log.updates.error("\(message, privacy: .public)")
            case .available(let release): Log.updates.notice("Version \(release.version, privacy: .public) available")
            case .ready(let version, _): Log.updates.notice("Version \(version, privacy: .public) downloaded")
            case .installing: Log.updates.notice("Installing")
            default: break
            }
        }
    }
    /// Called once per new version, for the notice on the home screen.
    var onAvailable: ((String) -> Void)?
    /// Whether nothing is being watched or used right now, so restarting Mac TV is fine.
    var isIdle: () -> Bool = { false }

    /// Install new versions on their own while Mac TV is idle. On unless turned off.
    var automatic: Bool {
        get { !LocalBuild.isPublicEdition && preferences.automaticUpdates }
        set {
            guard !LocalBuild.isPublicEdition else { return }
            preferences.automaticUpdates = newValue
            if newValue, case .available(let release) = state { install(release, now: false) }
        }
    }

    /// Set just before an automatic update restarts Mac TV, so the new copy can pick up where it was.
    static func takeAutomaticRestart() -> Bool {
        defer { UserDefaults.standard.removeObject(forKey: "restartedForUpdate") }
        return UserDefaults.standard.bool(forKey: "restartedForUpdate")
    }

    private static let upstreamRelease = URL(string: "https://api.github.com/repos/Arunprakaash/mac-tv/releases/latest")!
    private static let publicRelease = URL(string: "https://api.github.com/repos/Cocomong98/MacTV-Custom/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?
    private var idleTimer: Timer?
    private var download: URLSessionDownloadTask?
    private var progress: NSKeyValueObservation?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var availableVersion: String? {
        switch state {
        case .available(let release): return release.version
        case .ready(let version, _): return version
        default: return nil
        }
    }

    var releaseNotes: String? {
        if case .available(let release) = state { return release.notes }
        return nil
    }

    func start() {
        guard !LocalBuild.isCustom, !LocalBuild.isPublicEdition else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            self.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfIdle() }
        }
    }

    /// A downloaded update goes in once nothing is in use.
    private func installIfIdle() {
        guard automatic, case .ready(_, let image) = state, isIdle() else { return }
        UserDefaults.standard.set(true, forKey: "restartedForUpdate")
        state = .installing
        installDiskImage(image)
    }

    /// The Software update row: installs an available update, otherwise checks now.
    func activate() {
        guard LocalBuild.isPublicEdition || !LocalBuild.isCustom else { return }
        switch state {
        case .available(let release): install(release, now: true)
        case .ready(_, let image):
            state = .installing
            installDiskImage(image)
        case .checking, .downloading, .installing: break
        default: check()
        }
    }

    func check() {
        let publicEdition = LocalBuild.isPublicEdition
        guard publicEdition || !LocalBuild.isCustom else { return }
        switch state {
        case .checking, .downloading, .ready, .installing: return
        default: break
        }
        state = .checking
        var request = URLRequest(url: publicEdition ? Self.publicRelease : Self.upstreamRelease, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let release = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            Task { @MainActor in
                guard let shared = self else { return }
                if publicEdition {
                    guard (response as? HTTPURLResponse)?.statusCode == 200, let release else {
                        shared.state = .failed("GitHub에서 업데이트를 확인할 수 없습니다. 다시 시도하세요.")
                        return
                    }
                    do {
                        if let update = try Self.couchDialUpdate(from: release, currentVersion: Self.currentVersion) {
                            shared.state = .available(update)
                        } else {
                            shared.state = .upToDate
                        }
                    } catch {
                        shared.state = .failed("공개 릴리스의 업데이트 정보를 확인할 수 없습니다.")
                    }
                    return
                }
                guard let release, let tag = release["tag_name"] as? String else {
                    shared.state = .failed(error == nil ? "Couldn't read the latest release." : "Couldn't reach GitHub.")
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = release["assets"] as? [[String: Any]] ?? []
                guard Self.isNewer(version, than: Self.currentVersion) else { shared.state = .upToDate; return }
                guard let link = assets.lazy.compactMap({ $0["browser_download_url"] as? String })
                        .first(where: { $0.hasSuffix(".dmg") }),
                      let url = URL(string: link), url.scheme == "https" else {
                    shared.state = .upToDate
                    return
                }
                let update = Release(version: version, download: url)
                shared.state = .available(update)
                if shared.automatic { shared.install(update, now: false) }
                let noticed = UserDefaults.standard.string(forKey: "updateNoticeShown")
                if noticed != version {
                    UserDefaults.standard.set(version, forKey: "updateNoticeShown")
                    shared.onAvailable?(version)
                }
            }
        }.resume()
    }

    /// Dotted version comparison: 0.10 is newer than 0.9, and 0.12 than 0.11.1.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    enum ReleaseError: Error { case invalidRelease }

    static func couchDialUpdate(from release: [String: Any], currentVersion: String) throws -> Release? {
        guard release["draft"] as? Bool == false, release["prerelease"] as? Bool == false,
              let tag = release["tag_name"] as? String, tag.first == "v" else { throw ReleaseError.invalidRelease }
        let version = String(tag.dropFirst())
        guard isStableVersion(version) else { throw ReleaseError.invalidRelease }
        guard isNewer(version, than: currentVersion) else { return nil }
        let name = "CouchDial-\(version).dmg"
        let expectedURL = "https://github.com/Cocomong98/MacTV-Custom/releases/download/\(tag)/\(name)"
        let assets = release["assets"] as? [[String: Any]] ?? []
        let matches = assets.filter { $0["name"] as? String == name }
        guard matches.count == 1, let asset = matches.first,
              asset["browser_download_url"] as? String == expectedURL, let url = URL(string: expectedURL),
              let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
              digest.count == 71, digest.dropFirst(7).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw ReleaseError.invalidRelease }
        let body = (release["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = body.flatMap { $0.isEmpty ? nil : String($0.prefix(600)) }
        return Release(version: version, download: url, sha256: String(digest.dropFirst(7)), notes: notes)
    }

    private static func isStableVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy {
            !$0.isEmpty && ($0.count == 1 || $0.first != "0")
                && $0.utf8.allSatisfy { (48...57).contains($0) } && Int($0) != nil
        }
    }

    // MARK: Installing

    /// Downloads the update; `now` installs it straight after, otherwise it waits until Mac TV is idle.
    private func install(_ release: Release, now: Bool) {
        let bundle = Bundle.main.bundleURL
        guard !bundle.path.contains("/AppTranslocation/"), !bundle.path.hasPrefix("/Volumes/") else {
            state = .failed(LocalBuild.isPublicEdition ? "먼저 앱을 응용 프로그램 폴더에 설치하세요." : "Move Mac TV to Applications first.")
            return
        }
        guard FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            state = .failed(LocalBuild.isPublicEdition ? "현재 폴더에 앱을 설치할 권한이 없습니다." : "Mac TV can't write to its folder. Download the update from GitHub.")
            return
        }
        state = .downloading(0)
        let task = URLSession.shared.downloadTask(with: release.download) { [weak self] file, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let allowed = release.sha256 == nil || (response?.url?.scheme == "https" &&
                ["github.com", "release-assets.githubusercontent.com"].contains(response?.url?.host ?? ""))
            // The downloaded file is removed when this returns, so move it somewhere of our own first.
            var kept: URL?
            if let file, ok, allowed {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacTV-update-\(UUID().uuidString)")
                let target = folder.appendingPathComponent("update.dmg")
                kept = Log.updates.attempt("Keeping the download") {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: file, to: target)
                    return target
                }
            }
            Task { @MainActor in
                guard let self else { return }
                self.progress = nil
                self.download = nil
                guard let kept else {
                    self.state = .failed(LocalBuild.isPublicEdition ? "업데이트를 내려받지 못했습니다. 다시 시도하세요."
                        : (error == nil ? "The download didn't finish." : "Couldn't download the update."))
                    return
                }
                if now {
                    self.state = .installing
                    self.installDiskImage(kept, release: release)
                } else {
                    self.state = .ready(version: release.version, image: kept)
                    self.installIfIdle()
                }
            }
        }
        progress = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                if let self, case .downloading = self.state { self.state = .downloading(fraction) }
            }
        }
        download = task
        task.resume()
    }

    /// Mounts the disk image, checks the app inside, swaps it in and relaunches. The slow parts run off the main thread.
    private func installDiskImage(_ image: URL, release: Release? = nil) {
        let bundle = Bundle.main.bundleURL
        let work = image.deletingLastPathComponent()
        let requirement = Self.ownRequirement()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.replaceApp(at: bundle, withAppIn: image, work: work, requirement: requirement, release: release)
            try? FileManager.default.removeItem(at: work)
            Task { @MainActor in
                switch result {
                case .success(let backup):
                    if !Self.relaunch(bundle, backup: backup) {
                        Self.restoreBackup(backup, at: bundle)
                        self?.state = .failed("업데이트한 앱을 다시 열 수 없습니다.")
                    }
                case .failure(let error):
                    UserDefaults.standard.removeObject(forKey: "restartedForUpdate")
                    self?.state = .failed(error.message)
                }
            }
        }
    }

    struct InstallError: Error { let message: String }

    nonisolated static func replaceApp(at bundle: URL, withAppIn image: URL, work: URL,
                                       requirement: SecRequirement?, release: Release? = nil) -> Result<URL, InstallError> {
        let publicUpdate = release?.sha256 != nil
        if let digest = release?.sha256, (try? sha256(of: image)) != digest {
            return .failure(InstallError(message: "업데이트 파일의 체크섬이 일치하지 않습니다."))
        }
        let mount = work.appendingPathComponent("mount")
        Log.updates.attempt("Creating the mount point") {
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        }
        guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path]) else {
            return .failure(InstallError(message: publicUpdate ? "업데이트 파일을 열 수 없습니다." : "Couldn't open the update."))
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
        let apps = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard let found = publicUpdate ? (apps.count == 1 && apps.first?.lastPathComponent == "MacTV Custom.app" ? apps.first : nil)
                                       : apps.first else {
            return .failure(InstallError(message: publicUpdate ? "업데이트에 CouchDial 앱이 없습니다." : "The update has no app in it."))
        }
        let manager = FileManager.default
        let parent = bundle.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".CouchDial-update-\(UUID().uuidString)", isDirectory: true)
        let staged = staging.appendingPathComponent("CouchDial.app")
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(InstallError(message: "업데이트를 준비할 공간을 만들 수 없습니다."))
        }
        defer { try? manager.removeItem(at: staging) }
        guard run("/usr/bin/ditto", [found.path, staged.path]) else {
            return .failure(InstallError(message: publicUpdate ? "업데이트 앱을 복사하지 못했습니다." : "Couldn't copy the update."))
        }
        if publicUpdate {
            guard let old = Bundle(url: bundle), let new = Bundle(url: staged),
                  old.bundleIdentifier == "local.couch.tv.custom", new.bundleIdentifier == old.bundleIdentifier,
                  let installed = old.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let version = new.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  version == release?.version, isNewer(version, than: installed) else {
                return .failure(InstallError(message: "업데이트 앱의 식별자 또는 버전이 일치하지 않습니다."))
            }
        }
        guard let requirement, isSigned(staged, satisfying: requirement) else {
            return .failure(InstallError(message: publicUpdate ? "업데이트 앱의 서명이 현재 앱과 일치하지 않습니다."
                : "The update isn't signed like this copy of Mac TV. Download it from GitHub."))
        }
        let backupName = ".CouchDial-previous-\(UUID().uuidString).app"
        let backup = parent.appendingPathComponent(backupName)
        do {
            _ = try manager.replaceItemAt(bundle, withItemAt: staged, backupItemName: backupName,
                                          options: [.withoutDeletingBackupItem])
            return .success(backup)
        } catch {
            if manager.fileExists(atPath: backup.path) { restoreBackup(backup, at: bundle) }
            return .failure(InstallError(message: publicUpdate ? "업데이트를 설치하지 못했습니다. 다시 시도하세요."
                : "Couldn't replace Mac TV. Download the update from GitHub."))
        }
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func restoreBackup(_ backup: URL, at bundle: URL) {
        let manager = FileManager.default
        Log.updates.attempt("Restoring the previous app") {
            if manager.fileExists(atPath: bundle.path) {
                _ = try manager.replaceItemAt(bundle, withItemAt: backup, options: [.usingNewMetadataOnly])
            } else {
                try manager.moveItem(at: backup, to: bundle)
            }
        }
    }

    /// The running app's designated requirement: its identifier and signing certificate.
    private static func ownRequirement() -> SecRequirement? {
        var code: SecCode?, staticCode: SecStaticCode?, requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    private nonisolated static func isSigned(_ app: URL, satisfying requirement: SecRequirement) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Opens the new copy once this one has quit.
    private static func relaunch(_ bundle: URL, backup: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", """
            while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
            if /usr/bin/open -a "$2"; then
              /bin/rm -rf "$3"
            elif /bin/mv "$2" "$3.failed"; then
              if /bin/mv "$3" "$2"; then
                /usr/bin/open -a "$2"
              else
                /bin/mv "$3.failed" "$2"
              fi
            fi
            """, "sh", String(ProcessInfo.processInfo.processIdentifier), bundle.path, backup.path]
        do { try process.run() }
        catch {
            Log.updates.failure("Starting the relaunch", error)
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
