import Foundation
import PDFKit
import PencilKit
import UIKit

// MARK: - PDFStore

/// Manages the collection of imported PDF documents, their on-disk copies,
/// per-page annotation data, and annotated-PDF export.
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

    // MARK: - CRUD

    /// Copies the PDF at `sourceURL` into the app's PDFNotes directory, creates a record,
    /// and returns it.  Returns `nil` when the source is not a valid PDF.
    @discardableResult
    func importPDF(from sourceURL: URL) -> PDFNoteRecord? {
        // Security-scoped access (file picker results need this).
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

    /// Removes the record and its stored PDF file from disk.
    func deleteRecord(id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: pdfURL(for: record))
        records.removeAll { $0.id == id }
        save()
    }

    /// Stores or updates the PencilKit annotation for `page` in the given record.
    func updateAnnotation(id: UUID, page: Int, data: Data) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].annotationData[String(page)] = data
        records[idx].modifiedAt = Date()
        save()
    }

    /// Persists the last-viewed page without updating `modifiedAt`.
    func updateCurrentPage(id: UUID, page: Int) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].currentPage = page
        save()
    }

    // MARK: - URL helpers

    /// Absolute URL of the stored PDF file for a record.
    func pdfURL(for record: PDFNoteRecord) -> URL {
        pdfDirectory.appendingPathComponent(record.pdfFilename)
    }

    // MARK: - Export

    /// Composites each PDF page with its annotation drawing and writes the result to a
    /// temporary file.  Returns the temporary file URL, or `nil` on failure.
    ///
    /// **Coordinate note:** Annotations are rendered at the PDF page's native media-box
    /// size.  If the user annotated at a zoom level other than the default fit-to-width
    /// zoom, strokes will appear proportionally scaled on export.  A future improvement
    /// could record the view transform at annotation time and apply the inverse on export.
    func exportAnnotatedPDF(for record: PDFNoteRecord) -> URL? {
        let srcURL = pdfURL(for: record)
        guard let document = PDFDocument(url: srcURL) else { return nil }

        let newDoc = PDFDocument()
        for pageIndex in 0 ..< document.pageCount {
            guard let sourcePage = document.page(at: pageIndex) else { continue }
            let mediaBox = sourcePage.bounds(for: .mediaBox)

            // Use 2× scale for print-quality output.
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2.0
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: mediaBox.size, format: format)

            let composited = renderer.image { ctx in
                let cgCtx = ctx.cgContext

                // White background.
                cgCtx.setFillColor(UIColor.white.cgColor)
                cgCtx.fill(CGRect(origin: .zero, size: mediaBox.size))

                // Draw the PDF page.  PDF origin is bottom-left; flip for UIKit.
                cgCtx.saveGState()
                cgCtx.translateBy(x: 0, y: mediaBox.height)
                cgCtx.scaleBy(x: 1, y: -1)
                sourcePage.draw(with: .mediaBox, to: cgCtx)
                cgCtx.restoreGState()

                // Overlay the PencilKit annotation, if any.
                if let drawingData = record.annotationData[String(pageIndex)],
                   let drawing = try? PKDrawing(data: drawingData) {
                    let annotationImage = drawing.image(
                        from: CGRect(origin: .zero, size: mediaBox.size),
                        scale: 1.0
                    )
                    annotationImage.draw(in: CGRect(origin: .zero, size: mediaBox.size))
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

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let loaded = try? JSONDecoder().decode([PDFNoteRecord].self, from: data)
        else { return }
        records = loaded
    }

    /// Reloads PDF records from disk.  Called after an iCloud sync overwrites the metadata file.
    func reloadFromDisk() {
        load()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}
