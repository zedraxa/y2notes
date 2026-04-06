import SwiftUI

// MARK: - NoteEditorView+Export

extension NoteEditorView {

    // MARK: - Export Functions

    /// Exports only the current page as a single-page PDF and presents the share sheet.
    func exportCurrentPageAsPDF(pageIndex: Int) {
        guard note.pages.indices.contains(pageIndex) else { return }
        let pageData = note.pages[pageIndex]
        let pt = effectivePageType(forPage: pageIndex)
        let bg = canvasBackgroundColor
        let title = note.title.isEmpty ? "Note" : note.title
        let attachments = note.attachments(forPage: pageIndex)
        let widgets = note.widgets(forPage: pageIndex)
        let nid = note.id
        isExporting = true
        Task {
            let url = await NoteExporter.exportAsPDF(
                title: "\(title) — Page \(pageIndex + 1)",
                pages: [pageData],
                attachmentLayers: [attachments.isEmpty ? nil : attachments],
                widgetLayers: [widgets.isEmpty ? nil : widgets],
                noteID: nid,
                backgroundColor: bg,
                pageTypes: [pt]
            )
            await MainActor.run {
                isExporting = false
                if let url {
                    shareItems = [url]
                    showShareSheet = true
                }
            }
        }
    }

    /// Exports every page of the note as a multi-page PDF and presents the share sheet.
    /// When the note has a maintained backing PDF, shares it directly without re-rendering.
    func exportAllPagesAsPDF() {
        let attachmentLayers = note.attachmentLayers
        let widgetLayersData = note.widgetLayers
        let nid = note.id

        // Fast path: share the maintained PDF file directly when available.
        if let pdfURL = noteStore.notePDFURL(for: note),
           FileManager.default.fileExists(atPath: pdfURL.path) {
            // Force a synchronous regeneration so the PDF reflects the very latest strokes.
            if let filename = note.pdfFilename {
                let pageTypes = (0..<note.pageCount).map { effectivePageType(forPage: $0) }
                NotePDFGenerator.regeneratePDF(
                    filename: filename,
                    pages: note.pages,
                    attachmentLayers: attachmentLayers,
                    noteID: nid,
                    backgroundColor: canvasBackgroundColor,
                    pageTypes: pageTypes
                )
            }
            shareItems = [pdfURL]
            showShareSheet = true
            return
        }
        // Fallback: render a new PDF from scratch (legacy notes without backing PDF).
        let pages = note.pages
        let pageTypes = (0..<note.pageCount).map { effectivePageType(forPage: $0) }
        let bg = canvasBackgroundColor
        let title = note.title.isEmpty ? "Note" : note.title
        isExporting = true
        Task {
            let url = await NoteExporter.exportAsPDF(
                title: title,
                pages: pages,
                attachmentLayers: attachmentLayers,
                widgetLayers: widgetLayersData,
                noteID: nid,
                backgroundColor: bg,
                pageTypes: pageTypes
            )
            await MainActor.run {
                isExporting = false
                if let url {
                    shareItems = [url]
                    showShareSheet = true
                }
            }
        }
    }

    /// Exports the current page as a PNG image and presents the share sheet.
    func exportCurrentPageAsImage(pageIndex: Int) {
        guard note.pages.indices.contains(pageIndex) else { return }
        let pageData = note.pages[pageIndex]
        let pt = effectivePageType(forPage: pageIndex)
        let bg = canvasBackgroundColor
        let attachments = note.attachments(forPage: pageIndex)
        let widgets = note.widgets(forPage: pageIndex)
        let nid = note.id
        isExporting = true
        Task {
            let image = await NoteExporter.exportPageAsImage(
                pageData: pageData,
                attachments: attachments.isEmpty ? nil : attachments,
                widgets: widgets.isEmpty ? nil : widgets,
                noteID: nid,
                backgroundColor: bg,
                pageType: pt
            )
            await MainActor.run {
                isExporting = false
                if let image {
                    shareItems = [image]
                    showShareSheet = true
                }
            }
        }
    }

    // MARK: - Find Bar Logic

    func updateFindMatches() {
        findMatches = searchService.findInDocument(query: findQuery, note: note)
        findMatchIndex = 0
    }

    func advanceFindMatch(forward: Bool) {
        guard !findMatches.isEmpty else { return }
        if forward {
            findMatchIndex = (findMatchIndex + 1) % findMatches.count
        } else {
            findMatchIndex = (findMatchIndex - 1 + findMatches.count) % findMatches.count
        }
    }

    // MARK: - Text Save Logic

    /// Schedules a debounced persist of the current `typedTextContent`.
    /// Mirrors the 0.8 s debounce used by the drawing layer.
    func scheduleTextSave() {
        textSaveTimer?.invalidate()
        let id   = note.id
        let text = typedTextContent
        let store = noteStore
        textSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
            store.updateTypedText(for: id, text: text)
        }
    }

    /// Immediately cancels the pending debounce timer and persists typed text to the store.
    func flushTextNow() {
        textSaveTimer?.invalidate()
        textSaveTimer = nil
        noteStore.updateTypedText(for: note.id, text: typedTextContent)
    }
}
