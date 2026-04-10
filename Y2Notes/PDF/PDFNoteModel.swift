import Foundation

// MARK: - PDFNoteRecord

/// Persistent record for an imported PDF document.
/// Stores a reference to the copied PDF file, per-page PencilKit annotation
/// data, and per-page sticker / widget overlay data.
struct PDFNoteRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    /// Basename of the stored PDF copy inside `Documents/PDFNotes/` (e.g. `"abc-123.pdf"`).
    var pdfFilename: String
    /// Total page count captured at import time.
    var pageCount: Int
    /// PencilKit drawing data keyed by page index expressed as a decimal string
    /// (e.g. `"0"`, `"1"`, …).  Pages with no annotation are absent from this dict.
    var annotationData: [String: Data]
    /// Serialised `[StickerInstance]` arrays keyed by page index string.
    var stickerData: [String: Data]
    /// Serialised `[NoteWidget]` arrays keyed by page index string.
    var widgetData: [String: Data]
    /// Last-viewed page index (0-based).
    var currentPage: Int
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        pdfFilename: String,
        pageCount: Int
    ) {
        self.id = id
        self.title = title
        self.pdfFilename = pdfFilename
        self.pageCount = pageCount
        self.annotationData = [:]
        self.stickerData = [:]
        self.widgetData = [:]
        self.currentPage = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: Codable — tolerant decoder for future field additions

    enum CodingKeys: String, CodingKey {
        case id, title, pdfFilename, pageCount
        case annotationData, stickerData, widgetData
        case currentPage, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        pdfFilename = try container.decode(String.self, forKey: .pdfFilename)
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        annotationData = try container.decodeIfPresent([String: Data].self, forKey: .annotationData) ?? [:]
        stickerData = try container.decodeIfPresent([String: Data].self, forKey: .stickerData) ?? [:]
        widgetData = try container.decodeIfPresent([String: Data].self, forKey: .widgetData) ?? [:]
        currentPage = try container.decodeIfPresent(Int.self, forKey: .currentPage) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }

    // MARK: Hashable — identity only

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
