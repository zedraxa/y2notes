import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @State private var selectedNoteID: UUID?
    /// Tracks the ID of the most-recently created note so the editor can
    /// auto-focus the title field for immediate rename.
    @State private var newlyCreatedNoteID: UUID?

    private var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return noteStore.notes.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            NoteListView(selectedNoteID: $selectedNoteID, onNoteCreated: { id in
                newlyCreatedNoteID = id
            })
        } detail: {
            if let note = selectedNote {
                NoteEditorView(note: note, autoFocusTitle: note.id == newlyCreatedNoteID)
                    .id(note.id)
                    .onAppear { newlyCreatedNoteID = nil }
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Select or create a note")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Tap \(Image(systemName: "square.and.pencil")) to start writing")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
