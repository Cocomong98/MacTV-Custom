import SwiftUI

private struct CanvasSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1920, height: 1080)
}

private struct CanvasPixelsKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1920, height: 1080)
}

extension EnvironmentValues {
    /// The TV canvas in points: 1920×1080 at 16:9, taller or wider for other window shapes.
    var canvasSize: CGSize {
        get { self[CanvasSizeKey.self] }
        set { self[CanvasSizeKey.self] = newValue }
    }

    var canvasPixels: CGSize {
        get { self[CanvasPixelsKey.self] }
        set { self[CanvasPixelsKey.self] = newValue }
    }
}

/// Lays content out on a TV canvas and scales it to the window, like a TV UI. The canvas is
/// 1920 wide on screens taller than 16:9 and 1080 tall on wider ones, so it always fills the
/// window with no bars.
struct TVCanvas<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let window = CGSize(width: max(geo.size.width, 1), height: max(geo.size.height, 1))
            let scale = window.width / window.height < 16 / 9 ? window.width / 1920 : window.height / 1080
            let canvas = CGSize(width: window.width / scale, height: window.height / scale)
            content
                .environment(\.canvasSize, canvas)
                .environment(\.canvasPixels, CGSize(width: window.width * displayScale, height: window.height * displayScale))
                .frame(width: canvas.width, height: canvas.height)
                .scaleEffect(scale)
                .frame(width: window.width, height: window.height)
        }
    }
}

enum TVLayout {
    static let edge: CGFloat = 96
    static let tileRadius: CGFloat = 24
    static let panelRadius: CGFloat = 42
    static let secondaryText = Color.white.opacity(0.74)
}

struct Wallpaper: View {
    var body: some View {
        RadialGradient(colors: [Color(hex: "#1B1E27"), Color(hex: "#0A0B0E")],
                       center: .top, startRadius: 0, endRadius: 1300)
    }
}

// MARK: Home

/// The frosted backdrop behind full-screen sheets (Settings, Add App, Profiles, Setup): the home screen
/// blurred and dimmed. Sheets on it use plain panels and platters, not glass.
struct SheetBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors: [.black.opacity(0.48), .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

// MARK: Add an app, on the TV
