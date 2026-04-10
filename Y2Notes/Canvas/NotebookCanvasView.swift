import SwiftUI
import PencilKit

// MARK: - NotebookCanvasView

/// A clean, configuration-driven wrapper around `CanvasPageView` for use in the
/// notebook canvas experience.
///
/// `NotebookCanvasView` accepts a `CanvasPageConfiguration` and
/// `CanvasPageCallbacks` instead of 60+ individual parameters, dramatically
/// simplifying the view hierarchy and reducing parameter drilling.
///
/// ## Design Principles
/// - **Configuration-first**: all state comes from a single value type.
/// - **Callback-bundled**: all outputs go through a single callbacks struct.
/// - **Adapter pattern**: internally creates a `CanvasPageView` so all
///   existing rendering, effects, and PencilKit integration is preserved.
/// - **Diff-aware**: because `CanvasPageConfiguration` conforms to `Equatable`,
///   the `CanvasPageView` inside is guarded by `.equatable()` so SwiftUI skips
///   the UIViewRepresentable update cycle entirely when nothing changed.
///
/// ## Usage
/// ```swift
/// NotebookCanvasView(
///     configuration: config,
///     callbacks: callbacks,
///     toolStore: toolStore,
///     stickerImageProvider: { id in stickerStore.image(for: id) }
/// )
/// ```
struct NotebookCanvasView: View {

    /// Immutable configuration snapshot for this canvas page.
    let configuration: CanvasPageConfiguration

    /// Bundled callbacks for drawing changes, object mutations, and navigation.
    let callbacks: CanvasPageCallbacks

    /// Reference to the drawing tool store for toolbar auto-fade and selection sync.
    var toolStore: DrawingToolStore?

    /// Image provider for rendering sticker assets.
    var stickerImageProvider: ((String) -> UIImage?)?

    var body: some View {
        CanvasPageView(
            noteID: configuration.noteID,
            drawingData: configuration.drawingData,
            backgroundColor: configuration.backgroundColor,
            defaultInkColor: configuration.defaultInkColor,
            currentTool: configuration.currentTool,
            isShapeToolActive: configuration.isShapeToolActive,
            activeShapeType: configuration.activeShapeType,
            shapeColor: configuration.shapeColor,
            shapeWidth: configuration.shapeWidth,
            drawingPolicy: configuration.drawingPolicy,
            zoomResetTrigger: configuration.zoomResetTrigger,
            pageType: configuration.pageType,
            activeFX: configuration.activeFX,
            fxColor: configuration.fxColor,
            pageIndex: configuration.pageIndex,
            onDrawingChanged: callbacks.onDrawingChanged,
            onSaveRequested: callbacks.onSaveRequested,
            onUndoStateChanged: callbacks.onUndoStateChanged,
            onPinchToOverview: callbacks.onPinchToOverview,
            pdfURL: configuration.pdfURL,
            toolStoreForFade: toolStore,
            currentPageShapes: configuration.shapes,
            onShapesChanged: callbacks.onShapesChanged,
            currentPageAttachments: configuration.attachments,
            attachmentNoteID: configuration.attachmentNoteID,
            onAttachmentsChanged: callbacks.onAttachmentsChanged,
            onAttachmentSelectionChanged: callbacks.onAttachmentSelectionChanged,
            currentPageWidgets: configuration.widgets,
            onWidgetsChanged: callbacks.onWidgetsChanged,
            onWidgetSelectionChanged: callbacks.onWidgetSelectionChanged,
            currentPageStickers: configuration.stickers,
            onStickersChanged: callbacks.onStickersChanged,
            onStickerSelectionChanged: callbacks.onStickerSelectionChanged,
            stickerImageProvider: stickerImageProvider,
            isTextToolActive: configuration.isTextToolActive,
            currentPageTextObjects: configuration.textObjects,
            onTextObjectsChanged: callbacks.onTextObjectsChanged,
            onTextObjectSelectionChanged: callbacks.onTextObjectSelectionChanged,
            onPlaceTextObject: callbacks.onPlaceTextObject,
            pageCount: configuration.pageCount,
            isMagicModeActive: configuration.isMagicModeActive,
            isStudyModeActive: configuration.isStudyModeActive,
            activeAmbientScene: configuration.activeAmbientScene,
            isAmbientSoundEnabled: configuration.isAmbientSoundEnabled,
            isNewPage: configuration.isNewPage,
            onZoomChanged: callbacks.onZoomChanged,
            initialZoomScale: configuration.initialZoomScale,
            isInfiniteCanvas: configuration.isInfiniteCanvas
        )
    }
}

// MARK: - NotebookCanvasView + Equatable

/// Wrapper that tells SwiftUI to skip re-rendering when the configuration
/// hasn't changed.  This is the diff optimization payoff: `CanvasPageConfiguration`
/// is `Equatable`, so the `EquatableView` guard prevents the entire
/// `updateUIView` cycle from running when no configuration field changed.
extension NotebookCanvasView: Equatable {
    static func == (lhs: NotebookCanvasView, rhs: NotebookCanvasView) -> Bool {
        lhs.configuration == rhs.configuration
    }
}
