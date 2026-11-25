import SwiftUI

/// The TV's Settings: a list of sections, each opening a page of its own, with the focused
/// section's symbol large on the left like tvOS. Driven by the D-pad, the keyboard or the mouse.
struct SettingsPanel: Equatable {
    enum Section: Int, CaseIterable {
        case profiles, remotes, watching, screenSaver, sounds, apps, movies, dedicatedTV, power, about
    }

    /// One row on a section's page.
    enum Row: Equatable {
        case phoneRemote, pairingCode, controller
        case sleepTimer, autoSkip, autoNext, playbackCheck, websitePlayer
        case addApp, arrangeApps
        case dedicatedTV, preferredDisplay, launchAtLogin
        case wallpaper, aerialCategory, saverDelay, saverClock, saverPreview
        case audioOutput, feedback
        case keepMacAwake, lidOverride, screenOff, sleepMac
        case version, update, autoUpdate, source, report, analytics

        /// Left/right steps or toggles this row; otherwise left goes back.
        var adjustsWithArrows: Bool {
            switch self {
            case .sleepTimer, .wallpaper, .aerialCategory, .saverDelay, .saverClock, .feedback,
                 .autoSkip, .autoNext, .websitePlayer, .dedicatedTV, .preferredDisplay, .launchAtLogin,
                 .keepMacAwake, .lidOverride, .analytics, .autoUpdate:
                true
            default:
                false
            }
        }

        /// Verb for the OK / Select hint on this row.
        var okVerb: String {
            switch self {
            case .autoSkip, .autoNext, .saverClock, .feedback, .keepMacAwake, .lidOverride,
                 .analytics, .autoUpdate, .dedicatedTV, .launchAtLogin:
                "전환"
            case .sleepTimer, .websitePlayer, .preferredDisplay, .wallpaper, .aerialCategory, .saverDelay:
                // ←→ already says Change; OK advances the same value.
                "선택"
            case .phoneRemote, .addApp, .arrangeApps, .playbackCheck, .audioOutput:
                "열기"
            case .saverPreview: "미리 보기"
            case .screenOff: "끄기"
            case .sleepMac: "잠자기"
            case .report: "복사"
            case .update: "업데이트"
            case .controller: "선택"
            // OK does nothing on these, so there's no OK hint.
            case .pairingCode, .version, .source: ""
            }
        }
    }

    var section: Section = .profiles
    /// On the section's own page rather than the list of sections.
    var open = false
    var row = 0
    /// Sleep Mac asks for a second press, like the phone remote's double tap.
    var confirmingSleep = false
}

extension SettingsPanel.Section {
    var title: String {
        switch self {
        case .profiles: "프로필"
        case .remotes: "리모컨 및 기기"
        case .watching: "시청"
        case .screenSaver: "화면 보호기"
        case .sounds: "사운드 및 햅틱"
        case .apps: "앱"
        case .movies: "동영상"
        case .dedicatedTV: "전용 TV"
        case .power: "전원"
        case .about: "앱 정보"
        }
    }

    var symbol: String {
        switch self {
        case .profiles: "person.2.fill"
        case .remotes: "appletvremote.gen4.fill"
        case .watching: "play.tv.fill"
        case .screenSaver: "sparkles.tv.fill"
        case .sounds: "speaker.wave.2.fill"
        case .apps: "square.grid.2x2.fill"
        case .movies: "film.stack.fill"
        case .dedicatedTV: "tv.fill"
        case .power: "bolt.fill"
        case .about: "info.circle"
        }
    }

    var blurb: String {
        switch self {
        case .profiles: "프로필마다 앱과 로그인 상태를 따로 관리합니다."
        case .remotes: "휴대전화를 리모컨으로 연결하고 게임 컨트롤러를 확인합니다."
        case .watching: "오프닝 건너뛰기, 다음 회차 재생, 취침 타이머를 설정합니다."
        case .screenSaver: "홈 화면에서 일정 시간 동안 조작하지 않으면 표시됩니다. 아무 버튼이나 누르면 홈으로 돌아갑니다."
        case .sounds: "이동 소리와 트랙패드 또는 컨트롤러의 진동을 설정합니다."
        case .apps: "웹사이트, Mac 앱, Steam 게임을 홈 화면에 추가합니다."
        case .movies: "폴더에 있는 동영상 파일을 재생합니다. MKV도 지원합니다."
        case .dedicatedTV: "재생 화면을 선택하고 CouchDial 자동 실행을 설정합니다."
        case .power: "리모컨을 쓸 수 있도록 Mac을 깨어 있게 유지하고 덮개를 닫을 때의 동작을 설정합니다."
        case .about: "CouchDial은 무료 오픈 소스 앱입니다."
        }
    }

    /// The rows on its page; empty for sections that open somewhere else.
    @MainActor var rows: [SettingsPanel.Row] {
        switch self {
        case .remotes: [.phoneRemote, .pairingCode, .controller]
        case .watching: [.sleepTimer, .autoSkip, .autoNext, .playbackCheck, .websitePlayer]
        case .screenSaver: ScreenSaverSettings.wallpaper == .aerials && !Aerials.categories.isEmpty
            ? [.wallpaper, .aerialCategory, .saverDelay, .saverClock, .saverPreview]
            : [.wallpaper, .saverDelay, .saverClock, .saverPreview]
        case .sounds: [.audioOutput, .feedback]
        case .apps: [.addApp, .arrangeApps]
        case .dedicatedTV: [.dedicatedTV, .preferredDisplay, .launchAtLogin]
        case .power: [.keepMacAwake, .lidOverride, .screenOff, .sleepMac]
        case .about: [.version] + (LocalBuild.isCustom ? [] : [.update, .autoUpdate])
            + [.source, .report] + (Analytics.available ? [.analytics] : [])
        case .profiles, .movies: []
        }
    }
}

extension TVController {
    static let sleepTimerSteps = [0, 15, 30, 60, 90]

    /// Minutes left on the sleep timer; 0 when it's off.
    var sleepMinutesLeft: Int {
        sleepAt.map { max(1, Int(($0.timeIntervalSinceNow / 60).rounded(.up))) } ?? 0
    }

    func openSettings() {
        settings = SettingsPanel()
    }

    func handleSettings(_ command: RemoteCommand) {
        guard var panel = settings else { return }
        if case .select = command {} else { panel.confirmingSleep = false }

        guard panel.open else {
            let sections = SettingsPanel.Section.allCases
            switch command {
            case .back:
                settings = nil
                return
            case .move(.up):
                panel.section = sections[max(0, panel.section.rawValue - 1)]
            case .move(.down):
                panel.section = sections[min(sections.count - 1, panel.section.rawValue + 1)]
            case .move(.right), .select:
                settings = panel
                openSection(panel.section)
                return
            default:
                break
            }
            settings = panel
            return
        }

        let rows = panel.section.rows
        let row = rows[min(panel.row, max(rows.count - 1, 0))]
        switch command {
        case .back:
            panel.open = false
            panel.row = 0
        case .move(.left) where !row.adjustsWithArrows:
            panel.open = false
            panel.row = 0
        case .move(.up):
            panel.row = max(0, panel.row - 1)
        case .move(.down):
            panel.row = min(rows.count - 1, panel.row + 1)
        case .move(let direction) where direction == .left || direction == .right:
            settings = panel
            adjustSetting(row, forward: direction == .right)
            return
        case .select:
            settings = panel
            activateSetting(row)
            return
        default:
            break
        }
        settings = panel
    }

    /// Opens a section's page, or goes where the section lives.
    func openSection(_ section: SettingsPanel.Section) {
        Analytics.send(.settingsOpened, ["section": String(describing: section)])
        switch section {
        case .profiles:
            openProfiles()
        case .movies:
            settings = nil
            openMovies()
        default:
            settings?.section = section
            settings?.open = true
            settings?.row = 0
        }
    }

    /// Left and right: step a value, or switch a setting off and on.
    private func adjustSetting(_ row: SettingsPanel.Row, forward: Bool) {
        switch row {
        case .dedicatedTV: setDedicatedTVMode(forward)
        case .preferredDisplay: stepTVDisplay(forward ? 1 : -1)
        case .launchAtLogin: setLaunchAtLogin(forward)
        case .sleepTimer: stepSleepTimer(by: forward ? 1 : -1, wrap: false)
        case .websitePlayer: stepWebsitePlayer(forward: forward)
        case .wallpaper: ScreenSaverSettings.step(forward ? 1 : -1)
        case .aerialCategory: ScreenSaverSettings.stepAerialCategory(forward ? 1 : -1)
        case .saverDelay: ScreenSaverSettings.stepDelay(forward ? 1 : -1)
        case .saverClock: ScreenSaverSettings.showClock = forward
        case .feedback: feedback.enabled = forward
        case .autoSkip: autoSkip = forward
        case .autoNext: autoNext = forward
        case .keepMacAwake: keepMacAwake = forward
        case .lidOverride: lidOverride = forward
        case .analytics: Analytics.setConsent(forward, context: analyticsContext)
        case .autoUpdate: updater.automatic = forward
        default: return
        }
    }

    func activateSetting(_ row: SettingsPanel.Row) {
        if let index = settings?.section.rows.firstIndex(of: row) { settings?.row = index }
        switch row {
        case .phoneRemote: pairing = true
        case .pairingCode: break
        case .controller:
            showToast(controller == nil ? "시스템 설정 › Bluetooth에서 컨트롤러를 연결하세요." : "컨트롤러의 메뉴 버튼을 누르면 언제든 홈으로 돌아갑니다.")
        case .addApp:
            settings = nil
            adder = AppAdder()
        case .arrangeApps: openOrganizer()
        case .playbackCheck: openPlaybackCheck()
        case .dedicatedTV: setDedicatedTVMode(!dedicatedTVMode)
        case .preferredDisplay: stepTVDisplay(1, wrap: true)
        case .launchAtLogin: setLaunchAtLogin(!launchAtLogin)
        case .sleepTimer: stepSleepTimer(by: 1, wrap: true)
        case .websitePlayer: stepWebsitePlayer()
        case .autoSkip: autoSkip.toggle()
        case .autoNext: autoNext.toggle()
        case .wallpaper:
            if ScreenSaverSettings.wallpaper == .photos { ScreenSaverSettings.choosePhotosFolder() } else { ScreenSaverSettings.step(1) }
        case .aerialCategory: ScreenSaverSettings.stepAerialCategory(1, wrap: true)
        case .saverDelay: ScreenSaverSettings.stepDelay(1, wrap: true)
        case .saverClock: ScreenSaverSettings.showClock.toggle()
        case .saverPreview:
            settings = nil
            showScreensaver()
        case .feedback: feedback.enabled.toggle()
        case .audioOutput:
            settings = nil
            openAudioPicker()
        case .keepMacAwake: keepMacAwake.toggle()
        case .lidOverride: lidOverride.toggle()
        case .screenOff: SystemControl.displayOff()
        case .sleepMac:
            if settings?.confirmingSleep == true {
                goHome()
                SystemControl.sleepNow()
            } else {
                settings?.confirmingSleep = true
            }
        case .version, .source: break
        case .report: DiagnosticReport.copy(from: self)
        case .update: updater.activate()
        case .autoUpdate: updater.automatic.toggle()
        case .analytics: Analytics.setConsent(!Analytics.enabled, context: analyticsContext)
        }
    }

    /// Moves the sleep timer to the next or previous step: Off, 15, 30, 60, 90 minutes.
    func stepSleepTimer(by step: Int, wrap: Bool) {
        let steps = Self.sleepTimerSteps
        let current = steps.firstIndex { $0 >= sleepMinutesLeft } ?? 0
        var next = current + step
        next = wrap ? (next + steps.count) % steps.count : min(max(next, 0), steps.count - 1)
        guard next != current else { return }
        setSleepTimer(minutes: steps[next])
    }

    /// The short summary beside each section in the list.
    func settingsDetail(_ section: SettingsPanel.Section) -> String {
        switch section {
        case .profiles: return profiles.all.map(\.name).joined(separator: ", ")
        case .remotes:
            let parts = [phonePaired ? "휴대전화" : nil, controller?.name].compactMap { $0 }
            return parts.isEmpty ? "연결하기" : parts.joined(separator: " · ")
        case .watching: return autoSkip ? "오프닝 건너뛰기" : "오프닝 재생"
        case .screenSaver: return "\(ScreenSaverSettings.wallpaper.title) · \(ScreenSaverSettings.delayMinutes)분"
        case .sounds: return feedback.enabled ? "켬" : "끔"
        case .apps: return "홈 화면에 \(services.filter { $0.kind != .settings && $0.kind != .addApp }.count)개"
        case .movies:
            let count = movieLibrary.folders.count
            return "폴더 \(count)개"
        case .dedicatedTV: return dedicatedTVMode ? "켬 · \(preferredTVDisplayName)" : "끔"
        case .power: return keepMacAwake ? "Mac을 깨어 있게 유지" : "평소대로 잠자기"
        case .about:
            if let version = updater.availableVersion { return "\(version)으로 업데이트" }
            return "버전 \(Updater.currentVersion)"
        }
    }
}

// MARK: Views

struct SettingsSheet: View {
    @ObservedObject var tv: TVController
    @ObservedObject private var updater: Updater
    @Environment(\.canvasSize) private var canvas
    @Namespace private var focusSpace

    init(tv: TVController) {
        _tv = ObservedObject(wrappedValue: tv)
        _updater = ObservedObject(wrappedValue: tv.updater)
    }

    var body: some View {
        let panel = tv.settings ?? SettingsPanel()
        HStack(spacing: 0) {
            hero(panel.section)
                .frame(width: 780, alignment: .leading)
                .padding(.leading, TVLayout.edge)
            VStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 28) {
                    Group {
                        if panel.open {
                            page(panel)
                        } else {
                            sections(panel)
                        }
                    }
                    .padding(20)
                    .tvPanel(in: RoundedRectangle(cornerRadius: TVLayout.panelRadius))
                    InputHintsBar(tv: tv, set: settingsHints(panel))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, TVLayout.edge)
            .padding(.leading, 20)
        }
        .foregroundStyle(.white)
        .frame(width: canvas.width, height: canvas.height)
        .animation(Motion.focus, value: panel)
    }

    /// One primary OK verb — never Change + Toggle together (same action twice).
    private func settingsHints(_ panel: SettingsPanel) -> HintSet {
        guard panel.open else { return .list }
        let rows = panel.section.rows
        guard rows.indices.contains(panel.row) else { return .list }
        let row = rows[panel.row]
        var actions: [HintAction] = [.moveVertical("이동")]
        let ok = (row == .sleepMac && panel.confirmingSleep) ? "확인" : row.okVerb
        if row.adjustsWithArrows, ok == "전환" {
            // ←→ and OK both flip the switch — show Toggle only.
            actions.append(.select("전환"))
        } else if row.adjustsWithArrows {
            // Multi-value steppers: ←→ is the real control; OK also advances.
            actions.append(.moveHorizontal("변경"))
        } else if !ok.isEmpty {
            actions.append(.select(ok))
        }
        actions.append(.back("닫기"))
        return .custom(actions)
    }

    private func hero(_ section: SettingsPanel.Section) -> some View {
        VStack(alignment: .leading, spacing: 34) {
            Text("설정").font(.tv(.caption2, emphasized: true)).foregroundStyle(TVLayout.secondaryText)
            Image(systemName: section.symbol)
                .font(.system(size: 130, weight: .regular))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 300, height: 300)
                // A plain tile, not glass: Settings sits on a frosted backdrop, and glass there would read flat.
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 72, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 72, style: .continuous).strokeBorder(.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 14) {
                Text(section.title).font(.tv(.title2, emphasized: true))
                Text(section.blurb).font(.tv(.caption1)).foregroundStyle(TVLayout.secondaryText)
                    .lineSpacing(5).frame(maxWidth: 560, alignment: .leading)
            }
            .id(section)
            .transition(.opacity)
        }
        .animation(Motion.appear, value: section)
    }

    private func sections(_ panel: SettingsPanel) -> some View {
        VStack(spacing: 10) {
            ForEach(SettingsPanel.Section.allCases, id: \.self) { section in
                let focused = panel.section == section
                row(focused: focused, warning: false) {
                    Image(systemName: section.symbol).font(.system(size: 27, weight: .medium))
                        .frame(width: 40).opacity(0.9)
                    Text(section.title).font(.tv(.body))
                    Spacer(minLength: 16)
                    Text(tv.settingsDetail(section)).font(.tv(.caption1)).opacity(0.55).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 20, weight: .semibold)).opacity(0.4)
                } action: {
                    tv.settings?.section = section
                    tv.openSection(section)
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ panel: SettingsPanel) -> some View {
        let rows = panel.section.rows
        VStack(alignment: .leading, spacing: 10) {
            if panel.section == .power {
                Text(tv.lidStatus).font(.tv(.caption2)).foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 6).padding(.bottom, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let focused = panel.row == index
                if row == .wallpaper {
                    wallpapers(focused: focused)
                } else if row == .aerialCategory {
                    aerialCategories(focused: focused)
                } else {
                    let warning = row == .sleepMac && panel.confirmingSleep
                    self.row(focused: focused, warning: warning) {
                        content(row, panel: panel)
                    } action: {
                        tv.activateSetting(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ row: SettingsPanel.Row, panel: SettingsPanel) -> some View {
        switch row {
        case .phoneRemote:
            title("QR 코드 표시")
            chevron
        case .pairingCode:
            title("연결 코드")
            value(tv.remoteToken)
        case .controller:
            if let controller = tv.controller {
                title(controller.name)
                value(controller.battery.map { "배터리 \(Int($0 * 100))%" } ?? "연결됨")
                Image(systemName: controller.batterySymbol).font(.system(size: 26))
            } else {
                title("게임 컨트롤러")
                value("연결 안 됨")
            }
        case .addApp:
            title("앱 추가")
            chevron
        case .arrangeApps:
            title("앱 정리")
            chevron
        case .playbackCheck:
            title("재생 점검")
            chevron
        case .dedicatedTV:
            title(tv.dedicatedTVMode ? "TV 모드 종료" : "TV 모드 시작")
            SettingSwitch(on: tv.dedicatedTVMode)
        case .preferredDisplay:
            title("기본 재생 화면")
            stepper(tv.preferredTVDisplayName, active: panel.section.rows[panel.row] == .preferredDisplay)
        case .launchAtLogin:
            title("로그인할 때 실행")
            if tv.loginNeedsApproval { value("권한 허용 필요") }
            else { SettingSwitch(on: tv.launchAtLogin) }
        case .sleepTimer:
            title("취침 타이머")
            let minutes = tv.sleepMinutesLeft
            stepper(minutes == 0 ? "끔" : "\(minutes)분 남음", active: panel.row == 0)
        case .websitePlayer:
            title("웹사이트 재생 앱")
            let player = tv.websitePlayerName
            stepper(player == "Built-in" ? "내장 플레이어" : player, active: panel.section.rows[panel.row] == .websitePlayer)
        case .autoSkip:
            title("오프닝 및 지난 이야기 건너뛰기")
            SettingSwitch(on: tv.autoSkip)
        case .autoNext:
            title("다음 회차 자동 재생")
            SettingSwitch(on: tv.autoNext)
        case .saverDelay:
            title("시작 대기 시간")
            stepper("\(ScreenSaverSettings.delayMinutes)분", active: tv.settings?.section.rows[panel.row] == .saverDelay)
        case .saverClock:
            title("시계 표시")
            SettingSwitch(on: ScreenSaverSettings.showClock)
        case .saverPreview:
            title("미리 보기")
            chevron
        case .audioOutput:
            title("오디오 출력")
            value(tv.currentAudioDevice?.name ?? "스피커")
            chevron
        case .feedback:
            title("사운드 및 햅틱")
            SettingSwitch(on: tv.feedback.enabled)
        case .keepMacAwake:
            title("CouchDial 실행 중 Mac을 깨어 있게 유지")
            SettingSwitch(on: tv.keepMacAwake)
        case .lidOverride:
            title("덮개를 닫아도 깨어 있기")
            SettingSwitch(on: tv.lidOverride)
        case .screenOff:
            title("화면 끄기")
        case .sleepMac:
            title(panel.confirmingSleep ? "한 번 더 누르면 Mac이 잠자기 상태로 전환됩니다." : "Mac 잠자기")
        case .version:
            title("버전")
            value(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        case .update:
            switch updater.state {
            case .failed(let message):
                title("소프트웨어 업데이트")
                value(message)
            case .available(let version, _):
                title("소프트웨어 업데이트")
                value("\(version) 설치")
            case .ready(let version, _):
                title("소프트웨어 업데이트")
                value("\(version) 설치")
            case .downloading(let fraction):
                title("소프트웨어 업데이트")
                value("다운로드 중 \(Int(fraction * 100))%")
            case .installing:
                title("소프트웨어 업데이트")
                value("설치 중…")
            case .checking:
                title("소프트웨어 업데이트")
                value("확인 중…")
            case .upToDate:
                title("소프트웨어 업데이트")
                value("최신 버전")
            case .idle:
                title("소프트웨어 업데이트")
                value("지금 확인")
            }
        case .autoUpdate:
            title("자동 업데이트")
            SettingSwitch(on: updater.automatic)
        case .source:
            title("소스 코드")
            value("github.com/Arunprakaash/mac-tv")
        case .report:
            title("진단 보고서 복사")
            value("복사")
        case .analytics:
            title("익명 사용 정보 공유")
            SettingSwitch(on: Analytics.enabled)
        case .wallpaper, .aerialCategory:
            EmptyView()
        }
    }

    /// The screen saver's wallpapers, side by side; left and right choose one.
    private func wallpapers(focused: Bool) -> some View {
        let chosen = ScreenSaverSettings.wallpaper
        return VStack(alignment: .leading, spacing: 12) {
            Text("배경").font(.tv(.caption2, emphasized: true)).tracking(1.4).opacity(0.5).padding(.leading, 6)
            HStack(spacing: 18) {
                ForEach(ScreenSaverSettings.Wallpaper.allCases, id: \.self) { wallpaper in
                    let selected = wallpaper == chosen
                    VStack(alignment: .leading, spacing: 10) {
                        WallpaperThumb(wallpaper: wallpaper)
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(.white.opacity(selected ? (focused ? 1 : 0.6) : 0.12), lineWidth: selected ? 4 : 1)
                            }
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 30))
                                        .symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                                        .padding(10).transition(.scale.combined(with: .opacity))
                                }
                            }
                            .scaleEffect(selected && focused ? 1.05 : 1)
                            .shadow(color: .black.opacity(selected && focused ? 0.45 : 0), radius: 18, y: 12)
                        Text(wallpaper.title).font(.tv(.caption2))
                            .opacity(selected ? 1 : 0.6).padding(.leading, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tv.settings?.row = 0
                        if selected, wallpaper == .photos { ScreenSaverSettings.choosePhotosFolder() }
                        ScreenSaverSettings.wallpaper = wallpaper
                    }
                }
            }
            .animation(Motion.focus, value: chosen)
        }
        .padding(.bottom, 14)
    }

    /// Apple's live wallpaper categories, the same as System Settings › Wallpaper; left and right choose one.
    private func aerialCategories(focused: Bool) -> some View {
        let chosen = ScreenSaverSettings.aerialCategory
        let choices: [(id: String?, name: String)] = [(nil, "모두 섞어서 재생")] + Aerials.categories.map { ($0.id, $0.name) }
        // Two rows of four, so every name fits.
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 14) {
            ForEach(choices, id: \.name) { choice in
                let selected = choice.id == chosen
                VStack(alignment: .leading, spacing: 8) {
                    Color.clear
                        .overlay {
                            if let thumb = Aerials.thumbnail(forCategory: choice.id), let image = ScreenImages.image(thumb, maxPixels: 400) {
                                Image(nsImage: image).resizable().scaledToFill()
                            }
                        }
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(selected ? (focused ? 1 : 0.6) : 0.12), lineWidth: selected ? 3 : 1)
                        }
                        .scaleEffect(selected && focused ? 1.06 : 1)
                    Text(choice.name).font(.tv(.caption2)).lineLimit(1)
                        .opacity(selected ? 1 : 0.6).padding(.leading, 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    ScreenSaverSettings.aerialCategory = choice.id
                }
            }
        }
        .animation(Motion.focus, value: chosen)
        .padding(.bottom, 10)
    }

    // MARK: Pieces

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 20, weight: .semibold)).opacity(0.4)
    }

    /// A row's title: one line, never a second line under it.
    private func title(_ text: String) -> some View {
        Text(text).font(.tv(.body)).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(_ text: String) -> some View {
        Text(text).font(.tv(.caption1)).monospacedDigit().opacity(0.55)
    }

    private func stepper(_ text: String, active: Bool) -> some View {
        HStack(spacing: 14) {
            if active { Image(systemName: "chevron.left").opacity(0.5) }
            Text(text).monospacedDigit().contentTransition(.numericText())
            if active { Image(systemName: "chevron.right").opacity(0.5) }
        }
        .font(.system(size: 24, weight: .semibold))
    }

    private func row<Content: View>(focused: Bool, warning: Bool, @ViewBuilder content: () -> Content,
                                    action: @escaping () -> Void) -> some View {
        HStack(spacing: 22) { content() }
            .padding(.horizontal, 30)
            .frame(minHeight: 78)
            // tvOS focus: a bright white platter with dark text; Sleep Mac turns red to confirm.
            .foregroundStyle(focused && !warning ? .black : .white)
            .background {
                let shape = RoundedRectangle(cornerRadius: TVLayout.tileRadius, style: .continuous)
                if focused {
                    // One platter that glides from row to row as focus moves, like tvOS.
                    shape.fill(warning ? Color(hex: "#FF453A") : .white)
                        .matchedGeometryEffect(id: "focus", in: focusSpace)
                } else {
                    shape.fill(.white.opacity(0.07))
                }
            }
            .scaleEffect(focused ? 1.03 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 20, y: 12)
            .animation(Motion.focus, value: focused)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

/// An on/off switch drawn like the phone remote's.
struct SettingSwitch: View {
    let on: Bool

    var body: some View {
        Capsule()
            // Mid grey when off, so it shows on a dark row and on the white focus platter alike.
            .fill(on ? Color(hex: "#3DDC84") : Color(white: 0.55, opacity: 0.5))
            .frame(width: 64, height: 36)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 28, height: 28).padding(4)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .animation(.snappy(duration: 0.2), value: on)
    }
}
