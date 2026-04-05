import Foundation
import Combine

/// Persistence and import manager for DOCX, EPUB, PPTX, KEY, and ODP documents.
///
/// **Storage layout**
/// ```
/// Documents/
///   ImportedDocs/
///     <uuid>.<ext>         ← original file copy
///   imported_documents.json ← metadata index
/// ```
///
/// Files are copied into the sandbox at import time so they remain accessible
/// after the source URL's security scope expires or the source is deleted.
final class DocumentStore: ObservableObject {

    // MARK: - Published state

    @Published private(set) var documents: [ImportedDocument] = []

    // MARK: - Private storage

    private let docsDir: URL
    private let indexURL: URL

    // MARK: - Init

    init() {
        let appDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        docsDir  = appDocs.appendingPathComponent("ImportedDocs", isDirectory: true)
        indexURL = appDocs.appendingPathComponent("imported_documents.json")
        try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        load()
        cleanupOrphans()
    }

    // MARK: - Public API

    /// Detects the document type from a file URL's extension.
    func documentType(for url: URL) -> ImportedDocumentType? {
        let ext = url.pathExtension.lowercased()
        // Handle common extension aliases (e.g., .jpeg → .jpg)
        switch ext {
        case "jpeg": return .jpg
        case "pdf":  return .pdf
        default:     return ImportedDocumentType.allCases.first { $0.rawValue == ext }
        }
    }

    /// Imports a document from the given security-scoped URL.
    ///
    /// - Parameter sourceURL: A security-scoped URL obtained from a `UIDocumentPickerViewController`
    ///   or SwiftUI `.fileImporter`. The store copies the file before the security scope expires.
    /// - Returns: The newly created `ImportedDocument`, or `nil` on failure.
    @discardableResult
    func importDocument(from sourceURL: URL) -> ImportedDocument? {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let docType = documentType(for: sourceURL) else { return nil }
        let fileName      = "\(UUID().uuidString).\(docType.rawValue)"
        let destination   = docsDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            return nil
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        let record = ImportedDocument(
            displayName:    displayName,
            documentType:   docType,
            storedFileName: fileName,
            fileSize:       size
        )
        documents.insert(record, at: 0)
        save()
        return record
    }

    /// Imports multiple documents from an array of security-scoped URLs.
    ///
    /// - Returns: The successfully imported documents (failed imports are silently skipped).
    @discardableResult
    func importDocuments(from urls: [URL]) -> [ImportedDocument] {
        var imported: [ImportedDocument] = []
        for url in urls {
            if let doc = importDocument(from: url) {
                imported.append(doc)
            }
        }
        return imported
    }

    /// Renames the display name of an imported document.
    func rename(_ document: ImportedDocument, displayName: String) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let idx = documents.firstIndex(of: document) else { return }
        documents[idx].displayName = name
        save()
    }

    /// Toggles the favourited state of a document.
    func toggleFavorite(_ document: ImportedDocument) {
        guard let idx = documents.firstIndex(of: document) else { return }
        documents[idx].isFavorited.toggle()
        save()
    }

    /// Records that the document was just opened for viewing.
    func updateLastOpened(_ document: ImportedDocument) {
        guard let idx = documents.firstIndex(of: document) else { return }
        documents[idx].lastOpenedAt = Date()
        save()
    }

    /// Deletes a document and removes the stored file copy.
    func delete(_ document: ImportedDocument) {
        let fileURL = storedURL(for: document)
        try? FileManager.default.removeItem(at: fileURL)
        documents.removeAll { $0.id == document.id }
        save()
    }

    /// Resolves the full file URL for a stored document.
    func storedURL(for document: ImportedDocument) -> URL {
        docsDir.appendingPathComponent(document.storedFileName)
    }

    /// Returns the documents sorted by the given order.
    func sorted(by order: DocumentSortOrder) -> [ImportedDocument] {
        switch order {
        case .nameAscending:
            return documents.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameDescending:
            return documents.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .dateImported:
            return documents.sorted { $0.importedAt > $1.importedAt }
        case .lastOpened:
            return documents.sorted {
                let a = $0.lastOpenedAt ?? $0.importedAt
                let b = $1.lastOpenedAt ?? $1.importedAt
                return a > b
            }
        case .type:
            return documents.sorted { $0.documentType.rawValue < $1.documentType.rawValue }
        case .sizeDescending:
            return documents.sorted { $0.fileSize > $1.fileSize }
        case .favoritesFirst:
            return documents.sorted {
                if $0.isFavorited != $1.isFavorited { return $0.isFavorited }
                return $0.importedAt > $1.importedAt
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ImportedDocument].self, from: data) else {
            return
        }
        documents = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Orphan cleanup

    /// Removes stored files that have no matching record and drops records whose
    /// stored file is missing.  Called once on init to keep the sandbox tidy.
    private func cleanupOrphans() {
        let fm = FileManager.default

        // 1. Remove records whose backing file is gone.
        let missing = documents.filter { !fm.fileExists(atPath: storedURL(for: $0).path) }
        if !missing.isEmpty {
            let missingIDs = Set(missing.map(\.id))
            documents.removeAll { missingIDs.contains($0.id) }
            save()
        }

        // 2. Delete stored files that have no record.
        guard let storedFiles = try? fm.contentsOfDirectory(atPath: docsDir.path) else { return }
        let knownFileNames = Set(documents.map(\.storedFileName))
        for file in storedFiles where !knownFileNames.contains(file) {
            try? fm.removeItem(at: docsDir.appendingPathComponent(file))
        }
    }
}
