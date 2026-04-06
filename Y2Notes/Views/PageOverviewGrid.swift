import SwiftUI
import PencilKit

// MARK: - Page Overview Grid

/// Full-screen grid of page thumbnails shown via pinch-to-overview gesture or
/// the page indicator button. Tap a thumbnail to jump to that page.
///
/// Each page is rendered as a miniature `PKDrawing` snapshot on a background
/// that matches the note's canvas colour.
struct PageOverviewGrid: View {
    let note: Note
    @Binding var currentPageIndex: Int
    let canvasBackground: UIColor
    let onDismiss: () -> Void

    @EnvironmentObject var noteStore: NoteStore

    /// Thumbnails are generated asynchronously — keyed by page index.
    @State private var thumbnails: [Int: UIImage] = [:]
    /// Page index pending deletion confirmation.
    @State private var pageToDelete: Int?
    /// Whether the delete confirmation alert is shown.
    @State private var showDeleteConfirmation = false

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            pageGridContent
                .navigationTitle("Pages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { pageOverviewToolbar }
                .alert("Delete Page?", isPresented: $showDeleteConfirmation) {
                    deletePageAlertActions
                } message: {
                    deletePageAlertMessage
                }
        }
    }

    // MARK: - Extracted subviews (type-checker decomposition)

    private var pageGridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<note.pageCount, id: \.self) { index in
                        draggablePageCell(index: index)
                    }
                }
                .padding(16)
            }
            .onAppear {
                proxy.scrollTo(currentPageIndex, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func draggablePageCell(index: Int) -> some View {
        pageCell(index: index)
            .id(index)
            .draggable(String(index)) {
                Text("Page \(index + 1)")
                    .font(.caption.bold())
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let sourceStr = items.first,
                      let source = Int(sourceStr),
                      source != index else { return false }
                noteStore.reorderPageInNote(noteID: note.id, from: source, to: index)
                if currentPageIndex == source {
                    currentPageIndex = index
                } else if source < currentPageIndex && index >= currentPageIndex {
                    currentPageIndex -= 1
                } else if source > currentPageIndex && index <= currentPageIndex {
                    currentPageIndex += 1
                }
                thumbnails.removeAll()
                return true
            }
    }

    @ToolbarContentBuilder
    private var pageOverviewToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { onDismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let newIndex = noteStore.addPage(to: note.id) {
                    currentPageIndex = newIndex
                    onDismiss()
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add page")
        }
    }

    @ViewBuilder
    private var deletePageAlertActions: some View {
        Button("Cancel", role: .cancel) { pageToDelete = nil }
        Button("Delete", role: .destructive) {
            if let page = pageToDelete {
                let wasOnDeletedPage = currentPageIndex == page
                noteStore.removePage(from: note.id, at: page)
                thumbnails.removeAll()
                if wasOnDeletedPage {
                    currentPageIndex = max(0, min(currentPageIndex, note.pageCount - 2))
                } else if page < currentPageIndex {
                    currentPageIndex -= 1
                }
                pageToDelete = nil
            }
        }
    }

    @ViewBuilder
    private var deletePageAlertMessage: some View {
        if let page = pageToDelete {
            Text("Page \(page + 1) will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Page cell

    @ViewBuilder
    private func pageCell(index: Int) -> some View {
        let isSelected = index == currentPageIndex

        Button {
            currentPageIndex = index
            onDismiss()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Background matching canvas colour
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: canvasBackground))

                    if let thumb = thumbnails[index] {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    } else {
                        // Placeholder while thumbnail renders
                        ProgressView()
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color(uiColor: .separator),
                            lineWidth: isSelected ? 3 : 1
                        )
                )
                .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 4 : 2)

                Text("Page \(index + 1)")
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button {
                currentPageIndex = index
                onDismiss()
            } label: {
                Label("Go to Page", systemImage: "arrow.right")
            }

            Button {
                if let newIdx = noteStore.duplicatePageInNote(noteID: note.id, pageIndex: index) {
                    thumbnails.removeAll()
                    currentPageIndex = newIdx
                }
            } label: {
                Label("Duplicate Page", systemImage: "doc.on.doc")
            }

            if note.pageCount > 1 {
                Divider()
                Button(role: .destructive) {
                    pageToDelete = index
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            }
        }
        .task(id: "\(note.id)-\(index)-\(note.pages.indices.contains(index) ? note.pages[index].count : 0)") {
            await generateThumbnail(for: index)
        }
    }

    // MARK: - Thumbnail generation

    /// Renders a miniature image of the page's PKDrawing off the main thread.
    private func generateThumbnail(for index: Int) async {
        guard note.pages.indices.contains(index) else { return }
        let data = note.pages[index]
        guard !data.isEmpty else {
            // Blank page — no thumbnail needed
            thumbnails[index] = nil
            return
        }

        // Capture screen scale on the main actor before entering the detached task.
        let screenScale = UIScreen.main.scale

        let image = await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data) else { return nil as UIImage? }
            let bounds = drawing.bounds
            guard !bounds.isEmpty else { return nil as UIImage? }

            // Expand bounds slightly to avoid clipping edge strokes.
            let padding: CGFloat = 20
            let renderRect = bounds.insetBy(dx: -padding, dy: -padding)

            // Scale to thumbnail size (max 240pt wide).
            let maxDimension: CGFloat = 240
            let scale = min(maxDimension / renderRect.width, maxDimension / renderRect.height, 1.0)

            return drawing.image(from: renderRect, scale: scale * screenScale)
        }.value

        if let image {
            thumbnails[index] = image
        }
    }
}
