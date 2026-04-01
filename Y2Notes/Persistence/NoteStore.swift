import Foundation
import Combine

/// Persistent store for notes. Saves to the app's Documents directory as JSON.
/// All mutations are performed on the main thread (via @Published / @MainActor).
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    private let saveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_notes.json")
    }()

    init() {
        load()
    }

    // MARK: - CRUD

    @discardableResult
    func addNote() -> Note {
        let note = Note(title: "Note \(notes.count + 1)")
        notes.insert(note, at: 0)
        save()
        return note
    }

    func deleteNotes(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        save()
    }

    /// Deletes notes whose IDs are in `ids`. Used when the caller holds a filtered/sorted view.
    func deleteNotes(ids: [UUID]) {
        notes.removeAll { ids.contains($0.id) }
        save()
    }

    func updateTitle(for noteID: UUID, title: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].title = title
        notes[idx].modifiedAt = Date()
        // Debounced saves happen in NoteEditorView; call save() here for title changes.
        save()
    }

    /// Sets or clears the per-note theme override. Pass nil to revert to the global app theme.
    func updateThemeOverride(for noteID: UUID, theme: AppTheme?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].themeOverride = theme
        save()
    }

    func updateDrawing(for noteID: UUID, data: Data) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].drawingData = data
        notes[idx].modifiedAt = Date()
        // Drawing saves are debounced by the caller; we just update state here.
    }

    // MARK: - Persistence

    func save() {
        do {
            let encoded = try JSONEncoder().encode(notes)
            try encoded.write(to: saveURL, options: .atomic)
        } catch {
            assertionFailure("Y2Notes: save failed — \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            notes = try JSONDecoder().decode([Note].self, from: data)
        } catch {
            // Corrupted store — start fresh rather than crashing.
            notes = []
        }
    }
}
