import AppKit
import Testing
@testable import MacTV

@Suite @MainActor
struct SideLevelOSDTests {
    @Test func levelsUseOppositeEdgesAndRetainMuteState() {
        let screen = CGRect(x: -1600, y: 230, width: 1600, height: 900)
        let brightness = SideLevelOSD.frame(for: .brightness, in: screen)
        let volume = SideLevelOSD.frame(for: .volume, in: screen)
        #expect(screen.contains(brightness) && screen.contains(volume))
        #expect(brightness.minX - screen.minX == screen.maxX - volume.maxX)
        #expect(brightness.midY == screen.midY && volume.midY == screen.midY)
        #expect(!brightness.intersects(volume))
        #expect(DisplayLevel.brightness(62).text == "62%")
        let muted = DisplayLevel.volume(.init(level: 40, muted: true))
        #expect(muted.text == "Mute" && muted.fraction == 0)
        #expect(DisplayLevel.volume(.init(level: nil, muted: false)).fraction == nil)
    }

    @Test func overlayKeepsFocusAndHidesAfterTheLastUpdate() async throws {
        let application = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let overlay = SideLevelOSD(duration: .milliseconds(250))
        defer { overlay.dismiss() }
        let keyWindow = application.keyWindow

        overlay.show(.brightness(47), on: screen.displayID)
        let panel = try #require(application.windows.first {
            $0.identifier?.rawValue == "SideLevelOSD" && $0.isVisible
        })
        #expect(!panel.canBecomeKey && !panel.canBecomeMain && panel.ignoresMouseEvents)
        #expect(panel.collectionBehavior.contains([.fullScreenAuxiliary, .canJoinAllApplications]))
        #expect(panel.frame == SideLevelOSD.frame(for: .brightness, in: screen.frame))
        #expect(application.keyWindow === keyWindow)

        overlay.show(.brightness(50), on: screen.displayID)
        #expect(panel.isVisible)
        for _ in 0..<30 where panel.isVisible {
            try await Task.sleep(for: .milliseconds(100))
        }
        let hidden = !panel.isVisible
        #expect(hidden)
    }
}
