import Foundation
import Combine
import UIKit

// MARK: - Save state

/// Describes the current disk-persistence state of the store.
/// Observe `NoteStore.saveState` to drive save-status UI.
enum SaveState: Equatable {
    case idle
    case saving
    case saved
    case error(String)
}

// MARK: - NoteStore

/// Persistent store for notes and notebooks. Saves to the app's Documents directory as JSON.
/// All mutations are performed on the main thread (via @Published / @MainActor).
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var notebooks: [Notebook] = []
    /// Current disk-write state. Observe this to drive saving / saved / error UI.
    @Published private(set) var saveState: SaveState = .idle

    private let notesURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_notes.json")
    }()

    private let notebooksURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_notebooks.json")
    }()

    /// True when in-memory state has been mutated but not yet flushed to disk.
    private var isDirty = false
    /// Repeating timer that autosaves dirty state approximately every 30 s.
    private var autosaveTimer: Timer?

    init() {
        load()
        startAutosaveTimer()
        setupLifecycleObservers()
    }

    deinit {
        autosaveTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Autosave / lifecycle

    private func startAutosaveTimer() {
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.isDirty else { return }
            self.flushToDisk()
        }
        autosaveTimer?.tolerance = 5
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppWillResignActive() {
        guard isDirty else { return }
        flushToDisk()
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
        // Mark dirty so autosave timer and willResignActive flush pick this up.
        // The canvas coordinator owns the debounced 0.8 s save trigger.
        isDirty = true
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

    /// Creates and stores a new notebook with full wizard configuration.
    @discardableResult
    func addNotebook(
        name: String,
        cover: NotebookCover = .ocean,
        pageType: PageType = .ruled,
        pageSize: PageSize = .letter,
        orientation: PageOrientation = .portrait,
        defaultTheme: AppTheme? = nil,
        paperMaterial: PaperMaterial = .standard,
        customCoverData: Data? = nil
    ) -> Notebook {
        let nb = Notebook(
            name: name,
            cover: cover,
            pageType: pageType,
            pageSize: pageSize,
            orientation: orientation,
            defaultTheme: defaultTheme,
            paperMaterial: paperMaterial,
            customCoverData: customCoverData
        )
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

    // MARK: - Persistence public API

    /// Marks state clean and immediately flushes both data files to disk.
    func save() {
        isDirty = false
        flushToDisk()
    }

    // MARK: - Persistence internals

    /// Writes both data files atomically and updates `saveState`.
    private func flushToDisk() {
        saveState = .saving
        var firstError: Error?
        do {
            let data = try JSONEncoder().encode(notes)
            try writeAtomically(data, to: notesURL)
        } catch {
            firstError = error
        }
        do {
            let data = try JSONEncoder().encode(notebooks)
            try writeAtomically(data, to: notebooksURL)
        } catch {
            if firstError == nil { firstError = error }
        }
        if let error = firstError {
            saveState = .error(error.localizedDescription)
            assertionFailure("Y2Notes: save failed — \(error)")
        } else {
            saveState = .saved
        }
    }

    /// Writes `data` to `url` using an atomic swap (write-to-temp + rename), while keeping
    /// a one-generation backup at `url.bak` to allow recovery from interrupted writes.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        let backupURL = url.appendingPathExtension("bak")
        // Snapshot the current good file as a backup before overwriting it.
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: backupURL)
            if (try? FileManager.default.copyItem(at: url, to: backupURL)) == nil {
                // Best-effort — the primary write still proceeds. Log in debug builds
                // so disk-full or permission issues are visible during development.
                #if DEBUG
                print("Y2Notes: backup creation failed for \(url.lastPathComponent)")
                #endif
            }
        }
        // .atomic writes to a temp sibling then renames into place, making the
        // final swap as close to atomic as the filesystem permits.
        try data.write(to: url, options: .atomic)
    }

    private func load() {
        notes     = loadJSON([Note].self,     from: notesURL)     ?? []
        notebooks = loadJSON([Notebook].self, from: notebooksURL) ?? []
    }

    /// Decodes `type` from `url`. On missing or corrupt primary file, falls back to
    /// the `.bak` sibling created by `writeAtomically` so interrupted writes are recoverable.
    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        if let value = attemptLoad(type, from: url) {
            return value
        }
        // Primary missing or corrupt — try the backup.
        let backupURL = url.appendingPathExtension("bak")
        if let value = attemptLoad(type, from: backupURL) {
            // Promote the backup to primary so the next save goes to the right place.
            // If this copy fails, data is still in memory and will be written to the
            // primary path on the very next save() call.
            if (try? FileManager.default.copyItem(at: backupURL, to: url)) == nil {
                #if DEBUG
                print("Y2Notes: backup promotion failed for \(url.lastPathComponent); data will be rewritten on next save")
                #endif
            }
            return value
        }
        return nil
    }

    private func attemptLoad<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
