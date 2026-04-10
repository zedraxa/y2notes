import SwiftUI

// MARK: - NoteEditorView+Actions

extension NoteEditorView {

    // MARK: - Sticker Placement

    /// Places a sticker asset at the center of the current page.
    func placeSticker(_ asset: StickerAsset) {
        guard var updatedNote = noteStore.notes.first(where: { $0.id == note.id }) else { return }
        let pageIdx = currentPageIndex

        // Ensure stickerLayers array is sized to match pages
        while updatedNote.stickerLayers.count < updatedNote.pages.count {
            updatedNote.stickerLayers.append(nil)
        }

        var existing = updatedNote.stickerLayers[pageIdx] ?? []

        // Enforce per-page limit
        guard existing.count < StickerConstants.maxStickersPerPage else { return }

        let maxZ = existing.map(\.zIndex).max() ?? 0

        // Place at approximate center of page
        let pageSize = CanvasView.pageSize
        let center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)

        let instance = StickerInstance(
            stickerID: asset.id,
            position: center,
            scale: 1.0,
            rotation: 0,
            opacity: 1.0,
            zIndex: maxZ + 1,
            isLocked: false
        )

        existing.append(instance)
        updatedNote.stickerLayers[pageIdx] = existing
        updatedNote.modifiedAt = Date()

        noteStore.updateStickers(for: note.id, pageIndex: pageIdx, stickers: existing)
    }

    // MARK: - Widget Placement

    /// Places a new widget of the given kind at the centre of the current page.
    func placeWidget(_ kind: WidgetKind) {
        let pageIdx = currentPageIndex
        var widgets = note.widgets(forPage: pageIdx)

        // Enforce per-page limit
        guard widgets.count < WidgetConstants.maxWidgetsPerPage else { return }

        let maxZ = widgets.map(\.zIndex).max() ?? 0

        // Place at approximate centre of page
        let pageSize = CanvasView.pageSize
        let center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)

        var widget: NoteWidget
        switch kind {
        case .checklist:
            widget = NoteWidget.makeChecklist(at: center)
        case .quickTable:
            widget = NoteWidget.makeQuickTable(at: center)
        case .calloutBox:
            widget = NoteWidget.makeCalloutBox(at: center)
        case .referenceCard:
            widget = NoteWidget.makeReferenceCard(at: center)
        case .stickyNote:
            widget = NoteWidget.makeStickyNote(at: center)
        case .flashcard:
            widget = NoteWidget.makeFlashcard(at: center)
        case .progressTracker:
            widget = NoteWidget.makeProgressTracker(at: center)
        }
        widget.zIndex = maxZ + 1

        widgets.append(widget)
        noteStore.updateWidgets(for: note.id, pageIndex: pageIdx, widgets: widgets)

        // Auto-select the newly placed widget
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            toolStore.activeWidgetSelection = widget.id
            toolStore.activeShapeSelection = nil
            toolStore.activeStickerSelection = nil
            toolStore.activeAttachmentSelection = nil
            toolStore.activeTextObjectSelection = nil
            toolStore.hasActiveSelection = false
        }
    }

    // MARK: - Text Object Placement

    /// Places a new empty text box anchored at the given page-coordinate point.
    func placeTextObject(at tapPoint: CGPoint) {
        let pageIdx = currentPageIndex
        var objects = note.textObjects(forPage: pageIdx)

        // Enforce per-page limit
        guard objects.count < TextObjectConstants.maxTextObjectsPerPage else { return }

        let maxZ = objects.map(\.zIndex).max() ?? 0
        let size = TextObjectConstants.defaultSize
        // Centre the box on the tap point
        let origin = CGPoint(x: tapPoint.x - size.width / 2, y: tapPoint.y - size.height / 2)
        let frame = CGRect(origin: origin, size: size)

        let obj = TextObject(
            frame: frame,
            fontSize: toolStore.activeTextFontSize,
            fontFamily: toolStore.activeTextFontFamily,
            isBold: toolStore.activeTextBold,
            textColor: .label,
            alignment: toolStore.activeTextAlignment,
            zIndex: maxZ + 1
        )

        objects.append(obj)
        noteStore.updateTextObjects(for: note.id, pageIndex: pageIdx, textObjects: objects)

        // Auto-select so the user can immediately start editing
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            toolStore.activeTextObjectSelection = obj.id
            toolStore.activeShapeSelection = nil
            toolStore.activeStickerSelection = nil
            toolStore.activeAttachmentSelection = nil
            toolStore.activeWidgetSelection = nil
            toolStore.hasActiveSelection = false
        }
    }

    // MARK: - Shape Actions

    /// Handles actions from the shape action bar.
    func handleShapeAction(_ action: ShapeAction, for shapeID: UUID) {
        let pageIdx = currentPageIndex
        var shapes = note.shapes(forPage: pageIdx)
        guard let idx = shapes.firstIndex(where: { $0.id == shapeID }) else { return }

        switch action {
        case .duplicate:
            var copy = shapes[idx]
            copy = ShapeInstance(
                shapeType: copy.shapeType,
                frame: copy.frame.offsetBy(dx: 20, dy: 20),
                rotation: copy.rotation,
                style: copy.style,
                zIndex: (shapes.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false
            )
            shapes.append(copy)
            toolStore.activeShapeSelection = copy.id

        case .delete:
            shapes.remove(at: idx)
            toolStore.activeShapeSelection = nil

        case .toggleLock:
            shapes[idx].isLocked.toggle()

        case .bringToFront:
            let maxZ = shapes.map(\.zIndex).max() ?? 0
            shapes[idx].zIndex = maxZ + 1

        case .sendToBack:
            let minZ = shapes.map(\.zIndex).min() ?? 0
            shapes[idx].zIndex = minZ - 1

        case .updateStyle(let newStyle):
            shapes[idx].style = newStyle
        }

        noteStore.updateShapes(for: note.id, pageIndex: pageIdx, shapes: shapes)
    }

    // MARK: - Attachment Actions

    func handleAttachmentAction(_ action: AttachmentAction, for attachmentID: UUID) {
        let pageIdx = currentPageIndex
        var attachments = note.attachments(forPage: pageIdx)
        guard let idx = attachments.firstIndex(where: { $0.id == attachmentID }) else { return }

        switch action {
        case .expand:
            // Handled by presenting AttachmentViewerView — signal via state
            break

        case .duplicate:
            var copy = attachments[idx]
            copy = AttachmentObject(
                type: copy.type,
                frame: AttachmentFrame(
                    position: CGPoint(
                        x: copy.frame.position.x + AttachmentConstants.duplicateOffset,
                        y: copy.frame.position.y + AttachmentConstants.duplicateOffset
                    ),
                    size: copy.frame.size
                ),
                label: copy.label,
                zIndex: (attachments.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false,
                aspectRatio: copy.aspectRatio,
                fileExtension: copy.fileExtension,
                linkURL: copy.linkURL
            )
            attachments.append(copy)
            toolStore.activeAttachmentSelection = copy.id

        case .toggleLock:
            attachments[idx].isLocked.toggle()

        case .delete:
            let removed = attachments.remove(at: idx)
            toolStore.activeAttachmentSelection = nil
            AttachmentStore.shared.deleteAttachmentFiles(
                noteID: note.id,
                attachmentID: removed.id,
                ext: removed.fileExtension
            )
        }

        noteStore.updateAttachments(for: note.id, pageIndex: pageIdx, attachments: attachments)
    }

    // MARK: - Widget Actions

    func handleWidgetAction(_ action: WidgetAction, for widgetID: UUID) {
        let pageIdx = currentPageIndex
        var widgets = note.widgets(forPage: pageIdx)
        guard let idx = widgets.firstIndex(where: { $0.id == widgetID }) else { return }

        switch action {
        case .edit:
            widgetToEdit = widgets[idx]

        case .duplicate:
            let source = widgets[idx]
            let copy = NoteWidget(
                kind: source.kind,
                frame: WidgetFrame(
                    position: CGPoint(
                        x: source.frame.position.x + WidgetConstants.duplicateOffset,
                        y: source.frame.position.y + WidgetConstants.duplicateOffset
                    ),
                    size: source.frame.size
                ),
                payload: source.payload,
                zIndex: (widgets.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false,
                borderColorComponents: source.borderColorComponents
            )
            widgets.append(copy)
            toolStore.activeWidgetSelection = copy.id

        case .toggleLock:
            widgets[idx].isLocked.toggle()

        case .bringForward:
            let maxZ = widgets.map(\.zIndex).max() ?? 0
            if widgets[idx].zIndex < maxZ {
                widgets[idx].zIndex += 1
            }

        case .sendBack:
            let minZ = widgets.map(\.zIndex).min() ?? 0
            if widgets[idx].zIndex > minZ {
                widgets[idx].zIndex -= 1
            }

        case .delete:
            widgets.remove(at: idx)
            toolStore.activeWidgetSelection = nil
        }

        noteStore.updateWidgets(for: note.id, pageIndex: pageIdx, widgets: widgets)
    }

    // MARK: - Text Object Actions

    /// Handles actions from the text object action bar.
    func handleTextObjectAction(_ action: TextObjectAction, for textObjectID: UUID) {
        let pageIdx = currentPageIndex
        var textObjects = note.textObjects(forPage: pageIdx)
        guard let idx = textObjects.firstIndex(where: { $0.id == textObjectID }) else { return }

        switch action {
        case .duplicate:
            let source = textObjects[idx]
            let copy = TextObject(
                content: source.content,
                frame: source.frame.offsetBy(dx: 20, dy: 20),
                fontSize: source.fontSize,
                fontFamily: source.fontFamily,
                isBold: source.isBold,
                textColor: source.textColor,
                backgroundColor: source.backgroundColor,
                alignment: source.textAlignment,
                rotation: source.rotation,
                opacity: source.opacity,
                zIndex: (textObjects.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false,
                borderRadius: source.borderRadius,
                borderColor: source.borderColor,
                borderWidth: source.borderWidth
            )
            textObjects.append(copy)
            toolStore.activeTextObjectSelection = copy.id

        case .delete:
            textObjects.remove(at: idx)
            toolStore.activeTextObjectSelection = nil

        case .toggleLock:
            textObjects[idx].isLocked.toggle()

        case .bringToFront:
            let maxZ = textObjects.map(\.zIndex).max() ?? 0
            textObjects[idx].zIndex = maxZ + 1

        case .sendToBack:
            let minZ = textObjects.map(\.zIndex).min() ?? 0
            textObjects[idx].zIndex = minZ - 1

        case .updateFontSize(let size):
            textObjects[idx].fontSize = size

        case .updateFontFamily(let family):
            textObjects[idx].fontFamily = family

        case .toggleBold:
            textObjects[idx].isBold.toggle()

        case .updateAlignment(let alignment):
            switch alignment {
            case .center: textObjects[idx].alignmentRaw = 1
            case .right:  textObjects[idx].alignmentRaw = 2
            default:      textObjects[idx].alignmentRaw = 0
            }

        case .updateTextColor(let color):
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            textObjects[idx].textColorComponents = [Double(r), Double(g), Double(b), Double(a)]

        case .updateBackgroundColor(let color):
            if let bg = color {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                bg.getRed(&r, green: &g, blue: &b, alpha: &a)
                textObjects[idx].backgroundColorComponents = [Double(r), Double(g), Double(b), Double(a)]
            } else {
                textObjects[idx].backgroundColorComponents = nil
            }

        case .updateBorderRadius(let radius):
            textObjects[idx].borderRadius = radius

        case .updateBorderColor(let color):
            if let bc = color {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                bc.getRed(&r, green: &g, blue: &b, alpha: &a)
                textObjects[idx].borderColorComponents = [Double(r), Double(g), Double(b), Double(a)]
            } else {
                textObjects[idx].borderColorComponents = nil
            }

        case .updateBorderWidth(let width):
            textObjects[idx].borderWidth = width
        }

        noteStore.updateTextObjects(for: note.id, pageIndex: pageIdx, textObjects: textObjects)
    }


    // MARK: - Undo/Redo State

    func refreshUndoRedoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    // MARK: - Linked Import Navigation

    /// Opens the PDF or document that this note was created to accompany.
    ///
    /// If the linked import no longer exists (e.g. user deleted it), the action is a no-op.
    func openLinkedImport() {
        if let pdfID = note.linkedPDFID,
           let record = pdfStore.records.first(where: { $0.id == pdfID }) {
            workspace.openTab(
                .pdf(id: record.id),
                displayName: record.title,
                accentColor: [0.8, 0.3, 0.3]
            )
        } else if let docID = note.linkedDocumentID,
                  let doc = documentStore.documents.first(where: { $0.id == docID }) {
            workspace.openTab(
                .document(id: doc.id),
                displayName: doc.displayName,
                accentColor: [0.3, 0.5, 0.7]
            )
        }
    }

    // MARK: - Selection Actions

    /// Dispatches standard UIResponder actions for lasso-selected strokes
    /// to the canvas's responder chain. PencilKit's built-in lasso selection
    /// supports cut/copy/paste/delete through the standard UIResponder actions.
    func handleSelectionAction(_ action: SelectionAction) {
        // The canvas is first responder; dispatch standard UIResponder actions
        // which PencilKit handles for lasso selections.
        let app = UIApplication.shared
        switch action {
        case .cut:
            app.sendAction(#selector(UIResponderStandardEditActions.cut(_:)), to: nil, from: nil, for: nil)
            toolStore.hasActiveSelection = false
        case .copy:
            app.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: nil, for: nil)
        case .duplicate:
            // Copy then paste in-place to duplicate selected strokes
            app.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: nil, for: nil)
            app.sendAction(#selector(UIResponderStandardEditActions.paste(_:)), to: nil, from: nil, for: nil)
        case .delete:
            app.sendAction(#selector(UIResponderStandardEditActions.delete(_:)), to: nil, from: nil, for: nil)
            toolStore.hasActiveSelection = false
        }
    }

}
