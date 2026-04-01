import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?
    let onNoteCreated: (UUID) -> Void

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
        onNoteCreated(note.id)
    }

    /// Map offsets in `filteredNotes` back to UUIDs so deletion works correctly
    /// regardless of whether a search filter is active.
    private func deleteFiltered(at offsets: IndexSet) {
        let ids = offsets.map { filteredNotes[$0].id }
        noteStore.deleteNotes(ids: ids)
    }
}

// MARK: - Row

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(note.title.isEmpty ? .secondary : .primary)
            Text(note.modifiedAt, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
