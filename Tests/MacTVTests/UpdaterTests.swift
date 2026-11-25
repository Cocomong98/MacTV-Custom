import Foundation
import Security
import Testing
@testable import MacTV

@Suite @MainActor
struct UpdaterTests {
    @Test
    func usesOnlyTheMatchingPublicReleaseAsset() throws {
        let name = "CouchDial-0.3.2.dmg"
        let download = "https://github.com/Cocomong98/MacTV-Custom/releases/download/v0.3.2/" + name
        let hash = String(repeating: "a", count: 64)
        let asset = ["name": name, "browser_download_url": download, "digest": "sha256:" + hash]
        var release: [String: Any] = [
            "tag_name": "v0.3.2", "draft": false, "prerelease": false, "body": "릴리스 변경 내용",
            "assets": [["name": "another.dmg"], asset],
        ]
        let result = try Updater.couchDialUpdate(from: release, currentVersion: "0.3.1")
        let update = try #require(result)
        #expect(update.version == "0.3.2")
        #expect(update.download.absoluteString == download)
        #expect(update.sha256 == hash)
        #expect(update.notes == "릴리스 변경 내용")
        #expect(try Updater.couchDialUpdate(from: release, currentVersion: "0.3.2") == nil)
        #expect(try Updater.couchDialUpdate(from: release, currentVersion: "0.4.0") == nil)
        release["assets"] = [asset.merging(["browser_download_url": "https://example.com/\(name)"]) { _, new in new }]
        #expect(throws: Updater.ReleaseError.self) { try Updater.couchDialUpdate(from: release, currentVersion: "0.3.1") }
        release["assets"] = [asset.filter { $0.key != "digest" }]
        #expect(throws: Updater.ReleaseError.self) { try Updater.couchDialUpdate(from: release, currentVersion: "0.3.1") }
        release["assets"] = [asset]
        release["prerelease"] = true
        #expect(throws: Updater.ReleaseError.self) { try Updater.couchDialUpdate(from: release, currentVersion: "0.3.1") }
        release["prerelease"] = false
        release["tag_name"] = "v0.3.2-preview"
        #expect(throws: Updater.ReleaseError.self) { try Updater.couchDialUpdate(from: release, currentVersion: "0.3.1") }
    }

    @Test
    func rejectsAnInvalidChecksumBeforeReplacingTheApp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("couchdial-checksum-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = folder.appendingPathComponent("MacTV Custom.app")
        let image = folder.appendingPathComponent("update.dmg")
        let original = Data("previous app".utf8)
        try original.write(to: installed)
        try Data("abc".utf8).write(to: image)
        #expect(try Updater.sha256(of: image) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let release = Updater.Release(version: "0.3.2", download: image, sha256: String(repeating: "0", count: 64))
        let result = Updater.replaceApp(at: installed, withAppIn: image, work: folder, requirement: nil, release: release)
        guard case .failure(let error) = result else { Issue.record("Corrupt update was accepted"); return }
        #expect(error.message.contains("체크섬"))
        #expect(try Data(contentsOf: installed) == original)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("mount").path))
    }

    @Test
    func installsASignedDMGAndKeepsThePreviousBundleForRecovery() throws {
        guard let fixture = ProcessInfo.processInfo.environment["MACTV_UPDATE_FIXTURE"] else { return }
        let fixtureRoot = URL(fileURLWithPath: fixture, isDirectory: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("couchdial-update-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = folder.appendingPathComponent("MacTV Custom.app")
        let image = fixtureRoot.appendingPathComponent("CouchDial-0.3.2.dmg")
        try FileManager.default.copyItem(at: fixtureRoot.appendingPathComponent("MacTV Custom.app"), to: installed)
        var requirement: SecRequirement?
        let expression = #"identifier "local.couch.tv.custom" and certificate leaf = H"00965dc4a85abd2b8c0994fc18d46be39931e849""#
        try #require(SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess)
        let digest = try Updater.sha256(of: image)
        let mismatched = Updater.Release(version: "0.3.3", download: image, sha256: digest)
        let rejected = Updater.replaceApp(at: installed, withAppIn: image, work: folder, requirement: requirement, release: mismatched)
        guard case .failure = rejected else { Issue.record("Mismatched version was accepted"); return }
        let release = Updater.Release(version: "0.3.2", download: image, sha256: digest)
        let backup = try Updater.replaceApp(at: installed, withAppIn: image, work: folder, requirement: requirement, release: release).get()
        func version(at app: URL) throws -> String? {
            let plist = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
            return info?["CFBundleShortVersionString"] as? String
        }
        #expect(try version(at: installed) == "0.3.2")
        #expect(try version(at: backup) == "0.3.1")
    }
    @Test
    func comparesDottedVersionsNumerically() {
        #expect(Updater.isNewer("0.12", than: "0.11.1"))
        #expect(Updater.isNewer("0.10", than: "0.9"))
        #expect(Updater.isNewer("1.0", than: "0.99"))
        #expect(Updater.isNewer("0.12.1", than: "0.12"))
        #expect(!Updater.isNewer("0.12", than: "0.12"))
        #expect(!Updater.isNewer("0.12", than: "0.12.0"))
        #expect(!Updater.isNewer("0.11.1", than: "0.12"))
    }
}
