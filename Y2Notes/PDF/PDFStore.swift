import Foundation
import PDFKit
import PencilKit
import UIKit

// MARK: - PDFStore

/// Manages the collection of imported PDF documents, their on-disk copies,
/// per-page annotation / sticker / widget data, and annotated-PDF export.
@MainActor
final class PDFStore: ObservableObject {

    @Published private(set) var records: [PDFNoteRecord] = []

    // MARK: - Storage paths

    private let metadataURL: URL
    /// Directory where imported PDF files are stored.
    let pdfDirectory: URL

    // MARK: - Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        metadataURL = docs.appendingPathComponent("y2notes_pdfs.json")
        pdfDirectory = docs.appendingPathComponent("PDFNotes")
        try? FileManager.default.createDirectory(
            at: pdfDirectory, withIntermediateDirectories: true, attributes: nil
        )
        load()
    }

    // MARK: - Import

    /// Copies the PDF at `sourceURL` into the app's PDFNotes directory and
    /// creates a record.  Returns `nil` when the source is not a valid PDF.
    @discardableResult
    func importPDF(from sourceURL: URL) -> PDFNoteRecord? {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: sourceURL) else { return nil }

        let filename = UUID().uuidString + ".pdf"
        let destURL = pdfDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            return nil
        }

        let rawTitle = sourceURL.deletingPathExtension().lastPathComponent
        let title = rawTitle.isEmpty ? "Imported PDF" : rawTitle
        let record = PDFNoteRecord(
            title: title,
            pdfFilename: filename,
            pageCount: document.pageCount
        )
        records.insert(record, at: 0)
        save()
        return record
    }

    // MARK: - Delete

    /// Removes the record and its stored PDF file from disk.
    func deleteRecord(id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: pdfURL(for: record))
        records.removeAll { $0.id == id }
        save()
    }

    // MARK: - Annotation CRUD

    /// Stores or updates the PencilKit annotation for `page`.
    func updateAnnotation(id: UUID, page: Int, data: Data) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].annotationData[String(page)] = data
        records[idx].modifiedAt = Date()
        save()
    }

    /// Stores or updates the sticker layer for `page`.
    func updateStickers(id: UUID, page: Int, data: Data) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].stickerData[String(page)] = data
        records[idx].modifiedAt = Date()
        save()
    }

    /// Stores or updates the widget layer for `page`.
    func updateWidgets(id: UUID, page: Int, data: Data) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].widgetData[String(page)] = data
        records[idx].modifiedAt = Date()
        save()
    }

    /// Persists the last-viewed page without updating `modifiedAt`.
    func updateCurrentPage(id: UUID, page: Int) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].currentPage = page
        save()
    }

    // MARK: - Sticker / Widget helpers

    /// Decodes the sticker instances for a given page.
    func stickers(for recordID: UUID, page: Int) -> [StickerInstance] {
        guard let record = records.first(where: { $0.id == recordID }),
              let data = record.stickerData[String(page)],
              let decoded = try? JSONDecoder().decode([StickerInstance].self, from: data)
        else { return [] }
        return decoded
    }

    /// Decodes the widget instances for a given page.
    func widgets(for recordID: UUID, page: Int) -> [NoteWidget] {
        guard let record = records.first(where: { $0.id == recordID }),
              let data = record.widgetData[String(page)],
              let decoded = try? JSONDecoder().decode([NoteWidget].self, from: data)
        else { return [] }
        return decoded
    }

    /// Encodes and persists sticker instances for a given page.
    func saveStickers(_ stickers: [StickerInstance], recordID: UUID, page: Int) {
        guard let data = try? JSONEncoder().encode(stickers) else { return }
        updateStickers(id: recordID, page: page, data: data)
    }

    /// Encodes and persists widget instances for a given page.
    func saveWidgets(_ widgets: [NoteWidget], recordID: UUID, page: Int) {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        updateWidgets(id: recordID, page: page, data: data)
    }

    // MARK: - URL helpers

    /// Absolute URL of the stored PDF file for a record.
    func pdfURL(for record: PDFNoteRecord) -> URL {
        pdfDirectory.appendingPathComponent(record.pdfFilename)
    }

    // MARK: - Export

    /// Composites each PDF page with its annotation, sticker, and widget
    /// overlays and writes the result to a temporary file.
    func exportAnnotatedPDF(for record: PDFNoteRecord) -> URL? {
        let srcURL = pdfURL(for: record)
        guard let document = PDFDocument(url: srcURL) else { return nil }

        let newDoc = PDFDocument()
        for pageIndex in 0 ..< document.pageCount {
            guard let sourcePage = document.page(at: pageIndex) else { continue }
            let mediaBox = sourcePage.bounds(for: .mediaBox)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 2.0
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: mediaBox.size, format: format)

            let composited = renderer.image { ctx in
                let cgCtx = ctx.cgContext

                // White background.
                cgCtx.setFillColor(UIColor.white.cgColor)
                cgCtx.fill(CGRect(origin: .zero, size: mediaBox.size))

                // Draw the PDF page. PDF origin is bottom-left; flip for UIKit.
                cgCtx.saveGState()
                cgCtx.translateBy(x: 0, y: mediaBox.height)
                cgCtx.scaleBy(x: 1, y: -1)
                sourcePage.draw(with: .mediaBox, to: cgCtx)
                cgCtx.restoreGState()

                // Overlay the PencilKit annotation, if any.
                if let drawingData = record.annotationData[String(pageIndex)],
                   let drawing = try? PKDrawing(data: drawingData) {
                    let image = drawing.image(
                        from: CGRect(origin: .zero, size: mediaBox.size),
                        scale: 1.0
                    )
                    image.draw(in: CGRect(origin: .zero, size: mediaBox.size))
                }

                // Overlay stickers.
                if let stickerData = record.stickerData[String(pageIndex)],
                   let stickers = try? JSONDecoder().decode(
                       [StickerInstance].self, from: stickerData
                   ) {
                    for sticker in stickers.sorted(by: { $0.zIndex < $1.zIndex }) {
                        renderStickerForExport(sticker, in: mediaBox.size, context: cgCtx)
                    }
                }

                // Overlay widgets.
                if let wData = record.widgetData[String(pageIndex)],
                   let noteWidgets = try? JSONDecoder().decode(
                       [NoteWidget].self, from: wData
                   ) {
                    for widget in noteWidgets.sorted(by: { $0.zIndex < $1.zIndex }) {
                        renderWidgetForExport(widget, context: cgCtx)
                    }
                }
            }

            if let newPage = PDFPage(image: composited) {
                newDoc.insert(newPage, at: newDoc.pageCount)
            }
        }

        let safeName = record.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-annotated.pdf")
        guard newDoc.write(to: tempURL) else { return nil }
        return tempURL
    }

    // MARK: - Export helpers

    private func renderStickerForExport(
        _ sticker: StickerInstance,
        in pageSize: CGSize,
        context: CGContext
    ) {
        // Draw a placeholder rectangle for each sticker in the export
        // (actual sticker images require StickerStore which is not
        // available at this layer — a future enhancement).
        let size: CGFloat = StickerConstants.defaultNaturalSize.width * sticker.scale
        let rect = CGRect(
            x: sticker.position.x - size / 2,
            y: sticker.position.y - size / 2,
            width: size,
            height: size
        )
        context.saveGState()
        context.setAlpha(sticker.opacity)
        context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.3).cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    private func renderWidgetForExport(
        _ widget: NoteWidget,
        context: CGContext
    ) {
        let rect = widget.frame.boundingRect
        context.saveGState()
        context.setFillColor(UIColor.secondarySystemBackground.cgColor)
        context.fill(rect)
        context.setStrokeColor(UIColor.separator.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
        context.restoreGState()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let loaded = try? JSONDecoder().decode([PDFNoteRecord].self, from: data)
        else { return }
        records = loaded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}
