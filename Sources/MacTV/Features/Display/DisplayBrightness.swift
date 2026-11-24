import AppKit
import Darwin

@MainActor
final class DisplayBrightness {
    enum Method: String, Sendable {
        case builtIn, ddc, betterDisplay
    }

    private struct Target: Equatable, Sendable {
        let id: String
        let displayID: CGDirectDisplayID
        let name: String
        let builtIn: Bool
    }

    private struct Reading {
        var sample: BetterDisplayBrightness.Sample?
        var pending = false
        var error: String?
        var updated = -Double.infinity
        var requestID = UUID()
    }

    private var external: [String: Reading] = [:]
    private let betterDisplay = BetterDisplayBrightness()
    private let onChange: (CGDirectDisplayID, Int) -> Void

    init(onChange: @escaping (CGDirectDisplayID, Int) -> Void) {
        self.onChange = onChange
    }

    nonisolated static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private var targets: [Target] {
        let screens = NSScreen.screens.compactMap { screen -> Target? in
            guard let id = Self.uuid(for: screen.displayID) else { return nil }
            return Target(id: id, displayID: screen.displayID, name: screen.localizedName,
                          builtIn: CGDisplayIsBuiltin(screen.displayID) != 0)
        }
        // A selector must identify exactly one active display, even if a device reports a duplicate UUID.
        return screens.filter { screen in screens.filter { $0.id == screen.id }.count == 1 }
    }

    func invalidate() {
        external.removeAll()
    }

    func snapshot() -> [[String: Any]] {
        let now = ProcessInfo.processInfo.systemUptime
        return targets.map { target in
            var info: [String: Any] = ["id": target.id, "name": target.name, "builtIn": target.builtIn]
            if target.builtIn {
                info["method"] = Method.builtIn.rawValue
                if let percent = BuiltInBrightness.read(target.displayID) {
                    info["value"] = percent
                } else {
                    info["error"] = "Built-in brightness is unavailable."
                }
                return info
            }
            let prior = external[target.id] ?? Reading()
            if !prior.pending, now - prior.updated >= 10 {
                startExternal(target, level: nil, prior: prior)
            }
            let reading = external[target.id] ?? prior
            info["pending"] = reading.pending
            if let sample = reading.sample {
                info["value"] = sample.percent
                info["method"] = sample.method.rawValue
            }
            if let error = reading.error { info["error"] = error }
            return info
        }
    }

    func set(id: String, level: Int, method: Method) -> HTTPResponse {
        guard (0...100).contains(level), let target = targets.first(where: { $0.id == id }) else {
            return .json(["error": "Choose a connected display and a brightness from 0 to 100."], status: "400 Bad Request")
        }
        if target.builtIn {
            guard method == .builtIn else { return Self.methodChanged() }
            if let confirmed = BuiltInBrightness.set(level, displayID: target.displayID) {
                onChange(target.displayID, confirmed)
                return .json(["value": confirmed])
            }
            return .json(["error": "The Mac did not confirm the brightness change."], status: "503 Service Unavailable")
        }
        let reading = external[id] ?? Reading()
        guard !reading.pending, let sample = reading.sample else {
            return .json(["error": "Wait for the monitor to report its brightness."], status: "409 Conflict")
        }
        guard sample.method == method else { return Self.methodChanged() }
        startExternal(target, level: level, prior: reading)
        guard external[id]?.pending == true else {
            return .json(["error": "BetterDisplay is not available."], status: "503 Service Unavailable")
        }
        return .json(["pending": true], status: "202 Accepted")
    }

    private static func methodChanged() -> HTTPResponse {
        .json(["error": "The brightness control changed. Try again after it refreshes."], status: "409 Conflict")
    }

    private func startExternal(_ target: Target, level: Int?, prior: Reading) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: BetterDisplayBrightness.bundleID).isEmpty else {
            external[target.id] = Reading(error: "Open BetterDisplay to control this monitor's brightness.",
                                          updated: ProcessInfo.processInfo.systemUptime)
            return
        }
        let requestID = UUID()
        var pending = prior
        pending.requestID = requestID
        pending.pending = true
        pending.error = nil
        external[target.id] = pending
        Task { [weak self, betterDisplay] in
            let result = await betterDisplay.brightness(uuid: target.id, displayID: target.displayID,
                                                        level: level, prior: prior.sample)
            guard let self, self.external[target.id]?.requestID == requestID else { return }
            guard self.targets.contains(target) else {
                self.external[target.id] = nil
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            if let result {
                self.external[target.id] = Reading(sample: result, updated: now)
                if level != nil { self.onChange(target.displayID, result.percent) }
            } else {
                let error = level == nil ? "BetterDisplay could not read this monitor's brightness."
                    : "Could not confirm this monitor's brightness change."
                self.external[target.id] = Reading(error: error, updated: now)
            }
        }
    }
}

@MainActor
private enum BuiltInBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    // DisplayServices has no public SDK API. Missing symbols leave this control unavailable.
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let get = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let set = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    static func read(_ displayID: CGDirectDisplayID) -> Int? {
        var value: Float = 0
        guard set != nil, CGDisplayIsActive(displayID) != 0, CGDisplayIsBuiltin(displayID) != 0,
              get?(displayID, &value) == 0, (0...1).contains(value) else { return nil }
        return Int((value * 100).rounded())
    }

    static func set(_ level: Int, displayID: CGDirectDisplayID) -> Int? {
        guard read(displayID) != nil, set?(displayID, Float(level) / 100) == 0 else { return nil }
        return read(displayID)
    }
}

private actor BetterDisplayBrightness {
    struct Sample: Sendable {
        let percent: Int
        let method: DisplayBrightness.Method
        var maximum: Int?
    }

    static let bundleID = "pro.betterdisplay.BetterDisplay"
    private let executable = URL(fileURLWithPath: "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay")

    func brightness(uuid: String, displayID: CGDirectDisplayID, level: Int?, prior: Sample?) -> Sample? {
        guard CGDisplayIsActive(displayID) != 0, CGDisplayIsBuiltin(displayID) == 0,
              DisplayBrightness.uuid(for: displayID) == uuid else { return nil }
        let target = ["-UUID=\(uuid)", "-type=Display"]
        if let level {
            // A write must use the same method that the phone displayed.
            switch prior?.method {
            case .ddc: return ddc(target, level: level, knownMaximum: prior?.maximum)
            case .betterDisplay: return combined(target, level: level)
            default: return nil
            }
        }
        if prior?.method == .betterDisplay { return combined(target) }
        return ddc(target, knownMaximum: prior?.maximum) ?? combined(target)
    }

    private func ddc(_ target: [String], level: Int? = nil, knownMaximum: Int?) -> Sample? {
        let target = target + ["-feature=ddc", "-vcp=luminance"]
        if let level {
            guard let knownMaximum else { return nil }
            let raw = Int((Double(level) * Double(knownMaximum) / 100).rounded())
            guard run(["set"] + target + ["-value=\(raw)"]) != nil else { return nil }
        }
        guard let output = run(["get"] + target + ["-value"]), let raw = Int(output),
              let maximum = knownMaximum ?? run(["get"] + target + ["-max"]).flatMap(Int.init),
              (1...65_535).contains(maximum), (0...maximum).contains(raw) else { return nil }
        return Sample(percent: Int((Double(raw) * 100 / Double(maximum)).rounded()), method: .ddc, maximum: maximum)
    }

    // Use the same scale as the BetterDisplay menu, including any configured hardware range.
    private func combined(_ target: [String], level: Int? = nil) -> Sample? {
        if let level {
            let percent = Double(level) / 100
            guard run(["set"] + target + ["-brightness=\(percent)"]) != nil else { return nil }
        }
        guard let output = run(["get"] + target + ["-brightness"]),
              let value = Double(output), (0...1).contains(value) else { return nil }
        let percent = Int((value * 100).rounded())
        if let level, abs(percent - level) > 1 { return nil }
        return Sample(percent: percent, method: .betterDisplay)
    }

    private func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        guard done.wait(timeout: .now() + 3) == .success else {
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
