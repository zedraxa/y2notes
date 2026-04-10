import SwiftUI
import PDFKit
import UIKit

// MARK: - PDFViewerView

/// Full-screen PDF viewer with:
/// - PencilKit annotation overlay (toggleable between annotate / read modes).
/// - Sticker and widget placement on each page.
/// - Page navigation bar (prev / next + page indicator).
/// - PDF text search with result strip.
/// - Share original, export annotated PDF, and Open In… workflows.
struct PDFViewerView: View {
    @EnvironmentObject var pdfStore:  PDFStore
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var toolStore: DrawingToolStore
    @Environment(TabWorkspaceStore.self) private var workspace

    let record: PDFNoteRecord
    let tabID: UUID?

    var onOpenCompanionNote: ((UUID) -> Void)?

    @State private var currentPage: Int
    @State private var isAnnotating: Bool = true
    @State private var isSearching: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [PDFPageSearchResult] = []
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    // Sticker / widget state for the current page
    @State private var pageStickers: [StickerInstance] = []
    @State private var pageWidgets: [NoteWidget] = []
    @State private var showStickerPicker: Bool = false
    @State private var showWidgetPicker: Bool = false

    @AppStorage("y2notes.pencilOnlyDrawing") private var pencilOnlyDrawing = false

    init(
        record: PDFNoteRecord,
        tab: TabSession? = nil,
        onOpenCompanionNote: ((UUID) -> Void)? = nil
    ) {
        self.record = record
        self.tabID  = tab?.id
        self.onOpenCompanionNote = onOpenCompanionNote
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

            ZStack {
                PDFPageAnnotationView(
                    pdfURL: pdfStore.pdfURL(for: record),
                    pageIndex: currentPage,
                    annotationData: drawingData,
                    currentTool: toolStore.pkTool,
                    drawingPolicy: pencilOnlyDrawing ? .pencilOnly : .anyInput,
                    isAnnotating: isAnnotating,
                    onPageChanged: { newPage in
                        saveCurrentPageOverlays()
                        currentPage = newPage
                        loadOverlays(for: newPage)
                        pdfStore.updateCurrentPage(id: record.id, page: newPage)
                    },
                    onAnnotationChanged: { page, data in
                        pdfStore.updateAnnotation(id: record.id, page: page, data: data)
                    }
                )

                // Sticker overlay
                stickerOverlay

                // Widget overlay
                widgetOverlay
            }

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
                stickerButton
                widgetButton
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
        .sheet(isPresented: $showStickerPicker) {
            stickerPickerSheet
        }
        .sheet(isPresented: $showWidgetPicker) {
            widgetPickerSheet
        }
        .onAppear {
            loadOverlays(for: currentPage)
        }
        .onChange(of: currentPage) { _, page in
            pdfStore.updateCurrentPage(id: record.id, page: page)
            if let id = tabID {
                workspace.updateTabState(id, pageIndex: page)
            }
        }
    }

    // MARK: - Sticker overlay

    @ViewBuilder
    private var stickerOverlay: some View {
        if isAnnotating && !pageStickers.isEmpty {
            ForEach(pageStickers) { sticker in
                stickerView(sticker)
            }
        }
    }

    @ViewBuilder
    private func stickerView(_ sticker: StickerInstance) -> some View {
        let size = StickerConstants.defaultNaturalSize.width * sticker.scale
        Circle()
            .fill(Color.yellow.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: size * 0.4))
            )
            .opacity(sticker.opacity)
            .rotationEffect(.radians(sticker.rotation))
            .position(sticker.position)
            .allowsHitTesting(false)
    }

    // MARK: - Widget overlay

    @ViewBuilder
    private var widgetOverlay: some View {
        if isAnnotating && !pageWidgets.isEmpty {
            ForEach(pageWidgets) { widget in
                widgetBadge(widget)
            }
        }
    }

    @ViewBuilder
    private func widgetBadge(_ widget: NoteWidget) -> some View {
        RoundedRectangle(cornerRadius: WidgetConstants.cardCornerRadius)
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: WidgetConstants.cardCornerRadius)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
            .overlay(widgetContent(widget))
            .frame(width: widget.frame.size.width, height: widget.frame.size.height)
            .position(widget.frame.position)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func widgetContent(_ widget: NoteWidget) -> some View {
        switch widget.payload {
        case .checklist(let title, _):
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "checklist")
                Text(title.isEmpty ? "Checklist" : title)
                    .font(.caption2)
                    .lineLimit(2)
            }
            .padding(8)
        case .stickyNote(let body, _):
            Text(body.isEmpty ? "Sticky Note" : body)
                .font(.caption2)
                .padding(8)
                .lineLimit(4)
        case .calloutBox(let title, _, _):
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "text.bubble")
                Text(title.isEmpty ? "Callout" : title)
                    .font(.caption2)
                    .lineLimit(2)
            }
            .padding(8)
        default:
            Image(systemName: "widget.small")
                .padding(8)
        }
    }

    // MARK: - Overlay persistence

    private func loadOverlays(for page: Int) {
        pageStickers = pdfStore.stickers(for: record.id, page: page)
        pageWidgets  = pdfStore.widgets(for: record.id, page: page)
    }

    private func saveCurrentPageOverlays() {
        pdfStore.saveStickers(pageStickers, recordID: record.id, page: currentPage)
        pdfStore.saveWidgets(pageWidgets, recordID: record.id, page: currentPage)
    }

    // MARK: - Sticker picker

    private var stickerPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(StickerCategory.allCases) { category in
                    Button {
                        let sticker = StickerInstance(
                            stickerID: "\(category.rawValue)_default",
                            position: CGPoint(x: 200, y: 300),
                            scale: 1.0
                        )
                        pageStickers.append(sticker)
                        pdfStore.saveStickers(pageStickers, recordID: record.id, page: currentPage)
                        showStickerPicker = false
                    } label: {
                        Label(category.displayName, systemImage: category.systemImage)
                    }
                }
            }
            .navigationTitle("Add Sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showStickerPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Widget picker

    private var widgetPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(WidgetKind.allCases, id: \.rawValue) { kind in
                    Button {
                        let center = CGPoint(x: 200, y: 300)
                        let widget: NoteWidget
                        switch kind {
                        case .checklist:       widget = .makeChecklist(at: center)
                        case .quickTable:      widget = .makeQuickTable(at: center)
                        case .calloutBox:      widget = .makeCalloutBox(at: center)
                        case .referenceCard:   widget = .makeReferenceCard(at: center)
                        case .stickyNote:      widget = .makeStickyNote(at: center)
                        case .flashcard:       widget = .makeFlashcard(at: center)
                        case .progressTracker: widget = .makeProgressTracker(at: center)
                        }
                        pageWidgets.append(widget)
                        pdfStore.saveWidgets(pageWidgets, recordID: record.id, page: currentPage)
                        showWidgetPicker = false
                    } label: {
                        Label(kind.rawValue.capitalized, systemImage: widgetIcon(for: kind))
                    }
                }
            }
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showWidgetPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func widgetIcon(for kind: WidgetKind) -> String {
        switch kind {
        case .checklist:       return "checklist"
        case .quickTable:      return "tablecells"
        case .calloutBox:      return "text.bubble"
        case .referenceCard:   return "rectangle.and.text.magnifyingglass"
        case .stickyNote:      return "note.text"
        case .flashcard:       return "rectangle.on.rectangle.angled"
        case .progressTracker: return "chart.bar.fill"
        }
    }

    // MARK: - Toolbar buttons

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

    private var stickerButton: some View {
        Button { showStickerPicker = true } label: {
            Image(systemName: "star.square")
        }
        .disabled(!isAnnotating)
        .accessibilityLabel("Add sticker")
    }

    private var widgetButton: some View {
        Button { showWidgetPicker = true } label: {
            Image(systemName: "widget.small")
        }
        .disabled(!isAnnotating)
        .accessibilityLabel("Add widget")
    }

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
        .accessibilityLabel(
            pencilOnlyDrawing ? "Enable finger drawing" : "Enable Pencil-only drawing"
        )
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
            Image(systemName: isSearching
                  ? "magnifyingglass.circle.fill" : "magnifyingglass")
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
                saveCurrentPageOverlays()
                currentPage -= 1
                loadOverlays(for: currentPage)
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
                saveCurrentPageOverlays()
                currentPage += 1
                loadOverlays(for: currentPage)
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
                        searchQuery   = ""
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
                                saveCurrentPageOverlays()
                                currentPage = result.pageIndex
                                loadOverlays(for: result.pageIndex)
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
                            .accessibilityLabel(
                                "Go to page \(result.pageIndex + 1), match: \(result.snippet)"
                            )
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
                let idx = document.index(for: page)
                guard idx != NSNotFound else { continue }
                let snippet = selection.string ?? searchQuery
                results.append(PDFPageSearchResult(pageIndex: idx, snippet: snippet))
            }
        }
        searchResults = results
        if let first = results.first {
            saveCurrentPageOverlays()
            currentPage = first.pageIndex
            loadOverlays(for: first.pageIndex)
        }
    }

    // MARK: - Share / Export / Open-In

    private func shareOriginal() {
        shareItems     = [pdfStore.pdfURL(for: record)]
        showShareSheet = true
    }

    private func exportAndShare() {
        saveCurrentPageOverlays()
        guard let url = pdfStore.exportAnnotatedPDF(for: liveRecord) else { return }
        shareItems     = [url]
        showShareSheet = true
    }

    private func openIn() {
        saveCurrentPageOverlays()
        guard let url = pdfStore.exportAnnotatedPDF(for: liveRecord) else { return }
        let controller = UIDocumentInteractionController(url: url)
        controller.name = liveRecord.title
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows
                  .first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        controller.presentOpenInMenu(
            from: rootVC.view.bounds, in: rootVC.view, animated: true
        )
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
