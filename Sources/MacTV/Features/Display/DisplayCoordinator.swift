import AppKit
import IOKit.ps
import IOKit.pwr_mgt

/// Manages display power assertions, lid sleep overrides, and external screen configuration.
@MainActor
final class DisplayCoordinator: ObservableObject {
    weak var tv: TVController?
    weak var tvMode: TVMode?

    private let keepAwake = KeepAwake()
    private let macAwake = KeepAwake(kIOPMAssertionTypePreventUserIdleSystemSleep)
    private var powerTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?
    private var screensObserver: NSObjectProtocol?
    private var lidGuard: Process?
    private static let lowBattery = 20

    @Published private(set) var power = PowerStatus()
    @Published private(set) var lidSleepOff = false
    @Published private(set) var displaysSleeping = false
    private var lastDisplayWakeRequest = -Double.infinity
    let brightness: DisplayBrightness
    let levelOSD: SideLevelOSD

    private let preferences: Preferences

    init(tv: TVController? = nil, preferences: Preferences = .shared) {
        self.tv = tv
        self.preferences = preferences
        let osd = SideLevelOSD()
        levelOSD = osd
        brightness = DisplayBrightness { [weak osd] displayID, value in
            osd?.show(.brightness(value), on: displayID)
        }
    }

    /// Prevent the Mac from sleeping automatically while Mac TV is open so the remote remains responsive.
    var keepMacAwake: Bool {
        get { preferences.keepMacAwake }
        set { preferences.keepMacAwake = newValue; applyPower() }
    }

    /// Keep running with the lid closed even on battery or without a TV connected.
    var lidOverride: Bool {
        get { preferences.lidOverride }
        set { preferences.lidOverride = newValue; applyPower() }
    }

    /// One line for the remote about what closing the lid will do.
    var lidStatus: String {
        if lidSleepOff {
            return power.onAC ? "Stays awake with the lid closed. Keep the Mac ventilated."
                : "Stays awake with the lid closed until the battery drops below \(Self.lowBattery)%."
        }
        if power.closedLidModeReady { return "Safe to close the lid: the TV and power are connected." }
        return "Closing the lid sleeps the Mac."
    }

    func startPowerManagement() {
        applyPower()
        // macOS says when the power source, battery level or displays change, so there's nothing
        // to poll for. Only a lid override needs a timer (`updateLidTimer`).
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let coordinator = Unmanaged<DisplayCoordinator>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { coordinator.refreshPower() }
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.brightness.invalidate()
                self?.levelOSD.dismiss()
                self?.refreshPower()
            }
        }
        // Closing the lid with a TV connected switches the built-in display off.
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.brightness.invalidate()
                self?.levelOSD.dismiss()
                self?.refreshPower()
            }
        }
    }

    func stopPowerManagement() {
        levelOSD.dismiss()
        powerTimer?.invalidate()
        powerTimer = nil
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        macAwake.release()
        if lidSleepOff { releaseLid() }
    }

    func refreshPower() {
        let now = PowerStatus.current()
        if now != power {
            power = now
        }
        guard lidSleepOff else { return }
        if let reason = lidOverrideStopReason() {
            lidOverride = false
            Log.system.notice("Lid override stopped: \(reason, privacy: .public)")
            tv?.showToast(reason)
        } else {
            LidSleep.setPrevented(true)
        }
    }

    func applyPower() {
        power = PowerStatus.current()
        keepMacAwake ? macAwake.hold(reason: "Mac TV is open, so the phone remote can reach it") : macAwake.release()

        if lidOverride, lidSleepOff == false {
            if let reason = lidOverrideStopReason() {
                preferences.lidOverride = false
                tv?.showToast(reason)
            } else if LidSleep.setPrevented(true) {
                lidSleepOff = true
                lidGuard = LidSleep.startGuard()
            } else {
                preferences.lidOverride = false
                tv?.showToast("이 Mac에서는 덮개를 닫은 채 깨어 있게 유지할 수 없습니다.")
            }
        } else if !lidOverride, lidSleepOff {
            releaseLid()
        }
        updateLidTimer()
    }

    /// powerd rewrites the lid switch when power or displays change, and at times of its own, so
    /// while lid sleep is off it's set again every few seconds, and the battery and heat checked.
    private func updateLidTimer() {
        if lidSleepOff, powerTimer == nil {
            powerTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPower() }
            }
        } else if !lidSleepOff {
            powerTimer?.invalidate()
            powerTimer = nil
        }
    }

    private func releaseLid() {
        LidSleep.restore()
        lidGuard?.terminate()
        lidGuard = nil
        lidSleepOff = false
    }

    /// Why the lid override has to stop now, if it does: a closed Mac that never sleeps can run
    /// its battery flat or overheat in a bag.
    private func lidOverrideStopReason() -> String? {
        if !power.onAC, let battery = power.battery, battery < Self.lowBattery {
            return "배터리가 부족합니다. 이제 덮개를 닫으면 Mac이 잠자기 상태로 전환됩니다."
        }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return "Mac의 온도가 높습니다. 이제 덮개를 닫으면 Mac이 잠자기 상태로 전환됩니다."
        default: return nil
        }
    }

    func noteDisplaySleep(_ sleeping: Bool) {
        displaysSleeping = sleeping
        if sleeping {
            levelOSD.dismiss()
            tv?.screensaverOff()
        }
    }

    func wakeDisplays() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDisplayWakeRequest >= 0.5 else { return }
        if SystemControl.displayOn() { lastDisplayWakeRequest = now }
        else { tv?.showToast("화면을 깨우지 못했습니다. 화면 깨우기를 다시 눌러 보세요.") }
    }

    func holdPlaybackKeepAwake(reason: String) {
        keepAwake.hold(reason: reason)
    }

    func releasePlaybackKeepAwake() {
        keepAwake.release()
    }

    var playbackScreen: NSScreen? {
        tvMode?.playbackScreen
            ?? tv?.window?.screen ?? NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) == 0 }
            ?? NSScreen.main
    }

    func resetPairingFocus() {
        tvMode?.resetPairingFocus()
    }

    /// Report current connected displays and refresh rates.
    var displayDiagnostics: [(name: String, width: Int, height: Int, refreshRate: Double)] {
        NSScreen.screens.compactMap { screen in
            guard let mode = CGDisplayCopyDisplayMode(screen.displayID) else { return nil }
            return (screen.localizedName, mode.pixelWidth, mode.pixelHeight, mode.refreshRate)
        }
    }
}

