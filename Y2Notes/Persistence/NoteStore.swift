import Foundation
import Combine

/// Persistent store for notes and notebooks. Saves to the app's Documents directory as JSON.
/// All mutations are performed on the main thread (via @Published / @MainActor).
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var notebooks: [Notebook] = []

    private let notesURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_notes.json")
    }()

    private let notebooksURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_notebooks.json")
    }()

    init() {
        load()
    }

    // MARK: - Note CRUD

    /// Creates a new note, optionally filing it into a notebook.
    @discardableResult
    func addNote(inNotebook notebookID: UUID? = nil) -> Note {
        let note = Note(title: "Note \(notes.count + 1)", notebookID: notebookID)
        notes.insert(note, at: 0)
        save()
        return note
    }

    func deleteNotes(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        save()
    }

    /// Deletes notes whose IDs are in `ids`. Safe when caller holds a filtered/sorted view.
    func deleteNotes(ids: [UUID]) {
        notes.removeAll { ids.contains($0.id) }
        save()
    }

    func updateTitle(for noteID: UUID, title: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].title = title
        notes[idx].modifiedAt = Date()
        save()
    }

    func updateDrawing(for noteID: UUID, data: Data) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].drawingData = data
        notes[idx].modifiedAt = Date()
        // Drawing saves are debounced by the caller; we just update state here.
    }

    /// Creates a copy of the note inserted directly after the original.
    @discardableResult
    func duplicateNote(id: UUID) -> Note? {
        guard let original = notes.first(where: { $0.id == id }) else { return nil }
        let copy = Note(
            title: original.title.isEmpty ? "Copy" : "\(original.title) (Copy)",
            createdAt: Date(),
            modifiedAt: Date(),
            drawingData: original.drawingData,
            isFavorited: false,
            notebookID: original.notebookID
        )
        if let idx = notes.firstIndex(of: original) {
            notes.insert(copy, at: idx + 1)
        } else {
            notes.insert(copy, at: 0)
        }
        save()
        return copy
    }

    /// Moves the note into a notebook (or unfiled when `notebookID` is nil).
    func moveNote(id: UUID, toNotebook notebookID: UUID?) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].notebookID = notebookID
        notes[idx].modifiedAt = Date()
        save()
    }

    /// Toggles the starred/favorited state of a note.
    func toggleFavorite(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isFavorited.toggle()
        notes[idx].modifiedAt = Date()
        save()
    }

    // MARK: - Note helpers

    /// All notes in a specific notebook, unsorted.
    func notes(inNotebook notebookID: UUID) -> [Note] {
        notes.filter { $0.notebookID == notebookID }
    }

    /// The 10 most recently modified notes across all notebooks.
    var recentNotes: [Note] {
        Array(notes.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(10))
    }

    /// All favorited notes sorted by most-recently modified.
    var favoritedNotes: [Note] {
        notes.filter { $0.isFavorited }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Notebook CRUD

    /// Creates and stores a new notebook.
    @discardableResult
    func addNotebook(name: String, cover: NotebookCover = .ocean) -> Notebook {
        let nb = Notebook(name: name, cover: cover)
        notebooks.insert(nb, at: 0)
        save()
        return nb
    }

    func renameNotebook(id: UUID, name: String) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].name = name
        notebooks[idx].modifiedAt = Date()
        save()
    }

    func updateNotebookCover(id: UUID, cover: NotebookCover) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].cover = cover
        notebooks[idx].modifiedAt = Date()
        save()
    }

    /// Deletes a notebook and unfiles all notes that belonged to it.
    func deleteNotebook(id: UUID) {
        for i in notes.indices where notes[i].notebookID == id {
            notes[i].notebookID = nil
        }
        notebooks.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    func save() {
        saveJSON(notes, to: notesURL)
        saveJSON(notebooks, to: notebooksURL)
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            assertionFailure("Y2Notes: save failed — \(error)")
        }
    }

    private func load() {
        notes     = loadJSON([Note].self,     from: notesURL)     ?? []
        notebooks = loadJSON([Notebook].self, from: notebooksURL) ?? []
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Corrupted store — start fresh rather than crashing.
            return nil
        }
    }
}
