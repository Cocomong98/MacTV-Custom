import SwiftUI

/// Toasts and controller notices are kept apart from `TVController` so that appearing notices
/// redraw only the views that show them.
@MainActor
final class Notices: ObservableObject {
    @Published private(set) var toast: String?
    @Published private(set) var controller: ControllerNotice?

    private var toastTask: Task<Void, Never>?
    private var controllerTask: Task<Void, Never>?

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func showController(_ notice: ControllerNotice) {
        withAnimation(.smooth(duration: 0.35)) { controller = notice }
        controllerTask?.cancel()
        controllerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { withAnimation(.smooth(duration: 0.4)) { self?.controller = nil } }
        }
    }
}

/// The notices' layer over every screen. It never takes the pointer.
struct NoticesOverlay: View {
    @ObservedObject var notices: Notices

    var body: some View {
        ZStack {
            if let notice = notices.controller {
                TVCanvas {
                    GlassGroup { ControllerBanner(notice: notice).tvGlassTransition() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 96)
                        .padding(.top, 43)
                }
                .ignoresSafeArea()
            }

            // Always in place, so the toast's glass materializes in and out rather than fading.
            TVCanvas {
                GlassGroup {
                    if let toast = notices.toast {
                        Text(toast)
                            .font(.tv(.callout))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 34).padding(.vertical, 18)
                            .tvGlass(in: Capsule())
                            .tvGlassTransition()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 52)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .animation(Motion.appear, value: notices.toast)
    }
}
