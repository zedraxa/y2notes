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

    @EnvironmentObject var noteStore: NoteStore
    @Environment(TabWorkspaceStore.self) private var workspace

    let document: ImportedDocument
    let fileURL: URL

    var body: some View {
        QLPreviewRepresentable(url: fileURL)
            .ignoresSafeArea()
            .navigationTitle(document.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if let existing = noteStore.notes(forDocument: document.id).first {
                            workspace.openTab(
                                .note(id: existing.id),
                                displayName: existing.title,
                                accentColor: [0.3, 0.5, 0.7]
                            )
                        } else {
                            let note = noteStore.addNote(forDocument: document)
                            workspace.openTab(
                                .note(id: note.id),
                                displayName: note.title,
                                accentColor: [0.3, 0.5, 0.7]
                            )
                        }
                    } label: {
                        Image(systemName: noteStore.hasCompanionNote(forDocument: document.id)
                              ? "note.text" : "note.text.badge.plus")
                    }
                    .accessibilityLabel(noteStore.hasCompanionNote(forDocument: document.id)
                                        ? "Open companion note" : "Create companion note")
                }
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

/// Grid view listing all imported documents with an import button.
struct DocumentLibraryView: View {

    @EnvironmentObject var documentStore: DocumentStore
    @EnvironmentObject var noteStore: NoteStore
    @Environment(TabWorkspaceStore.self) private var tabSession

    @Binding var selectedDocumentID: UUID?
    @State private var showImporter = false
    @State private var importError: String?

    private var selectedDocument: ImportedDocument? {
        guard let id = selectedDocumentID else { return nil }
        return documentStore.documents.first { $0.id == id }
    }

    var body: some View {
        Group {
            if documentStore.documents.isEmpty {
                emptyState
            } else {
                documentGrid
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Import document")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: ImportedDocumentType.allUTTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if let doc = documentStore.importDocument(from: url) {
                        selectedDocumentID = doc.id
                        let note = noteStore.addNote(forDocument: doc)
                        tabSession.openTab(
                            .note(id: note.id),
                            displayName: note.title,
                            accentColor: [0.3, 0.5, 0.7]
                        )
                    } else {
                        importError = "Unable to import \"\(url.lastPathComponent)\". The file format may not be supported."
                    }
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
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No Documents")
                .font(.title3.weight(.semibold))
            Text("Import PDFs, images, Word files, ePubs,\nor presentations to view and annotate them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showImporter = true
            } label: {
                Label("Import Document", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200))], spacing: 16) {
                ForEach(documentStore.documents) { doc in
                    DocumentCell(
                        document: doc,
                        isSelected: doc.id == selectedDocumentID,
                        hasCompanionNote: noteStore.hasCompanionNote(forDocument: doc.id)
                    ) {
                        selectedDocumentID = doc.id
                    }
                    .contextMenu {
                        if let linkedNote = noteStore.notes(forDocument: doc.id).first {
                            Button {
                                tabSession.openTab(
                                    .note(id: linkedNote.id),
                                    displayName: linkedNote.title,
                                    accentColor: [0.3, 0.5, 0.7]
                                )
                            } label: {
                                Label("Open Companion Note", systemImage: "note.text")
                            }
                        } else {
                            Button {
                                let note = noteStore.addNote(forDocument: doc)
                                tabSession.openTab(
                                    .note(id: note.id),
                                    displayName: note.title,
                                    accentColor: [0.3, 0.5, 0.7]
                                )
                            } label: {
                                Label("Create Companion Note", systemImage: "note.text.badge.plus")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            documentStore.delete(doc)
                            if selectedDocumentID == doc.id { selectedDocumentID = nil }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - DocumentCell

private struct DocumentCell: View {
    let document: ImportedDocument
    let isSelected: Bool
    var hasCompanionNote: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    Image(systemName: document.documentType.systemImage)
                        .font(.system(size: 40))
                        .foregroundStyle(isSelected ? .white : .accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                        )

                    Text(document.displayName)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(document.documentType.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if hasCompanionNote {
                    Image(systemName: "note.text")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color(red: 0.3, green: 0.5, blue: 0.7).opacity(0.9)))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(document.displayName), \(document.documentType.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
