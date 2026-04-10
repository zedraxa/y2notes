import SwiftUI
import QuickLook

// MARK: - DocumentViewerView

/// Full-screen viewer for imported DOCX, EPUB, PPTX, KEY, and ODP files.
///
/// Uses `QLPreviewController` (Quick Look) — the same engine Apple uses in
/// the Files app — so every supported format renders with native fidelity.
struct DocumentViewerView: View {

    @EnvironmentObject var documentStore: DocumentStore
    @EnvironmentObject var noteStore: NoteStore

    let document: ImportedDocument
    let fileURL: URL

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

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
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
/// - Context menu with rename, favourite toggle, share, and delete
/// - Batch multi-file import
struct DocumentLibraryView: View {

    @EnvironmentObject var documentStore: DocumentStore
    @EnvironmentObject var noteStore: NoteStore

    @Binding var selectedDocumentID: UUID?

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
        let query = searchQuery.lowercased()
        return sorted.filter { $0.displayName.lowercased().contains(query) }
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
                    importError = "Unable to import \"\(names)\". " +
                        "The file format may not be supported."
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200))],
                spacing: 16
            ) {
                ForEach(displayedDocuments) { doc in
                    DocumentGridCell(
                        document: doc,
                        isSelected: doc.id == selectedDocumentID,
                        hasCompanionNote: noteStore.hasCompanionNote(forDocument: doc.id)
                    ) {
                        selectedDocumentID = doc.id
                    }
                    .contextMenu { contextMenu(for: doc) }
                }
            }
            .padding()
        }
    }

    // MARK: - List

    private var documentList: some View {
        List {
            ForEach(displayedDocuments) { doc in
                DocumentListRow(
                    document: doc,
                    isSelected: doc.id == selectedDocumentID
                ) {
                    selectedDocumentID = doc.id
                }
                .contextMenu { contextMenu(for: doc) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        documentStore.delete(doc)
                        if selectedDocumentID == doc.id { selectedDocumentID = nil }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        documentStore.toggleFavorite(doc)
                    } label: {
                        Label(
                            doc.isFavorited ? "Unfavorite" : "Favorite",
                            systemImage: doc.isFavorited ? "star.slash" : "star.fill"
                        )
                    }
                    .tint(.yellow)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Toolbar items

    private var sortMenu: some View {
        Menu {
            ForEach(DocumentSortOrder.allCases) { order in
                Button {
                    sortOrder = order
                } label: {
                    Label(order.displayName, systemImage: order.systemImage)
                    if sortOrder == order { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort documents")
    }

    private var layoutToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isGridLayout.toggle() }
        } label: {
            Image(systemName: isGridLayout ? "list.bullet" : "square.grid.2x2")
        }
        .accessibilityLabel(isGridLayout ? "Switch to list view" : "Switch to grid view")
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Import document")
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for doc: ImportedDocument) -> some View {
        Button {
            documentStore.toggleFavorite(doc)
        } label: {
            Label(
                doc.isFavorited ? "Remove Favorite" : "Add to Favorites",
                systemImage: doc.isFavorited ? "star.slash" : "star"
            )
        }

        Button {
            renameText = doc.displayName
            documentToRename = doc
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        if noteStore.hasCompanionNote(forDocument: doc.id),
           let existing = noteStore.notes(forDocument: doc.id).first {
            Button {
                onOpenCompanionNote?(existing.id)
            } label: {
                Label("Open Companion Note", systemImage: "note.text")
            }
        } else {
            Button {
                let note = noteStore.addNote(
                    forDocument: doc.id,
                    title: "\(doc.displayName) — Notes"
                )
                onOpenCompanionNote?(note.id)
            } label: {
                Label("Create Companion Note", systemImage: "note.text.badge.plus")
            }
        }

        Button {
            shareItems = [documentStore.storedURL(for: doc)]
            showShareSheet = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            documentStore.delete(doc)
            if selectedDocumentID == doc.id { selectedDocumentID = nil }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .scaleEffect(emptyAppeared ? 1.0 : 0.5)
                .opacity(emptyAppeared ? 1 : 0)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.7).delay(0.05),
                    value: emptyAppeared
                )
            Text("No Documents")
                .font(.title3.weight(.semibold))
                .opacity(emptyAppeared ? 1 : 0)
                .offset(y: emptyAppeared ? 0 : 10)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: emptyAppeared)
            Text("Import PDFs, images, Word files, ePubs,\nor presentations to view and annotate them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(emptyAppeared ? 1 : 0)
                .offset(y: emptyAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.35).delay(0.25), value: emptyAppeared)
            Button {
                showImporter = true
            } label: {
                Label("Import Document", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .scaleEffect(emptyAppeared ? 1.0 : 0.85)
            .opacity(emptyAppeared ? 1 : 0)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.75).delay(0.35),
                value: emptyAppeared
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { emptyAppeared = true }
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Results")
                .font(.title3.weight(.semibold))
            Text("No documents match \"\(searchQuery)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DocumentGridCell

private struct DocumentGridCell: View {
    let document: ImportedDocument
    let isSelected: Bool
    var hasCompanionNote: Bool = false
    let onTap: () -> Void

    private static let companionBadgeColor = Color(uiColor: UIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1.0))

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: document.documentType.systemImage)
                        .font(.system(size: 38))
                        .foregroundStyle(isSelected ? .white : .accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected
                                      ? Color.accentColor
                                      : Color(uiColor: .secondarySystemBackground))
                        )

                    VStack(spacing: 2) {
                        if document.isFavorited {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .padding(4)
                        }
                        if hasCompanionNote {
                            Image(systemName: "note.text")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(
                                    Circle().fill(Self.companionBadgeColor.opacity(0.9))
                                )
                        }
                    }
                    .padding(2)
                }

                Text(document.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Text(document.documentType.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if document.fileSize > 0 {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(document.formattedFileSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(document.displayName), \(document.documentType.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - DocumentListRow

private struct DocumentListRow: View {
    let document: ImportedDocument
    let isSelected: Bool
    let onTap: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: document.documentType.systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(document.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if document.isFavorited {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(document.documentType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if document.fileSize > 0 {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(document.formattedFileSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Self.dateFormatter.string(from: document.importedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(document.displayName), \(document.documentType.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
