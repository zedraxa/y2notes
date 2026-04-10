import Foundation
import UniformTypeIdentifiers

// MARK: - Sort order

/// The order in which imported documents are displayed in the library.
enum DocumentSortOrder: String, CaseIterable, Identifiable {
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"
    case dateImported = "date_imported"
    case lastOpened = "last_opened"
    case type = "type"
    case sizeDescending = "size_desc"
    case favoritesFirst = "favorites_first"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nameAscending:  return "Name (A–Z)"
        case .nameDescending: return "Name (Z–A)"
        case .dateImported:   return "Date Imported"
        case .lastOpened:     return "Last Opened"
        case .type:           return "File Type"
        case .sizeDescending: return "Largest First"
        case .favoritesFirst: return "Favorites First"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAscending:  return "a.circle"
        case .nameDescending: return "z.circle"
        case .dateImported:   return "clock"
        case .lastOpened:     return "eye"
        case .type:           return "doc"
        case .sizeDescending: return "arrow.down.circle"
        case .favoritesFirst: return "star"
        }
    }
}

// MARK: - Supported document types

/// The types of external documents that Y2Notes can import.
enum ImportedDocumentType: String, Codable, CaseIterable {
    case pdf
    case png
    case jpg
    case heic
    case docx
    case epub
    case pptx
    case key
    case odp

    var displayName: String {
        switch self {
        case .pdf:  return "PDF Document"
        case .png:  return "PNG Image"
        case .jpg:  return "JPEG Image"
        case .heic: return "HEIC Image"
        case .docx: return "Word Document"
        case .epub: return "ePub Book"
        case .pptx: return "PowerPoint"
        case .key:  return "Keynote"
        case .odp:  return "Presentation"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf:  return "doc.fill"
        case .png:  return "photo"
        case .jpg:  return "photo"
        case .heic: return "photo"
        case .docx: return "doc.text.fill"
        case .epub: return "book.fill"
        case .pptx: return "rectangle.on.rectangle"
        case .key:  return "rectangle.on.rectangle.fill"
        case .odp:  return "rectangle.on.rectangle"
        }
    }

    /// UTType identifiers recognised for file import.
    var utTypes: [UTType] {
        switch self {
        case .pdf:  return [.pdf]
        case .png:  return [.png]
        case .jpg:  return [.jpeg]
        case .heic: return [.heic]
        case .docx:
            return [
                UTType(filenameExtension: "docx") ?? .item,
                UTType("com.microsoft.word.docx") ?? .item,
            ]
        case .epub:
            return [
                UTType(filenameExtension: "epub") ?? .item,
                UTType("org.idpf.epub-container") ?? .item,
            ]
        case .pptx:
            return [
                UTType(filenameExtension: "pptx") ?? .item,
                UTType("com.microsoft.powerpoint.pptx") ?? .item,
            ]
        case .key:
            return [
                UTType(filenameExtension: "key") ?? .item,
                UTType("com.apple.iwork.keynote.key") ?? .item,
            ]
        case .odp:
            return [UTType(filenameExtension: "odp") ?? .item]
        }
    }

    /// All UTTypes supported across all document kinds — used by the file importer.
    static var allUTTypes: [UTType] {
        allCases.flatMap(\.utTypes)
    }
}

// MARK: - ImportedDocument model

/// A persistent record of a document imported into Y2Notes.
///
/// The original file is copied into the app's `Documents/ImportedDocs/` sandbox
/// directory so it remains accessible even after the source is removed.
struct ImportedDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var importedAt: Date
    var documentType: ImportedDocumentType
    /// File name (not full path) of the stored copy inside `ImportedDocs/`.
    var storedFileName: String
    /// File size in bytes captured at import time. 0 when unknown.
    var fileSize: Int64
    /// Timestamp of the most recent time the document was opened for viewing.
    var lastOpenedAt: Date?
    /// Whether the user has starred this document as a favourite.
    var isFavorited: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        documentType: ImportedDocumentType,
        storedFileName: String,
        importedAt: Date = Date(),
        fileSize: Int64 = 0,
        lastOpenedAt: Date? = nil,
        isFavorited: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.documentType = documentType
        self.storedFileName = storedFileName
        self.importedAt = importedAt
        self.fileSize = fileSize
        self.lastOpenedAt = lastOpenedAt
        self.isFavorited = isFavorited
    }

    // MARK: - Codable — tolerant decoder for legacy records

    enum CodingKeys: String, CodingKey {
        case id, displayName, importedAt, documentType, storedFileName
        case fileSize, lastOpenedAt, isFavorited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        documentType = try container.decode(ImportedDocumentType.self, forKey: .documentType)
        storedFileName = try container.decode(String.self, forKey: .storedFileName)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        isFavorited = try container.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
    }

    // MARK: - Formatted helpers

    /// A human-readable file size string (e.g. "2.4 MB").
    var formattedFileSize: String {
        guard fileSize > 0 else { return "–" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    // MARK: Hashable — identity only
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
