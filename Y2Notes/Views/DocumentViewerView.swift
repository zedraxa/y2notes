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

    let document: ImportedDocument
    let fileURL: URL

    var body: some View {
        QLPreviewRepresentable(url: fileURL)
            .ignoresSafeArea()
            .navigationTitle(document.displayName)
            .navigationBarTitleDisplayMode(.inline)
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

    @Binding var selectedDocumentID: UUID?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var docsAppeared = false
    @State private var emptyAppeared = false

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
                .scaleEffect(emptyAppeared ? 1.0 : 0.5)
                .opacity(emptyAppeared ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.05), value: emptyAppeared)
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
            .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.35), value: emptyAppeared)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { emptyAppeared = true }
    }

    private var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200))], spacing: 16) {
                ForEach(Array(documentStore.documents.enumerated()), id: \.element.id) { index, doc in
                    DocumentCell(document: doc, isSelected: doc.id == selectedDocumentID) {
                        selectedDocumentID = doc.id
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                documentStore.delete(doc)
                                if selectedDocumentID == doc.id { selectedDocumentID = nil }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .opacity(docsAppeared ? 1 : 0)
                    .offset(y: docsAppeared ? 0 : 14)
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.82)
                            .delay(Double(index) * 0.04),
                        value: docsAppeared
                    )
                }
            }
            .padding()
            .onAppear { docsAppeared = true }
        }
    }
}

// MARK: - DocumentCell

private struct DocumentCell: View {
    let document: ImportedDocument
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(document.displayName), \(document.documentType.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
