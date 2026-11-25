import AppKit
import Foundation
import Testing
import WebKit
@testable import MacTV

@Suite(.enabled(if: ProcessInfo.processInfo.environment["MACTV_LIVE_REMOTE_TEST"] == "1")) @MainActor
struct PlaybackResumeTests {
    @Test func homePausesTheEmbeddedPlayerAndReopeningKeepsItsPage() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mactv-resume-\(UUID())")
        let suiteName = "MacTV.PlaybackResume.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: folder)
        }
        let tv = TVController(library: AppLibrary(folder: folder), browserPreferences: BrowserPreferences(defaults: defaults))
        let html = """
            <audio id="media" loop preload="auto"></audio>
            <script>
            const wav = new Uint8Array(160044);
            const header = new DataView(wav.buffer);
            wav.set([82,73,70,70], 0);
            header.setUint32(4, wav.length - 8, true);
            wav.set([87,65,86,69,102,109,116,32], 8);
            header.setUint32(16, 16, true);
            header.setUint16(20, 1, true);
            header.setUint16(22, 1, true);
            header.setUint32(24, 8000, true);
            header.setUint32(28, 16000, true);
            header.setUint16(32, 2, true);
            header.setUint16(34, 16, true);
            wav.set([100,97,116,97], 36);
            header.setUint32(40, wav.length - 44, true);
            media.src = URL.createObjectURL(new Blob([wav], {type:'audio/wav'}));
            </script>
            """
        let address = try #require(URL(string: "data:text/html;base64," + Data(html.utf8).base64EncodedString()))
        let service = Service(id: "resume-fixture", name: "Resume fixture", kind: .web(address))
        tv.open(service)
        let web = try #require(tv.webView)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 390, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        tv.window = window
        window.orderFront(nil)
        defer { window.close() }
        try await waitFor("initial audio page") { (try? await web.evaluateJavaScript("media.src.startsWith('blob:')") as? Bool) == true }
        _ = try await web.callAsyncJavaScript("""
            window.resumeMarker = 'preserved';
            await media.play();
            media.currentTime = 3;
            """, arguments: [:], contentWorld: .page)

        tv.goHome(keepPlayback: true)
        #expect(tv.mode == .launcher)
        #expect(tv.webView == nil)
        try await waitFor("audio pauses on Home") { (try? await web.evaluateJavaScript("media.paused") as? Bool) == true }
        let pausedAt = try #require(try await web.evaluateJavaScript("media.currentTime") as? Double)
        #expect(pausedAt >= 3)

        let otherService = Service(id: "second-resume-fixture", name: "Second fixture", kind: .web(address))
        tv.open(otherService)
        let otherWeb = try #require(tv.webView)
        #expect(otherWeb !== web)
        tv.goHome(keepPlayback: true)
        tv.goHome(keepPlayback: true)
        tv.open(service)
        #expect(tv.webView === web)
        #expect(try await web.evaluateJavaScript("window.resumeMarker") as? String == "preserved")
        #expect(try await web.evaluateJavaScript("media.paused") as? Bool == true)
        let restoredAt = try #require(try await web.evaluateJavaScript("media.currentTime") as? Double)
        #expect(abs(restoredAt - pausedAt) < 0.25)
        _ = try await web.callAsyncJavaScript("await media.play();", arguments: [:], contentWorld: .page)
        try await waitFor("audio continues from the saved position") {
            guard let time = try? await web.evaluateJavaScript("media.currentTime") as? Double else { return false }
            return time > restoredAt
        }

        tv.goHome(keepPlayback: true)
        tv.open(otherService)
        #expect(tv.webView === otherWeb)
        let originalProfile = tv.profile.id
        let profile = tv.profiles.add(named: "Resume test profile")
        tv.switchProfile(to: profile.id)
        tv.switchProfile(to: originalProfile)
        tv.open(service)
        #expect(tv.webView !== web)
        tv.goHome()
    }

    private func waitFor(_ step: String, _ condition: () async -> Bool) async throws {
        for _ in 0..<60 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(await condition(), Comment(rawValue: step))
    }
}
