import AppKit
import Testing
@testable import MacTV

struct InputKindTests {
    @Test func mapsFeedbackSources() {
        #expect(InputKind(.keyboard) == .keyboard)
        #expect(InputKind(.trackpad) == .keyboard)
        #expect(InputKind(.pointer) == .keyboard)
        #expect(InputKind(.remote) == .remote)
        #expect(InputKind(.controller) == .controller)
    }

    @Test func hintSetsKeepStableVerbs() {
        #expect(HintSet.list.actions.map(\.label) == ["이동", "선택", "닫기"])
        #expect(HintSet.listAdjust.actions.map(\.label) == ["이동", "변경", "선택", "닫기"])
        #expect(HintSet.arrange.actions.map(\.label) == ["앱 선택", "동작 선택", "적용", "닫기"])
        #expect(HintSet.info.actions.map(\.label) == ["닫기"])
        #expect(HintSet.pick.actions.map(\.label) == ["이동", "선택"])
    }
}

@MainActor
struct InputHintBehaviourTests {
    @Test func gridsGetOneMoveHint() {
        #expect(HintAction.move("Choose").label == "Choose")
    }

    @Test func rowsWhereOKDoesNothingHaveNoOKHint() {
        for row in [SettingsPanel.Row.pairingCode, .version, .source] { #expect(row.okVerb.isEmpty) }
        #expect(SettingsPanel.Row.autoSkip.okVerb == "전환")
        #expect(SettingsPanel.Row.audioOutput.okVerb == "열기")
    }

    /// Every command reports its input; only a change of input may redraw the screens watching it.
    @Test func sameInputDoesNotRepublish() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("work/tests/hints-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tv = TVController(library: AppLibrary(folder: folder))
        _ = NSApplication.shared
        // In Settings, arrows only move its focus.
        tv.settings = SettingsPanel()
        var kinds: [InputKind] = []
        let watch = tv.$lastInputKind.dropFirst().sink { kinds.append($0) }
        defer { watch.cancel() }
        tv.handle(.move(.down), from: .keyboard)
        tv.handle(.move(.down), from: .keyboard)
        tv.handle(.move(.up), from: .controller)
        tv.handle(.move(.up), from: .controller)
        #expect(kinds == [.controller])
    }
}
