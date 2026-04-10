import SwiftUI

// MARK: - InfiniteCanvasView

/// A single-page, boundless whiteboard canvas inspired by GoodNotes' whiteboard mode.
///
/// Unlike the paginated `NotebookCarouselView` which presents a horizontal
/// carousel of fixed-size pages, `InfiniteCanvasView` shows a single canvas
/// with a much larger drawing area. The user can zoom out to see the whole
/// board or zoom in for fine detail. All standard drawing tools (pen, eraser,
/// shapes, stickers, text, etc.) work exactly as in paginated mode.
///
/// ## Usage
/// ```swift
/// InfiniteCanvasView(
///     note: note,
///     configurationForPage: { idx in makePageConfiguration(for: idx) },
///     callbacksForPage: { idx in makePageCallbacks(for: idx) },
///     toolStore: toolStore
/// )
/// ```
struct InfiniteCanvasView: View {

    /// The note model (always a single-page infinite canvas note).
    let note: Note

    /// Factory that builds a `CanvasPageConfiguration` for page 0.
    let configurationForPage: (Int) -> CanvasPageConfiguration
    /// Factory that builds a `CanvasPageCallbacks` for page 0.
    let callbacksForPage: (Int) -> CanvasPageCallbacks

    /// Reference to the drawing tool store for toolbar auto-fade.
    var toolStore: DrawingToolStore?
    /// Image provider for rendering sticker assets.
    var stickerImageProvider: ((String) -> UIImage?)?

    // MARK: - State

    /// Current zoom level of the canvas, used for UI overlays.
    @State private var currentZoom: CGFloat = 1.0
    /// Controls auto-hide of the zoom indicator after a delay.
    @State private var showZoomBadge = false
    /// Work item that auto-hides the zoom badge.
    @State private var zoomHideTask: DispatchWorkItem?

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            canvasView
            zoomIndicator
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Infinite canvas")
    }

    // MARK: - Canvas

    private var canvasView: some View {
        let config = configurationForPage(0)
        var callbacks = callbacksForPage(0)
        callbacks.onZoomChanged = { zoom in
            currentZoom = zoom
            showZoomBadge = true
            // Auto-hide after 1.5 seconds of no zoom changes.
            zoomHideTask?.cancel()
            let task = DispatchWorkItem { showZoomBadge = false }
            zoomHideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
        }

        return NotebookCanvasView(
            configuration: config,
            callbacks: callbacks,
            toolStore: toolStore,
            stickerImageProvider: stickerImageProvider
        )
        .equatable()
    }

    // MARK: - Zoom Indicator

    /// Current zoom as a percentage (e.g. 50, 200).
    private var zoomPercentage: Int {
        Int(round(currentZoom * 100))
    }

    /// Floating zoom-level badge in the bottom-right corner.
    /// Appears when the user zooms and auto-hides after 1.5 seconds.
    private var zoomIndicator: some View {
        Group {
            if showZoomBadge {
                Text("\(zoomPercentage)%")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: showZoomBadge)
                    .accessibilityLabel("Zoom \(zoomPercentage) percent")
            }
        }
    }
}
