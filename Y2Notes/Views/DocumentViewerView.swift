import SwiftUI
import QuickLook

// MARK: - DocumentViewerView

/// Full-screen viewer for imported DOCX, EPUB, PPTX, KEY, and ODP files.
///
/// Uses `QLPreviewController` (Quick Look) — the same engine Apple uses in Files app —
/// so every supported format renders with native fidelity without any third-party library.
///
/// Quick Look supports:
/// - Word (.docx), Excel (.xlsx), PowerPoint (.pptx)
/// - ePub books
/// - Keynote (.key), Numbers (.numbers), Pages (.pages)
/// - Images, PDFs, plain text, and many more
struct DocumentViewerView: View {

    @EnvironmentObject var documentStore: DocumentStore
    @EnvironmentObject var noteStore: NoteStore

    let document: ImportedDocument
    let fileURL: URL

    /// Callback invoked with the companion note's ID so the parent can open it in a tab.
    var onOpenCompanionNote: ((UUID) -> Void)?

    @State private var showShareSheet = false

    private var companionNote: Note? {
        noteStore.notes(forDocument: document.id).first
    }

    var body: some View {
        QLPreviewRepresentable(url: fileURL)
            .ignoresSafeArea()
            .navigationTitle(document.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    companionNoteButton
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share \(document.displayName)")
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [fileURL])
                    .ignoresSafeArea()
            }
            .onAppear {
                documentStore.updateLastOpened(document)
            }
    }

    // MARK: - Companion note button

    @ViewBuilder
    private var companionNoteButton: some View {
        if let existing = companionNote {
            Button {
                onOpenCompanionNote?(existing.id)
            } label: {
                Label("Open Companion Note", systemImage: "note.text")
            }
            .accessibilityLabel("Open companion note")
        } else {
            Button {
                let note = noteStore.addNote(
                    forDocument: document.id,
                    title: "\(document.displayName) — Notes"
                )
                onOpenCompanionNote?(note.id)
            } label: {
                Label("Create Companion Note", systemImage: "note.text.badge.plus")
            }
            .accessibilityLabel("Create companion note")
        }
    }
}

// MARK: - QLPreviewRepresentable

/// UIViewControllerRepresentable wrapper around `QLPreviewController`.
private struct QLPreviewRepresentable: UIViewControllerRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.reloadData()
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            uiViewController.reloadData()
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - DocumentLibraryView

/// Full-featured library listing all imported documents.
///
/// Provides:
/// - Sort picker (name / date / last opened / type / size / favorites)
/// - Live search bar that filters by display name
/// - Grid / list display toggle
/// - Richer cells showing file type, size, import date, and favourite star
/// - Context menu with rename, favourite toggle, share, and delete
/// - Batch multi-file import
struct DocumentLibraryView: View {

    @EnvironmentObject var documentStore: DocumentStore
    @EnvironmentObject var noteStore: NoteStore

    @Binding var selectedDocumentID: UUID?

    /// Callback invoked with a companion note's ID so the parent can open it in a tab.
    var onOpenCompanionNote: ((UUID) -> Void)?

    @State private var showImporter = false
    @State private var importError: String?
    @State private var docsAppeared = false
    @State private var emptyAppeared = false
    @State private var sortOrder: DocumentSortOrder = .dateImported
    @State private var searchQuery = ""
    @State private var isGridLayout = true
    @State private var documentToRename: ImportedDocument?
    @State private var renameText = ""
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    // MARK: - Filtered + sorted list

    private var displayedDocuments: [ImportedDocument] {
        let sorted = documentStore.sorted(by: sortOrder)
        guard !searchQuery.isEmpty else { return sorted }
        let q = searchQuery.lowercased()
        return sorted.filter { $0.displayName.lowercased().contains(q) }
    }

    private var selectedDocument: ImportedDocument? {
        guard let id = selectedDocumentID else { return nil }
        return documentStore.documents.first { $0.id == id }
    }

    var body: some View {
        Group {
            if documentStore.documents.isEmpty {
                emptyState
            } else {
                contentView
            }
        }
        .navigationTitle("Documents")
        .searchable(text: $searchQuery, prompt: "Search documents")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                sortMenu
                layoutToggleButton
                importButton
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: ImportedDocumentType.allUTTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let imported = documentStore.importDocuments(from: urls)
                if imported.isEmpty {
                    let names = urls.map(\.lastPathComponent).joined(separator: ", ")
                    importError = "Unable to import \"\(names)\". The file format may not be supported."
                } else {
                    selectedDocumentID = imported.first?.id
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Rename Document", isPresented: Binding(
            get: { documentToRename != nil },
            set: { if !$0 { documentToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
                .submitLabel(.done)
            Button("Rename") {
                if let doc = documentToRename {
                    documentStore.rename(doc, displayName: renameText)
                }
                documentToRename = nil
            }
            Button("Cancel", role: .cancel) { documentToRename = nil }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
                .ignoresSafeArea()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if displayedDocuments.isEmpty {
            noResultsState
        } else if isGridLayout {
            documentGrid
        } else {
            documentList
        }
    }

    // MARK: - Grid

    private var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200))], spacing: 16) {
                ForEach(displayedDocuments) { doc in
                    DocumentGridCell(
                        document: doc,
                        isSelected: doc.id == selectedDocumentID,
