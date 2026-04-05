import SwiftUI
import PDFKit
import UIKit

// MARK: - PDFViewerView

/// Full-screen PDF viewer with:
/// - PencilKit annotation overlay (toggleable between annotate / read modes).
/// - Page navigation bar (prev / next + page indicator).
/// - PDF text search with result strip.
/// - Share original, export annotated PDF, and Open In… workflows.
struct PDFViewerView: View {
    @EnvironmentObject var pdfStore:  PDFStore
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var toolStore: DrawingToolStore
    @Environment(TabWorkspaceStore.self) private var workspace

    let record: PDFNoteRecord
    /// The tab ID this viewer is running in, or nil when opened outside the tab workspace.
    let tabID: UUID?

    @State private var currentPage: Int
    @State private var isAnnotating: Bool = true
    @State private var isSearching: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [PDFPageSearchResult] = []
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    @AppStorage("y2notes.pencilOnlyDrawing") private var pencilOnlyDrawing = false

    init(record: PDFNoteRecord, tab: TabSession? = nil) {
        self.record  = record
        self.tabID   = tab?.id
        // Prefer the tab's persisted page over the store's record page.
        _currentPage = State(initialValue: tab?.pageIndex ?? record.currentPage)
    }

    // MARK: - Live record from store

    private var liveRecord: PDFNoteRecord {
        pdfStore.records.first { $0.id == record.id } ?? record
    }

    private var pageCount: Int { liveRecord.pageCount }

    private var drawingData: [String: Data] { liveRecord.annotationData }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            PDFPageAnnotationView(
                pdfURL: pdfStore.pdfURL(for: record),
                pageIndex: currentPage,
                annotationData: drawingData,
                currentTool: toolStore.pkTool,
                drawingPolicy: pencilOnlyDrawing ? .pencilOnly : .anyInput,
                isAnnotating: isAnnotating,
                onPageChanged: { newPage in
                    currentPage = newPage
                    pdfStore.updateCurrentPage(id: record.id, page: newPage)
                },
                onAnnotationChanged: { page, data in
                    pdfStore.updateAnnotation(id: record.id, page: page, data: data)
                }
            )

            DrawingToolbarView(toolStore: toolStore)
                .disabled(!isAnnotating)
                .opacity(isAnnotating ? 1 : 0.5)

            pageNavigationBar
        }
        .navigationTitle(liveRecord.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: isSearching)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                companionNoteButton
                annotateToggleButton
                pencilPolicyButton
                searchButton
                shareMenu
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
                .ignoresSafeArea()
        }
        .onChange(of: currentPage) { _, page in
            pdfStore.updateCurrentPage(id: record.id, page: page)
            if let id = tabID {
                workspace.updateTabState(id, pageIndex: page)
            }
        }
    }

    // MARK: - Toolbar buttons

    /// Opens or creates the companion note linked to this PDF.
    private var companionNoteButton: some View {
        Button {
            if let existing = noteStore.notes(forPDF: record.id).first {
                workspace.openTab(
                    .note(id: existing.id),
                    displayName: existing.title,
                    accentColor: [0.8, 0.3, 0.3]
                )
            } else {
                let note = noteStore.addNote(forPDF: record)
                workspace.openTab(
                    .note(id: note.id),
                    displayName: note.title,
                    accentColor: [0.8, 0.3, 0.3]
                )
            }
        } label: {
            Image(systemName: noteStore.hasCompanionNote(forPDF: record.id)
                  ? "note.text" : "note.text.badge.plus")
        }
        .accessibilityLabel(noteStore.hasCompanionNote(forPDF: record.id)
                            ? "Open companion note" : "Create companion note")
    }

    /// Toggles between annotate mode (canvas active) and read mode (PDFView handles touches).
    private var annotateToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isAnnotating.toggle() }
        } label: {
            Image(systemName: isAnnotating ? "pencil.circle.fill" : "pencil.circle")
        }
        .accessibilityLabel(isAnnotating ? "Switch to read mode" : "Switch to annotate mode")
    }

    private var pencilPolicyButton: some View {
        Button {
            pencilOnlyDrawing.toggle()
        } label: {
            Image(systemName: pencilOnlyDrawing ? "pencil.tip" : "hand.and.pencil")
        }
        .disabled(!isAnnotating)
        .accessibilityLabel(pencilOnlyDrawing ? "Enable finger drawing" : "Enable Pencil-only drawing")
    }

    private var searchButton: some View {
        Button {
            withAnimation {
                isSearching.toggle()
                if !isSearching {
                    searchResults = []
                    searchQuery   = ""
                }
            }
        } label: {
            Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
        }
        .accessibilityLabel(isSearching ? "Close search" : "Search PDF text")
    }

    private var shareMenu: some View {
        Menu {
            Button {
                shareOriginal()
            } label: {
                Label("Share Original PDF", systemImage: "square.and.arrow.up")
            }

            Button {
                exportAndShare()
            } label: {
                Label("Export Annotated PDF", systemImage: "arrow.up.doc.fill")
            }

            Button {
                openIn()
            } label: {
                Label("Open In…", systemImage: "arrow.up.forward.app")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share options")
    }

    // MARK: - Page navigation bar

    private var pageNavigationBar: some View {
        HStack(spacing: 20) {
            Button {
                guard currentPage > 0 else { return }
                currentPage -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(currentPage == 0)
            .accessibilityLabel("Previous page")

            Text("Page \(currentPage + 1) of \(pageCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 100)
                .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")

            Button {
                guard currentPage < pageCount - 1 else { return }
                currentPage += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(currentPage >= pageCount - 1)
            .accessibilityLabel("Next page")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search in PDF…", text: $searchQuery)
                    .submitLabel(.search)
                    .onSubmit(performSearch)
                    .autocorrectionDisabled()
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery  = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if !searchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(searchResults) { result in
                            Button {
                                currentPage = result.pageIndex
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Page \(result.pageIndex + 1)")
                                        .font(.caption2.bold())
                                    Text(result.snippet)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    currentPage == result.pageIndex
                                        ? Color.accentColor.opacity(0.15)
                                        : Color(uiColor: .tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Go to page \(result.pageIndex + 1), match: \(result.snippet)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            } else if !searchQuery.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }

            Divider()
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Search logic

    private func performSearch() {
        guard !searchQuery.isEmpty else { searchResults = []; return }
        let url = pdfStore.pdfURL(for: record)
        guard let document = PDFDocument(url: url) else { return }

        let selections = document.findString(searchQuery, withOptions: .caseInsensitive)
        var results: [PDFPageSearchResult] = []
        for selection in selections {
            if let page = selection.pages.first {
                let pageIndex = document.index(for: page)
                guard pageIndex != NSNotFound else { continue }
                let snippet = selection.string ?? searchQuery
                // First match per page for the result strip; all contribute to navigation.
                results.append(PDFPageSearchResult(pageIndex: pageIndex, snippet: snippet))
            }
        }
        searchResults = results
        // Navigate to the first result automatically.
        if let first = results.first { currentPage = first.pageIndex }
    }

    // MARK: - Share / Export / Open-In

    private func shareOriginal() {
        shareItems     = [pdfStore.pdfURL(for: record)]
        showShareSheet = true
    }

    private func exportAndShare() {
        guard let url = pdfStore.exportAnnotatedPDF(for: liveRecord) else { return }
        shareItems     = [url]
        showShareSheet = true
    }

    private func openIn() {
        guard let url = pdfStore.exportAnnotatedPDF(for: liveRecord) else { return }
        let controller = UIDocumentInteractionController(url: url)
        controller.name = liveRecord.title
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        controller.presentOpenInMenu(from: rootVC.view.bounds, in: rootVC.view, animated: true)
    }
}

// MARK: - PDFPageSearchResult

struct PDFPageSearchResult: Identifiable {
    let id      = UUID()
    let pageIndex: Int
    let snippet: String
}

// MARK: - ShareSheet

/// Wraps `UIActivityViewController` for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
