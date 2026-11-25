import AppKit
import Foundation
import Testing
import WebKit
@testable import MacTV

/// Live WebKit checks for remote text input and the paired move to the Mac's .local name.
/// Runs only with MACTV_LIVE_REMOTE_TEST=1, using isolated windows, profiles and pairings.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MACTV_LIVE_REMOTE_TEST"] == "1")) @MainActor
struct RemoteReconnectLiveTests {
    @Test func committedRemoteTextInsertsOnceAtTheWebSearchCursor() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mactv-remote-text-\(UUID())")
        let suite = "MacTV.RemoteTextTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let tv = TVController(library: AppLibrary(folder: folder), browserPreferences: BrowserPreferences(defaults: defaults))
        let page = """
            <input id="query" type="search">
            <script>
            const query = document.getElementById('query');
            window.edits = [];
            query.addEventListener('input', e => edits.push(e.data));
            query.addEventListener('keydown', e => {
              if (e.code === 'KeyA') { e.preventDefault(); query.value += 'a'; }
            });
            </script>
            """
        let url = try #require(URL(string: "data:text/html;base64," + Data(page.utf8).base64EncodedString()))
        let service = Service(id: "input-fixture", name: "Input fixture", kind: .web(url))
        tv.playbackCoordinator.playWeb(service, url: url)
        let web = try #require(tv.webView)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 390, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        tv.window = window
        window.orderFront(nil)
        defer { tv.playbackCoordinator.closeWebPlayback(); window.close() }
        try await waitFor { await web.isLoaded(at: "data:") }
        try #require(window.makeFirstResponder(web))
        _ = try await web.evaluateJavaScript("query.focus(); query.value = '앞뒤'; query.setSelectionRange(1, 1);")
        // Let the WebContent process publish its focused editor state to AppKit.
        try await Task.sleep(for: .milliseconds(150))

        let text = "한글A123 다음😃"
        let command = try #require(RemoteCommand(json: ["a": "text", "t": text]))
        tv.playbackCoordinator.handleInPlayer(command, service: service)
        let value = try await web.evaluateJavaScript("query.value") as? String
        let edits = try await web.evaluateJavaScript("edits") as? [String]
        #expect(value == "앞\(text)뒤")
        #expect(edits == [text])
    }

    @Test func aRemoteMovesToTheMacsNameStillPaired() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("work/tests/\(UUID().uuidString)", isDirectory: true)
        let suite = "MacTVTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let name = try #require(LAN.bonjourName())
        let port: UInt16 = 28765
        let nameOrigin = "http://\(name):\(port)", loopOrigin = "http://127.0.0.1:\(port)"

        let server = RemoteServer(token: "unused", onCommand: { _ in },
                                  state: { ["addresses": [nameOrigin, loopOrigin], "apps": [], "mode": "launcher"] },
                                  icon: { _ in nil }, routes: { _ in nil },
                                  pairing: PairingStore(folder: folder), defaults: defaults,
                                  ownOrigins: { [nameOrigin, loopOrigin] })
        var ready = false
        server.start(ports: [port]) { _ in ready = true }
        defer { server.stop() }
        for _ in 0..<50 where !ready { try await Task.sleep(for: .milliseconds(100)) }
        try #require(ready)

        let code = RemoteServer.pairingCode()
        let paired = server.respond(to: HTTPRequest(method: "POST", path: "/pair", query: [:], headers: [:],
                                                    body: try JSONSerialization.data(withJSONObject: ["code": code, "name": "Test"])))
        let token = try #require((try JSONSerialization.jsonObject(with: paired.body) as? [String: Any])?["token"] as? String)

        // The remote, open at the loopback address with its key and the Mac's addresses saved.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        web.load(URLRequest(url: URL(string: loopOrigin + "/")!))
        try await waitFor { await web.isLoaded(at: loopOrigin) }
        _ = try await web.callAsyncJavaScript("""
            localStorage.setItem('mactvKey', key0);
            localStorage.setItem('mactvAddresses', JSON.stringify([loop, nameOrigin]));
            key = key0;
            return await moveToAnotherAddress();
            """, arguments: ["key0": token, "loop": loopOrigin, "nameOrigin": nameOrigin], contentWorld: .page)

        // It lands on the name, keeps the key, clears it from the address bar and reads the state.
        try await waitFor { await web.isLoaded(at: nameOrigin) }
        let stored = try await web.evaluateJavaScript("localStorage.getItem('mactvKey')") as? String
        #expect(stored == token)
        #expect(web.url?.fragment == nil)
        let reachable = try await web.callAsyncJavaScript("return await refresh();", arguments: [:], contentWorld: .page) as? Bool
        #expect(reachable == true)

        // A fragment-only WKWebView load must keep the current document alive for the TV search.
        _ = try await web.evaluateJavaScript("window.inputTestMarker = true;")
        let sameDocument = try #require(URL(string: nameOrigin + "/#search?q=test"))
        web.load(URLRequest(url: sameDocument))
        try await waitFor { web.url?.fragment == "search?q=test" }
        let marker = try await web.evaluateJavaScript("window.inputTestMarker === true") as? Bool
        #expect(marker == true)
    }

    private func waitFor(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("Timed out waiting")
    }
}

@Suite @MainActor
struct YouTubeTVRemoteSearchTests {
    @Test func passesTheWholeQueryOnlyFromTheTVSearchScreen() throws {
        let current = try #require(URL(string: "https://www.youtube.com/tv#/search?"))
        let text = "한글 A+123 & # 😃"
        let target = try #require(PlaybackCoordinator.youTubeTVSearchURL(from: current, text: text))
        let components = try #require(URLComponents(url: target, resolvingAgainstBaseURL: false))
        #expect(components.host == "www.youtube.com")
        #expect(components.path == "/tv")
        #expect(components.query == nil)
        let fragment = try #require(components.percentEncodedFragment)
        #expect(fragment.hasPrefix("/search?q="))
        #expect(fragment.contains("%2B"))
        let parsed = try #require(URLComponents(string: fragment))
        #expect(parsed.queryItems == [URLQueryItem(name: "q", value: text)])
        for url in ["https://www.youtube.com/results", "https://www.youtube.com/tv#/watch?v=123",
                    "https://www.youtube.com/tv#/searchHistory", "https://example.com/tv#/search"] {
            #expect(PlaybackCoordinator.youTubeTVSearchURL(from: URL(string: url), text: text) == nil)
        }
        #expect(PlaybackCoordinator.youTubeTVSearchURL(from: current, text: " ") == nil)
    }
}

private extension WKWebView {
    /// The page at `origin` has finished loading.
    func isLoaded(at origin: String) async -> Bool {
        guard url?.absoluteString.hasPrefix(origin) == true, !isLoading else { return false }
        return (try? await evaluateJavaScript("document.readyState") as? String) == "complete"
    }
}
