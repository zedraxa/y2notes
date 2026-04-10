import SwiftUI

// MARK: - CanvasPageCallbacks

/// Groups every callback closure that a canvas page can fire.
///
/// Before this type, callbacks were passed as 15+ individual closure
/// parameters through the view hierarchy.  `CanvasPageCallbacks` bundles
/// them into a single struct that can be constructed once and forwarded
/// cheaply through `NotebookCarouselView` → `NotebookCanvasView`.
///
/// ## Thread Safety
/// All callbacks are invoked on the main thread.
///
/// ## Usage
/// ```swift
/// let callbacks = CanvasPageCallbacks.forPage(
///     pageIndex,
///     note: note,
///     noteStore: noteStore,
///     toolStore: toolStore,
///     stickerStore: stickerStore
/// )
/// ```
struct CanvasPageCallbacks {

    // MARK: - Drawing

    /// Drawing data changed (stroke committed, erased, or undo/redo).
    let onDrawingChanged: (Data) -> Void

    /// Canvas requests a disk flush (e.g. app backgrounding).
    let onSaveRequested: () -> Void

    /// Undo/redo state changed: (canUndo, canRedo).
    var onUndoStateChanged: ((Bool, Bool) -> Void)?

    /// Called with the canvas's UndoManager after the first drawing change.
    /// The parent view stores this reference to call undo/redo directly on
    /// the PKCanvasView's undo manager rather than relying on the SwiftUI
    /// environment undo manager, which may not be the same instance.
    var onCanvasUndoManagerAvailable: ((UndoManager?) -> Void)?

    // MARK: - Shapes

    /// Shape objects on this page were modified.
    var onShapesChanged: (([ShapeInstance]) -> Void)?

    // MARK: - Attachments

    /// Attachment objects on this page were modified.
    var onAttachmentsChanged: (([AttachmentObject]) -> Void)?
    /// Attachment selection changed (nil = deselected).
    var onAttachmentSelectionChanged: ((UUID?) -> Void)?

    // MARK: - Widgets

    /// Widget objects on this page were modified.
    var onWidgetsChanged: (([NoteWidget]) -> Void)?
    /// Widget selection changed (nil = deselected).
    var onWidgetSelectionChanged: ((UUID?) -> Void)?

    // MARK: - Stickers

    /// Sticker objects on this page were modified.
    var onStickersChanged: (([StickerInstance]) -> Void)?
    /// Sticker selection changed (nil = deselected).
    var onStickerSelectionChanged: ((UUID?) -> Void)?

    // MARK: - Text Objects

    /// Text objects on this page were modified.
    var onTextObjectsChanged: (([TextObject]) -> Void)?
    /// Text object selection changed (nil = deselected).
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    /// User tapped empty space while text tool is active.
    var onPlaceTextObject: ((CGPoint) -> Void)?

    // MARK: - Navigation

    /// User pinched-out to request the page overview grid.
    var onPinchToOverview: (() -> Void)?
    /// Zoom scale changed.
    var onZoomChanged: ((CGFloat) -> Void)?
    /// User swiped to turn a page (direction: +1 = forward, -1 = backward).
    /// Used by `NotebookReaderView`'s book-mode page-turn gesture.
    var onPageSwipe: ((Int) -> Void)?
}

// MARK: - Selection Helpers

extension CanvasPageCallbacks {

    /// Creates a selection-changed callback that clears all other object
    /// selections in the tool store before setting the new one.
    ///
    /// This eliminates the repetitive selection-clearing blocks that were
    /// previously duplicated for every object type in `NoteEditorView`.
    @MainActor static func selectionCallback<T>(
        for keyPath: ReferenceWritableKeyPath<DrawingToolStore, T?>,
        toolStore: DrawingToolStore,
        animation: Bool = true
    ) -> (T?) -> Void {
        return { newValue in
            let work = {
                toolStore[keyPath: keyPath] = newValue
                if newValue != nil {
                    // Clear all other object selections.
                    if keyPath != \.activeShapeSelection { toolStore.activeShapeSelection = nil }
                    if keyPath != \.activeStickerSelection { toolStore.activeStickerSelection = nil }
                    if keyPath != \.activeAttachmentSelection { toolStore.activeAttachmentSelection = nil }
                    if keyPath != \.activeWidgetSelection { toolStore.activeWidgetSelection = nil }
                    if keyPath != \.activeTextObjectSelection { toolStore.activeTextObjectSelection = nil }
                    toolStore.hasActiveSelection = false
                }
            }
            if animation {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { work() }
            } else {
                work()
            }
        }
    }
}

// MARK: - Factory

extension CanvasPageCallbacks {

    /// Builds a complete `CanvasPageCallbacks` for the given page, wiring all
    /// persistence and selection callbacks to the appropriate stores.
    ///
    /// This factory replaces the 100+ lines of callback wiring that was
    /// previously scattered across `NoteEditorView.canvasSection`.
    @MainActor static func forPage(
        _ pageIndex: Int,
        note: Note,
        noteStore: NoteStore,
        toolStore: DrawingToolStore,
        onUndoStateChanged: ((Bool, Bool) -> Void)? = nil,
        onPinchToOverview: (() -> Void)? = nil,
        onPlaceTextObject: ((CGPoint) -> Void)? = nil,
        onZoomChanged: ((CGFloat) -> Void)? = nil
    ) -> CanvasPageCallbacks {
        CanvasPageCallbacks(
            onDrawingChanged: { data in
                noteStore.updateDrawing(for: note.id, pageIndex: pageIndex, data: data)
            },
            onSaveRequested: { noteStore.save() },
            onUndoStateChanged: onUndoStateChanged,
            onShapesChanged: { shapes in
                noteStore.updateShapes(for: note.id, pageIndex: pageIndex, shapes: shapes)
            },
            onAttachmentsChanged: { atts in
                noteStore.updateAttachments(for: note.id, pageIndex: pageIndex, attachments: atts)
            },
            onAttachmentSelectionChanged: selectionCallback(
                for: \.activeAttachmentSelection, toolStore: toolStore
            ),
            onWidgetsChanged: { widgets in
                noteStore.updateWidgets(for: note.id, pageIndex: pageIndex, widgets: widgets)
            },
            onWidgetSelectionChanged: selectionCallback(
                for: \.activeWidgetSelection, toolStore: toolStore
            ),
            onStickersChanged: { stickers in
                noteStore.updateStickers(for: note.id, pageIndex: pageIndex, stickers: stickers)
            },
            onStickerSelectionChanged: selectionCallback(
                for: \.activeStickerSelection, toolStore: toolStore
            ),
            onTextObjectsChanged: { objs in
                noteStore.updateTextObjects(for: note.id, pageIndex: pageIndex, textObjects: objs)
            },
            onTextObjectSelectionChanged: selectionCallback(
                for: \.activeTextObjectSelection, toolStore: toolStore
            ),
            onPlaceTextObject: onPlaceTextObject,
            onPinchToOverview: onPinchToOverview,
            onZoomChanged: onZoomChanged
        )
    }
}
