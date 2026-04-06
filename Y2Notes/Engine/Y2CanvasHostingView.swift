import SwiftUI
import PencilKit

// MARK: - Y2CanvasHostingView

/// Thin `UIViewControllerRepresentable` that embeds `Y2CanvasViewController`
/// in a SwiftUI view hierarchy.
///
/// This wrapper is intentionally minimal — all canvas logic lives in the
/// UIKit controller. The hosting view's only job is to bridge SwiftUI state
/// into `CanvasConfiguration` and forward delegate callbacks.
struct Y2CanvasHostingView: UIViewControllerRepresentable {

    let configuration: CanvasConfiguration
    let delegate: CanvasDelegate?
    var zoomResetTrigger: Bool = false

    func makeUIViewController(context: Context) -> Y2CanvasViewController {
        let controller = Y2CanvasViewController(configuration: configuration)
        controller.delegate = delegate
        return controller
    }

    func updateUIViewController(_ controller: Y2CanvasViewController, context: Context) {
        controller.apply(configuration)
        controller.delegate = delegate

        if zoomResetTrigger != context.coordinator.lastZoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            controller.resetZoom()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastZoomResetTrigger: Bool = false
    }
}
