import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?
    @State private var searchText = ""

    /// Notes sorted newest-modified first, optionally filtered by search text.
    private var displayedNotes: [Note] {
        let sorted = noteStore.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(displayedNotes) { note in
                NoteRowView(note: note)
                    .tag(note.id)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Y2Notes")
        .searchable(text: $searchText, prompt: "Search notes")
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

    /// Delete notes whose IDs match the tapped rows in the currently displayed order.
    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { displayedNotes[$0].id }
        noteStore.deleteNotes(withIDs: ids)
    }
}

// MARK: - Row

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.headline)
                .foregroundColor(note.title.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Text(note.modifiedAt, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
