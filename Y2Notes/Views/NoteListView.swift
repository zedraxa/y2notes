import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(noteStore.notes) { note in
                NoteRowView(note: note)
                    .tag(note.id)
            }
            .onDelete(perform: noteStore.deleteNotes)
        }
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
}

// MARK: - Row

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            Text(note.modifiedAt, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
