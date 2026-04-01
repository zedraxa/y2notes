import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var themeStore: ThemeStore
    @State private var selectedNoteID: UUID?

    private var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return noteStore.notes.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            NoteListView(selectedNoteID: $selectedNoteID)
        } detail: {
            if let note = selectedNote {
                NoteEditorView(note: note)
                    .id(note.id)
            } else {
                emptyState
            }
        }
        .preferredColorScheme(themeStore.definition.colorScheme)
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
