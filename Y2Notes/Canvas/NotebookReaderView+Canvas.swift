import SwiftUI
import PencilKit

// MARK: - NotebookReaderView + Canvas Configuration

/// Extension that provides configuration-driven canvas construction for
/// `NotebookReaderView`, mirroring the pattern established in
/// `NoteEditorView+Canvas.swift`.
///
/// This replaces the 30-line inline `CanvasView(...)` call in `canvasForPage(_:in:)`
/// with structured factories that use the same `CanvasPageConfiguration` /
/// `CanvasPageCallbacks` types used by the editor.
extension NotebookReaderView {

    // MARK: - Configuration Factory

    /// Builds a `CanvasPageConfiguration` for a reader page.
    ///
    /// Reader pages use simpler defaults than editor pages:
    /// - Drawing policy is always `.anyInput` (no pencil-only toggle in reader).
    /// - Zoom reset trigger is always `false` (reader manages page turns, not zoom).
    /// - `isNewPage` is always `false` (reader doesn't add pages inline).
    func makeReaderPageConfiguration(
        for note: Note,
        at ref: PageRef
    ) -> CanvasPageConfiguration {
        let pageData = note.pages.indices.contains(ref.pageIndex)
            ? note.pages[ref.pageIndex] : Data()

        return CanvasPageConfiguration(
            noteID: note.id,
            pageIndex: ref.pageIndex,
            drawingData: pageData,
            currentTool: inkStore.activePreset?.pkTool ?? toolStore.pkTool,
            drawingPolicy: .anyInput,
            backgroundColor: canvasBackground(for: ref),
            defaultInkColor: effectiveDefinition.contrastingInkColor,
            pageType: effectivePageType(for: ref),
            paperMaterial: effectivePaperMaterial,
            isShapeToolActive: toolStore.activeTool == .shape,
            activeShapeType: toolStore.activeShapeType,
            shapeColor: toolStore.activeColor,
            shapeWidth: toolStore.activeWidth,
            activeFX: inkStore.resolvedFX,
            fxColor: inkStore.activePreset?.uiColor ?? toolStore.activeColor,
            isMagicModeActive: false,
            isStudyModeActive: false,
            activeAmbientScene: nil,
            isAmbientSoundEnabled: true,
            shapes: note.shapes(forPage: ref.pageIndex),
            attachments: note.attachments(forPage: ref.pageIndex),
            attachmentNoteID: note.id,
            widgets: note.widgets(forPage: ref.pageIndex),
            stickers: note.stickers(forPage: ref.pageIndex),
            textObjects: note.textObjects(forPage: ref.pageIndex),
            isTextToolActive: toolStore.activeTool == .text,
            pdfURL: noteStore.notePDFURL(for: note),
            pageCount: note.pageCount,
            isNewPage: false,
            zoomResetTrigger: false,
            initialZoomScale: nil,
            isInfiniteCanvas: false
        )
    }

    // MARK: - Callbacks Factory

    /// Builds a `CanvasPageCallbacks` for a reader page.
    ///
    /// Wires drawing persistence, navigation, and object-layer persistence
    /// callbacks so shapes, attachments, widgets, stickers, and text objects
    /// are fully functional in reader mode.
    func makeReaderPageCallbacks(
        for ref: PageRef,
        totalPages: Int
    ) -> CanvasPageCallbacks {
        var callbacks = CanvasPageCallbacks(
            onDrawingChanged: { data in
                noteStore.updateDrawing(for: ref.noteID, pageIndex: ref.pageIndex, data: data)
            },
            onSaveRequested: { noteStore.save() }
        )
        callbacks.onUndoStateChanged = { [self] canUndoVal, canRedoVal in
            canUndo = canUndoVal
            canRedo = canRedoVal
        }
        callbacks.onPinchToOverview = { showPageOverview = true }
        callbacks.onPageSwipe = { direction in
            turnPage(direction: direction, totalPages: totalPages)
        }
        // Object layer persistence
        callbacks.onShapesChanged = { shapes in
            noteStore.updateShapes(for: ref.noteID, pageIndex: ref.pageIndex, shapes: shapes)
        }
        callbacks.onAttachmentsChanged = { atts in
            noteStore.updateAttachments(for: ref.noteID, pageIndex: ref.pageIndex, attachments: atts)
        }
        callbacks.onAttachmentSelectionChanged = CanvasPageCallbacks.selectionCallback(
            for: \.activeAttachmentSelection, toolStore: toolStore
        )
        callbacks.onWidgetsChanged = { widgets in
            noteStore.updateWidgets(for: ref.noteID, pageIndex: ref.pageIndex, widgets: widgets)
        }
        callbacks.onWidgetSelectionChanged = CanvasPageCallbacks.selectionCallback(
            for: \.activeWidgetSelection, toolStore: toolStore
        )
        callbacks.onStickersChanged = { stickers in
            noteStore.updateStickers(for: ref.noteID, pageIndex: ref.pageIndex, stickers: stickers)
        }
        callbacks.onStickerSelectionChanged = CanvasPageCallbacks.selectionCallback(
            for: \.activeStickerSelection, toolStore: toolStore
        )
        callbacks.onTextObjectsChanged = { objs in
            noteStore.updateTextObjects(for: ref.noteID, pageIndex: ref.pageIndex, textObjects: objs)
        }
        callbacks.onTextObjectSelectionChanged = CanvasPageCallbacks.selectionCallback(
            for: \.activeTextObjectSelection, toolStore: toolStore
        )
        return callbacks
    }

    // MARK: - Reader Canvas Section

    /// Configuration-driven canvas for a reader page, replacing the inline
    /// `CanvasView(...)` construction.
    @ViewBuilder
    func readerCanvasForPage(_ ref: PageRef, in pages: [PageRef]) -> some View {
        if let note = noteStore.notes.first(where: { $0.id == ref.noteID }) {
            let config = makeReaderPageConfiguration(for: note, at: ref)
            let callbacks = makeReaderPageCallbacks(for: ref, totalPages: pages.count)

            ReaderCanvasView(
                configuration: config,
                callbacks: callbacks,
                toolStore: toolStore,
                stickerImageProvider: { id in
                    guard let asset = stickerStore.asset(for: id) else { return nil }
                    return stickerStore.image(for: asset)
                }
            )
            .equatable()
            .overlay(alignment: .bottom) {
                pageNumberWatermark(flatIndex: flatPageIndex, totalPages: pages.count)
            }
            .overlay(alignment: .leading) {
                if effectivePageType(for: ref) == .ruled {
                    Rectangle()
                        .fill(Color.red.opacity(0.08))
                        .frame(width: 1)
                        .padding(.leading, 28)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
            .padding(.horizontal, 4)
        }
    }
}
