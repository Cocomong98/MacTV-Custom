import AppKit
import SwiftUI

struct TopShelf: View {
    @ObservedObject var tv: TVController
    let expanded: Bool
    @Environment(\.canvasSize) private var canvas

    var body: some View {
        let service = tv.shelfService
        AppBanner(tv: tv, movieLibrary: tv.movieLibrary, service: service, expanded: expanded)
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .id(service.id)
            .transition(.opacity)
    }
}

/// Compares decoded artwork with the window's backing pixels before it can fill the screen.
enum ShelfArtwork {
    static func fillsScreen(_ image: CGSize, viewport: CGSize) -> Bool {
        image.width >= viewport.width && image.height >= viewport.height
            && image.width >= image.height * 1.4
    }
}

struct AppBanner: View {
    @ObservedObject var tv: TVController
    @ObservedObject var movieLibrary: MovieLibrary
    @Environment(\.canvasSize) private var canvas
    @Environment(\.canvasPixels) private var pixels
    let service: Service
    let expanded: Bool

    private var artwork: (image: NSImage, title: String)? {
        switch service.kind {
        case .movies:
            guard let first = movieLibrary.shelf.first else { return nil }
            let title = movieLibrary.movies.first(where: { $0.path == first.path })?.displayTitle ?? service.name
            return (first.image, title)
        case .steam:
            return SteamShelfArt.image(at: tv.library.heroFile(for: service.id)).map { ($0, service.name) }
        default:
            return nil
        }
    }

    var body: some View {
        let art = artwork
        let bitmap = art?.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let fullBleed = bitmap.map {
            ShelfArtwork.fillsScreen(CGSize(width: $0.width, height: $0.height), viewport: pixels)
        } ?? false
        ZStack(alignment: .topLeading) {
            Artwork(accent: service.accent, deep: service.deep)

            if let art, fullBleed {
                AppArtBackdrop(image: art.image)
                    .frame(width: canvas.width, height: canvas.height)
                    .accessibilityHidden(true)
            }

            LinearGradient(colors: [.black.opacity(fullBleed ? 0.88 : 0.46), .clear],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.42),
                                   .init(color: .black.opacity(0.78), location: 1)],
                           startPoint: .top, endPoint: .bottom)

            if let art, !fullBleed {
                Image(nsImage: art.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(460, canvas.width * 0.25), height: canvas.height * 0.38)
                    .clipShape(RoundedRectangle(cornerRadius: TVLayout.tileRadius))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 140)
                    .padding(.trailing, TVLayout.edge)
            }

            VStack(alignment: .leading, spacing: 18) {
                Text(service.name)
                    .font(.tv(.title1, emphasized: true))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let art, art.title != service.name {
                    Text(art.title)
                        .font(.tv(.body))
                        .foregroundStyle(TVLayout.secondaryText)
                        .lineLimit(2)
                }
                if expanded && tv.shelfCount > 0 {
                    ShelfButton(title: "열기", systemImage: "arrow.up.right", focused: tv.focus == .shelf(0)) {
                        tv.activateShelf(0)
                    }
                    .accessibilityLabel("\(service.name) 열기")
                    .padding(.top, 16)
                    .transition(.opacity)
                }
            }
            .frame(width: min(1060, canvas.width * 0.56), alignment: .leading)
            .padding(.leading, TVLayout.edge)
            .frame(maxHeight: .infinity, alignment: expanded ? .bottomLeading : .topLeading)
            .padding(.top, 148)
            .padding(.bottom, 110)
        }
        .clipped()
    }
}

/// Full-bleed Steam art via a layer (SwiftUI `Image(nsImage:)` was unreliable for some Steam PNGs).
struct AppArtBackdrop: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.contentsGravity = .resizeAspectFill
        view.layer?.contents = Self.bitmap(image)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // SwiftUI updates the view on every redraw; a new picture gets a new view (its id changes).
        guard let bitmap = Self.bitmap(image), view.layer?.contents as AnyObject? !== bitmap else { return }
        view.layer?.contents = bitmap
    }

    private static func bitmap(_ image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cg }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }
}

/// tvOS buttons: glass at rest, white with dark text when focused.
struct ShelfButton: View {
    let title: String
    var systemImage: String? = nil
    let focused: Bool
    /// Glass over artwork, like the Top Shelf; a plain platter on a frosted sheet, where glass has nothing to refract.
    var glass = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.tv(.callout, emphasized: true))
            .padding(.horizontal, 38)
            .frame(height: 72)
            .foregroundStyle(focused ? .black : .white)
            .background {
                if !glass { Capsule().fill(.white.opacity(0.12)) }
            }
            .focusPlatter(Capsule(), focused: focused, glass: glass)
            .scaleEffect(focused ? 1.08 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 20, y: 14)
            .animation(Motion.focus, value: focused)
        }
        .buttonStyle(.plain)
    }
}

/// A static background in the focused app's own colours.
struct Artwork: View {
    let accent: String
    let deep: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: deep), Color(hex: "#050608")], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: accent).opacity(0.8), Color(hex: accent).opacity(0.2), .clear],
                           center: UnitPoint(x: 0.74, y: 0.28), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Color(hex: accent).opacity(0.36), .clear],
                           center: UnitPoint(x: 0.56, y: 0.62), startRadius: 0, endRadius: 420)
        }
    }
}
