import Foundation
import UniformTypeIdentifiers

// MARK: - Supported document types

/// The types of external documents that Y2Notes can import for annotation.
enum ImportedDocumentType: String, Codable, CaseIterable {
    case pdf   = "pdf"
    case png   = "png"
    case jpg   = "jpg"
    case heic  = "heic"
    case docx  = "docx"
    case epub  = "epub"
    case pptx  = "pptx"
    case key   = "key"
    case odp   = "odp"

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
        case .pdf:
            return [.pdf]
        case .png:
            return [.png]
        case .jpg:
            return [.jpeg]
        case .heic:
            return [.heic]
        case .docx:
            return [UTType(filenameExtension: "docx") ?? .item,
                    UTType("com.microsoft.word.docx") ?? .item]
        case .epub:
            return [UTType(filenameExtension: "epub") ?? .item,
                    UTType("org.idpf.epub-container") ?? .item]
        case .pptx:
            return [UTType(filenameExtension: "pptx") ?? .item,
                    UTType("com.microsoft.powerpoint.pptx") ?? .item]
        case .key:
            return [UTType(filenameExtension: "key") ?? .item,
                    UTType("com.apple.iwork.keynote.key") ?? .item]
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

/// A persistent record of a document imported into Y2Notes for annotation.
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

    init(
        id: UUID = UUID(),
        displayName: String,
        documentType: ImportedDocumentType,
        storedFileName: String,
        importedAt: Date = Date()
    ) {
        self.id             = id
        self.displayName    = displayName
        self.documentType   = documentType
        self.storedFileName = storedFileName
        self.importedAt     = importedAt
    }

    // MARK: Hashable — identity only
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ImportedDocument, rhs: ImportedDocument) -> Bool { lhs.id == rhs.id }
}
