import SwiftUI
import PencilKit

// MARK: - Sort order

enum NoteSortOrder: String, CaseIterable {
    case modifiedDesc = "Recently Modified"
    case modifiedAsc  = "Oldest Modified"
    case titleAsc     = "Title A–Z"
    case titleDesc    = "Title Z–A"
    case createdDesc  = "Newest Created"
    case createdAsc   = "Oldest Created"

    var systemImage: String {
        switch self {
        case .modifiedDesc, .createdDesc: return "arrow.down.circle"
        case .modifiedAsc,  .createdAsc:  return "arrow.up.circle"
        case .titleAsc:                   return "textformat.abc"
        case .titleDesc:                  return "textformat"
        }
    }
}

// MARK: - Note list

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?

    @State private var searchText  = ""
    @State private var sortOrder: NoteSortOrder = .modifiedDesc

    // Filtered + sorted projection of the store.
    private var displayedNotes: [Note] {
        let source = searchText.isEmpty
            ? noteStore.notes
            : noteStore.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

        switch sortOrder {
        case .modifiedDesc: return source.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedAsc:  return source.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAsc:     return source.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .titleDesc:    return source.sorted { $0.title.localizedCompare($1.title) == .orderedDescending }
        case .createdDesc:  return source.sorted { $0.createdAt > $1.createdAt }
        case .createdAsc:   return source.sorted { $0.createdAt < $1.createdAt }
        }
    }

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(displayedNotes) { note in
                NoteRowView(note: note)
                    .tag(note.id)
                    // Leading swipe: duplicate note
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            duplicateNote(note)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
            }
            .onDelete(perform: deleteDisplayedNotes)
        }
        .navigationTitle("Y2Notes")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createNote) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New note")
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
        }
        .overlay {
            if displayedNotes.isEmpty {
                emptySearchOverlay
            }
        }
    }

    // MARK: Sort menu

    private var sortMenu: some View {
        Menu {
            ForEach(NoteSortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrder = order
                } label: {
                    if sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Text(order.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort notes")
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptySearchOverlay: some View {
        if !searchText.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("No notes match \"\(searchText)\"")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    // MARK: Actions

    private func createNote() {
        let note = noteStore.addNote()
        selectedNoteID = note.id
    }

    private func duplicateNote(_ note: Note) {
        if let copy = noteStore.duplicateNote(noteID: note.id) {
            selectedNoteID = copy.id
        }
    }

    /// `onDelete` passes offsets into `displayedNotes` (filtered/sorted), so we map to IDs
    /// before handing off to the store to avoid index mismatch.
    private func deleteDisplayedNotes(at offsets: IndexSet) {
        let ids = offsets.map { displayedNotes[$0].id }
        noteStore.deleteNotes(ids: ids)
    }
}

// MARK: - Row

private struct NoteRowView: View {
    let note: Note

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(note.title.isEmpty ? .secondary : .primary)
                Text(note.modifiedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        // Re-generate the thumbnail whenever the drawing data changes.
        .task(id: note.drawingData) {
            thumbnail = await makeThumbnail(from: note.drawingData)
        }
    }

    // MARK: Thumbnail view

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(uiColor: .systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )

            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .frame(width: 60, height: 44)
    }

    // MARK: Thumbnail generation

    /// Renders the stored PKDrawing to a small UIImage on a background thread.
    /// Returns nil when the note has no strokes yet.
    private func makeThumbnail(from data: Data) async -> UIImage? {
        guard !data.isEmpty else { return nil }

        return await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data),
                  !drawing.bounds.isEmpty else { return nil }

            // Expand the tight bounding box so strokes near the edge aren't clipped.
            let renderRect = drawing.bounds.insetBy(dx: -20, dy: -20)

            // Target ≈ 120×90 px output: derive scale so the longer axis fits,
            // then halve it to keep the image lightweight.
            let targetWidth:  CGFloat = 120
            let targetHeight: CGFloat = 90
            let scale = max(targetWidth / renderRect.width,
                            targetHeight / renderRect.height) * 0.5
            return drawing.image(from: renderRect, scale: scale)
        }.value
    }
}
