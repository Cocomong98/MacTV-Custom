import AppKit
import SwiftUI
import WebKit

struct PlayerFailure: Equatable {
    let message: String
    var selected = 0
}

@MainActor
final class PlaybackDiagnostics: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var result = "WebKit 재생 기능을 확인하는 중…"
    private var web: WKWebView?
    let displays: String = NSScreen.screens.map { screen in
        let mode = CGDisplayCopyDisplayMode(screen.displayID)
        return "\(screen.localizedName): \(mode?.pixelWidth ?? 0) × \(mode?.pixelHeight ?? 0), \(Int(mode?.refreshRate ?? 0)) Hz"
    }.joined(separator: "\n")

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        web = view
        view.navigationDelegate = self
        view.customUserAgent = UserAgent.safari
        view.loadHTMLString("<!doctype html><title>Playback check</title>", baseURL: URL(string: "https://example.com/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            do {
                let value = try await webView.callAsyncJavaScript(DRMSelfTest.script, contentWorld: .page)
                self?.result = value as? String ?? "재생 기능 보고서를 사용할 수 없습니다."
            } catch { self?.result = "재생 기능을 확인하지 못했습니다. \(error.localizedDescription)" }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        result = "재생 점검을 시작하지 못했습니다. \(error.localizedDescription)"
    }
}

extension TVController {
    func openPlaybackCheck() {
        let check = PlaybackDiagnostics()
        playbackCheck = check
        check.start()
    }
    func recordPlayerFailure(_ web: WKWebView, error: Error? = nil) {
        guard web === webView, case .player = mode else { return }
        if let error, (error as NSError).code == NSURLErrorCancelled { return }
        if let error { Log.playback.failure("Streaming page didn't load", error) }
        else { Log.playback.error("Streaming page stopped responding") }
        playerFailure = PlayerFailure(message: error == nil
            ? "스트리밍 페이지가 응답하지 않습니다."
            : "스트리밍 페이지를 불러오지 못했습니다. 연결을 확인한 뒤 다시 시도하세요.")
    }
    func handlePlayerFailure(_ command: RemoteCommand) {
        guard var panel = playerFailure else { return }
        switch command {
        case .move(.left), .move(.up): panel.selected = max(0, panel.selected - 1)
        case .move(.right), .move(.down): panel.selected = min(2, panel.selected + 1)
        case .select: performPlayerRecovery(panel.selected); return
        case .back: goHome(); return
        default: return
        }
        playerFailure = panel
    }
    func performPlayerRecovery(_ action: Int) {
        switch action {
        case 0:
            playerFailure = nil
            webView?.reload()
        case 1:
            guard case .player(let service) = mode else { return }
            let url: URL?
            if let current = webView?.url, ["http", "https"].contains(current.scheme ?? "") { url = current }
            else if case .web(let original) = service.kind { url = original }
            else { url = nil }
            guard let url, let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
                showToast("Safari를 열 수 없습니다. 다시 시도하거나 홈으로 돌아가세요."); return
            }
            NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
            goHome()
        default: goHome()
        }
    }
}

struct PlaybackFailureView: View {
    @ObservedObject var tv: TVController
    var body: some View {
        VStack(spacing: 28) {
            Text("재생할 수 없습니다").font(.tv(.title3, emphasized: true))
            Text(tv.playerFailure?.message ?? "").font(.tv(.body)).foregroundStyle(TVLayout.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                ForEach(Array(["다시 시도", "Safari에서 열기", "홈"].enumerated()), id: \.offset) { index, label in
                    Button(label) { tv.performPlayerRecovery(index) }
                        .buttonStyle(.plain).font(.system(size: 26, weight: .semibold)).padding(24)
                        .foregroundStyle(tv.playerFailure?.selected == index ? .black : .white)
                        .background(tv.playerFailure?.selected == index ? .white : .white.opacity(0.12), in: Capsule())
                }
            }
            InputHintsBar(tv: tv, set: .chooser)
        }
        .padding(60).frame(width: 1280)
        .tvPanel(in: RoundedRectangle(cornerRadius: TVLayout.panelRadius))
        .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.8))
    }
}

struct PlaybackCheckSheet: View {
    @ObservedObject var tv: TVController
    var body: some View {
        if let check = tv.playbackCheck {
            PlaybackCheckContent(tv: tv, check: check)
        }
    }
}

private struct PlaybackCheckContent: View {
    @ObservedObject var tv: TVController
    @ObservedObject var check: PlaybackDiagnostics
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("재생 점검").font(.tv(.title3, emphasized: true))
            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)").font(.tv(.caption1))
            Text(check.displays).font(.tv(.caption1))
            Text(check.result).font(.system(size: 19, design: .monospaced)).textSelection(.enabled)
            Text("이 점검은 지원 기능을 확인합니다. 실제 재생 해상도와 HDR, HDCP 적용 여부는 별도로 확인해야 합니다.")
                .font(.tv(.caption1, emphasized: true))
            Text("Netflix는 요금제, Safari 호환성, 화면과 케이블의 요구 조건을 확인하세요. 서비스에 따라 내장 플레이어가 제한될 수 있습니다. 재생이 실패하면 Safari에서 열어 보세요. 로그인과 구독은 각 서비스에서 확인합니다.")
                .font(.tv(.caption1)).foregroundStyle(.white.opacity(0.75))
            InputHintsBar(tv: tv, set: .info)
        }.padding(50).frame(width: 1380)
            .tvPanel(in: RoundedRectangle(cornerRadius: 44, style: .continuous))
            .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
