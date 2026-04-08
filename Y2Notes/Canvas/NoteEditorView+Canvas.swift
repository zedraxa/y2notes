import SwiftUI
import PencilKit

// MARK: - NoteEditorView + Notebook Canvas

/// Extension that provides the modernised, configuration-driven canvas section
/// for `NoteEditorView`.
///
/// This replaces the 100-line `canvasSection` computed property with a clean
/// builder that uses `CanvasPageConfiguration` and `CanvasPageCallbacks` to
/// eliminate parameter drilling and repetitive callback wiring.
extension NoteEditorView {

    // MARK: - Configuration Factory

    /// Builds a `CanvasPageConfiguration` for the given page index.
    ///
    /// Called once per page per SwiftUI render cycle. All the scattered
    /// parameter assembly that was previously in `canvasSection` is now
    /// centralised here.
    func makePageConfiguration(for pageIndex: Int) -> CanvasPageConfiguration {
        .page(
            for: note,
            at: pageIndex,
            toolStore: toolStore,
            inkStore: inkStore,
            backgroundColor: canvasBackgroundColor,
            defaultInkColor: effectiveDefinition.contrastingInkColor,
            drawingPolicy: pencilOnlyDrawing ? .pencilOnly : .anyInput,
            paperMaterial: effectivePaperMaterial,
            pageTypeForIndex: { idx in effectivePageType(forPage: idx) },
            pdfURL: noteStore.notePDFURL(for: note),
            zoomResetTrigger: zoomResetTrigger,
            isNewPage: isNewPageJustAdded && pageIndex == currentPageIndex,
            initialZoomScale: nil
        )
    }

    // MARK: - Callbacks Factory

    /// Builds a `CanvasPageCallbacks` for the given page index.
    ///
    /// This replaces the 80+ lines of callback wiring that were previously
    /// inlined in the `canvasSection` computed property.
    func makePageCallbacks(for pageIndex: Int) -> CanvasPageCallbacks {
        .forPage(
            pageIndex,
            note: note,
            noteStore: noteStore,
            toolStore: toolStore,
            onUndoStateChanged: { canUndoVal, canRedoVal in
                canUndo = canUndoVal
                canRedo = canRedoVal
            },
            onPinchToOverview: { showPageOverview = true },
            onPlaceTextObject: { point in placeTextObject(at: point) }
        )
    }

    // MARK: - Notebook Canvas Section

    /// SwiftUI-native page carousel using the redesigned configuration-driven API.
    ///
    /// This replaces the old `canvasSection` that passed 60+ individual parameters
    /// through the view hierarchy.
    @ViewBuilder
    var notebookCanvasSection: some View {
        NotebookCarouselView(
            note: note,
            currentPageIndex: $currentPageIndex,
            configurationForPage: { idx in makePageConfiguration(for: idx) },
            callbacksForPage: { idx in makePageCallbacks(for: idx) },
            toolStore: toolStore,
            stickerImageProvider: { id in
                guard let asset = stickerStore.asset(for: id) else { return nil }
                return stickerStore.image(for: asset)
            }
        )
    }
}
