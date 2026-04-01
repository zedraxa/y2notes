import SwiftUI
import PencilKit

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?
    @State private var searchText = ""

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return noteStore.notes }
        return noteStore.notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(filteredNotes) { note in
                NoteRowView(note: note)
                    .tag(note.id)
            }
            .onDelete(perform: deleteFiltered)
        }
        .searchable(text: $searchText, prompt: "Search notes")
        .navigationTitle("Y2Notes")
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
        }
    }

    private func createNote() {
        let note = noteStore.addNote()
        selectedNoteID = note.id
    }

    /// Map swipe-to-delete offsets from the filtered list back to the full notes array.
    private func deleteFiltered(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredNotes[$0].id }
        let fullOffsets = IndexSet(
            noteStore.notes.enumerated()
                .filter { idsToDelete.contains($0.element.id) }
                .map { $0.offset }
        )
        noteStore.deleteNotes(at: fullOffsets)
    }
}

// MARK: - Row

private struct NoteRowView: View {
    let note: Note
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(note.modifiedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            thumbnailView
        }
        .padding(.vertical, 4)
        .task(id: note.modifiedAt) {
            thumbnail = await makeThumbnail(from: note.drawingData)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        let size = CGSize(width: 60, height: 45)
        if let img = thumbnail {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray6))
                .frame(width: size.width, height: size.height)
        }
    }

    /// Renders a small image from stored PKDrawing data on a background thread.
    private func makeThumbnail(from data: Data) async -> UIImage? {
        guard !data.isEmpty else { return nil }
        return await Task(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data) else { return nil }
            let bounds = drawing.bounds
            guard !bounds.isEmpty else { return nil }
            // Expand the crop rect slightly so strokes at the edge aren't clipped.
            let padded = bounds.insetBy(dx: -12, dy: -12)
            return drawing.image(from: padded, scale: 2.0)
        }.value
    }
}
