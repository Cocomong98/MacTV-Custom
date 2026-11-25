import SwiftUI

struct PairSheet: View {
    @Environment(\.canvasSize) private var canvas
    @ObservedObject var tv: TVController

    var body: some View {
        let links = tv.pairingGuest ? tv.remoteGuestLinks : tv.remoteLinks
        HStack(alignment: .center, spacing: 52) {
            HStack(alignment: .top, spacing: 24) {
                if links.isEmpty {
                    RoundedRectangle(cornerRadius: 28).fill(.white.opacity(0.1))
                        .frame(width: 300, height: 300)
                        .overlay(Text("Wi-Fi 또는 Tailscale에\n연결하세요").multilineTextAlignment(.center)
                            .font(.tv(.caption2)).opacity(0.7))
                }
                ForEach(links) { link in
                    VStack(spacing: 14) {
                        if let qr = link.qr {
                            Image(nsImage: qr).interpolation(.none).resizable()
                                .frame(width: 260, height: 260)
                                .padding(20)
                                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                        Text(link.displayLabel).font(.tv(.caption2)).opacity(0.8)
                        Text(link.address).font(.tv(.caption2)).monospacedDigit().opacity(0.7)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                Text("아이폰을 리모컨으로 연결").font(.tv(.title3, emphasized: true))
                Text("QR을 스캔하거나 Safari에서 QR 아래 주소를 열고 연결 코드를 입력하세요.\n연결 코드 \(tv.pairingGuest ? tv.remoteGuestToken : tv.remoteToken)")
                    .font(.tv(.caption2)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                VStack(spacing: 10) {
                    pairRow("리모컨 권한", value: tv.pairingGuest ? "게스트 · 24시간" : "전체",
                            focused: tv.pairingFocusedRow == .access) { tv.pairingGuest.toggle() }
                    if tv.pairingRows.contains(.display) {
                        let displays = tv.availableTVDisplays
                        pairRow("화면", value: (displays.first(where: \.current) ?? displays.first)?.name,
                                focused: tv.pairingFocusedRow == .display) { tv.stepPairingDisplay() }
                    }
                    pairRow("시작할 때 표시", value: tv.preferences.showPairingAtLaunch ? "켬" : "끔",
                            focused: tv.pairingFocusedRow == .showAtLaunch) {
                        tv.preferences.showPairingAtLaunch.toggle()
                    }
                }
                .padding(.top, 8)
                InputHintsBar(tv: tv, set: pairHints)
                    .padding(.top, 10)
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
        .padding(56)
        .tvPanel(in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .foregroundStyle(.white)
        .frame(width: canvas.width, height: canvas.height)
    }

    private var pairHints: HintSet {
        switch tv.pairingFocusedRow {
        case .access, .showAtLaunch:
            // ←→ and OK both flip — Toggle only.
            .custom([.moveVertical("이동"), .select("전환"), .back("닫기")])
        case .display:
            .custom([.moveVertical("이동"), .moveHorizontal("변경"), .back("닫기")])
        }
    }

    /// A row on the frosted sheet: a plain fill at rest, the white platter with dark text when focused.
    private func pairRow(_ title: String, value: String? = nil, focused: Bool,
                         action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 16) {
                Text(title).lineLimit(1)
                Spacer(minLength: 16)
                if let value { Text(value).opacity(0.6) }
            }
            .font(.tv(.callout))
            .padding(.horizontal, 26)
            .frame(height: 66)
            .foregroundStyle(focused ? .black : .white)
            .background { if !focused { shape.fill(.white.opacity(0.07)) } }
            .focusPlatter(shape, focused: focused, glass: false)
            .scaleEffect(focused ? 1.03 : 1)
            .animation(Motion.focus, value: focused)
        }
        .buttonStyle(.plain)
    }
}
