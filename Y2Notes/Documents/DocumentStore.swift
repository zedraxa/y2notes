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
    }

    // MARK: - Public API

    /// Detects the document type from a file URL's extension.
    func documentType(for url: URL) -> ImportedDocumentType? {
        let ext = url.pathExtension.lowercased()
        return ImportedDocumentType.allCases.first { $0.rawValue == ext }
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

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        let record = ImportedDocument(
            displayName:    displayName,
            documentType:   docType,
            storedFileName: fileName
        )
        documents.append(record)
        save()
        return record
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
}
