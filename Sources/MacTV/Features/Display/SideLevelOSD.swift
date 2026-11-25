import AppKit
import SwiftUI

enum DisplayLevel: Equatable {
    enum Kind: Hashable { case brightness, volume }

    case brightness(Int)
    case volume(VolumeLevel)

    var kind: Kind {
        switch self {
        case .brightness: .brightness
        case .volume: .volume
        }
    }

    var symbol: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .volume(let volume):
            guard let level = volume.level else { return "tv" }
            if volume.muted || level == 0 { return "speaker.slash.fill" }
            return level < 34 ? "speaker.wave.1.fill" : level < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }

    var text: String {
        switch self {
        case .brightness(let level): return "\(level)%"
        case .volume(let volume):
            if volume.muted { return "Mute" }
            if let level = volume.level { return "\(level)%" }
            return "TV"
        }
    }

    var fraction: CGFloat? {
        let value: Int
        switch self {
        case .brightness(let level): value = level
        case .volume(let volume):
            guard let level = volume.level else { return nil }
            value = volume.muted ? 0 : level
        }
        return CGFloat(max(0, min(100, value))) / 100
    }
}

/// The panel sits in the display's active Space and never becomes a key window or receives clicks.
@MainActor
final class SideLevelOSD {
    private struct Key: Hashable {
        let displayID: CGDirectDisplayID
        let kind: DisplayLevel.Kind
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    @MainActor private final class Entry {
        let panel: Panel
        let view: NSHostingView<SideLevelView>
        var hide: Task<Void, Never>?

        init(level: DisplayLevel) {
            panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.identifier = NSUserInterfaceItemIdentifier("SideLevelOSD")
            view = NSHostingView(rootView: SideLevelView(level: level))
            panel.contentView = view
        }
    }

    private let duration: Duration
    private var entries: [Key: Entry] = [:]

    init(duration: Duration = .seconds(2)) { self.duration = duration }

    static func frame(for kind: DisplayLevel.Kind, in screen: CGRect) -> CGRect {
        let size = CGSize(width: 84, height: 194)
        let inset: CGFloat = 28
        let x = kind == .brightness ? screen.minX + inset : screen.maxX - size.width - inset
        return CGRect(x: x, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    func show(_ level: DisplayLevel, on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return }
        let key = Key(displayID: displayID, kind: level.kind)
        let entry = entries[key] ?? Entry(level: level)
        entries[key] = entry
        entry.view.rootView = SideLevelView(level: level)
        entry.panel.setFrame(Self.frame(for: level.kind, in: screen.frame), display: true)
        entry.panel.orderFrontRegardless()
        entry.hide?.cancel()
        entry.hide = Task { [weak self, duration] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.entries.removeValue(forKey: key)?.panel.orderOut(nil)
        }
    }

    func dismiss() {
        for entry in entries.values {
            entry.hide?.cancel()
            entry.panel.orderOut(nil)
        }
        entries.removeAll()
    }
}

struct SideLevelView: View {
    let level: DisplayLevel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: level.symbol)
                .font(.system(size: 23, weight: .semibold))
                .frame(width: 36, height: 26)
            if let fraction = level.fraction {
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule().fill(.white).frame(height: 92 * fraction)
                }
                .frame(width: 8, height: 92)
            } else {
                Color.clear.frame(width: 8, height: 92)
            }
            Text(level.text)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .frame(width: 80, height: 190)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.22)) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.kind == .brightness ? "밝기" : "음량")
        .accessibilityValue(level.text)
    }
}

extension NSScreen {
    /// Accessibility window positions use top-left Quartz coordinates, like CGDisplayBounds.
    static func overlappingQuartzBounds(_ bounds: CGRect) -> NSScreen? {
        screens.compactMap { screen -> (NSScreen, CGFloat)? in
            let overlap = bounds.intersection(CGDisplayBounds(screen.displayID))
            guard !overlap.isNull, !overlap.isEmpty else { return nil }
            return (screen, overlap.width * overlap.height)
        }.max { $0.1 < $1.1 }?.0
    }
}
