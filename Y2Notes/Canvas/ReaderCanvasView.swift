import SwiftUI
import PencilKit

// MARK: - ReaderCanvasView

/// Configuration-driven canvas adapter for `NotebookReaderView`'s book mode.
///
/// Unlike `NotebookCanvasView` (which wraps the full-featured `CanvasPageView`
/// with object overlays), `ReaderCanvasView` wraps the lighter `CanvasView`
/// which includes the page-swipe gesture for book-like page turns.
///
/// ## Why a separate adapter?
/// The notebook reader and the note editor have different interaction models:
/// - **Editor**: horizontal ScrollView carousel, full object overlays, stickers.
/// - **Reader**: swipe-to-turn-page gesture, page-stack shadows, no object editing.
///
/// `ReaderCanvasView` uses the same `CanvasPageConfiguration` / `CanvasPageCallbacks`
/// types so all parameter construction is consistent across both experiences.
///
/// ## Usage
/// ```swift
/// ReaderCanvasView(
///     configuration: config,
///     callbacks: callbacks,
///     toolStore: toolStore
/// )
/// ```
struct ReaderCanvasView: View {

    /// Immutable configuration snapshot for this canvas page.
    let configuration: CanvasPageConfiguration

    /// Bundled callbacks for drawing changes and navigation.
    let callbacks: CanvasPageCallbacks

    /// Reference to the drawing tool store for toolbar auto-fade.
    var toolStore: DrawingToolStore?

    /// Image provider for rendering sticker assets.
    var stickerImageProvider: ((String) -> UIImage?)?

    var body: some View {
        CanvasView(
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
            onPageSwipe: callbacks.onPageSwipe,
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
            isNewPage: configuration.isNewPage
        )
    }
}

// MARK: - ReaderCanvasView + Equatable

/// Equatable conformance lets SwiftUI skip re-rendering when the page
/// configuration hasn't changed. Particularly valuable in the reader where
/// page-turn animations can trigger redundant updates on the non-visible
/// previous page.
extension ReaderCanvasView: Equatable {
    static func == (lhs: ReaderCanvasView, rhs: ReaderCanvasView) -> Bool {
        lhs.configuration == rhs.configuration
    }
}
