import Foundation

// MARK: - RustDataBridge

/// Thin Swift wrapper around the `libY2Data` C FFI.
///
/// The bridge converts between Swift types (`String`, `UUID`, `Data`) and the
/// null-terminated UTF-8 strings used by the Rust C API.  All returned JSON
/// strings are automatically freed after decoding.
///
/// ## Lifecycle
/// Call `RustDataBridge.initialize()` once at app startup (e.g. in
/// `ServiceContainer.init`) and `RustDataBridge.shutdown()` on termination.
///
/// ## Thread Safety
/// The Rust data store uses an internal `Mutex`.  The bridge methods are safe
/// to call from any thread, though callers should prefer the main thread for
/// UI-triggered mutations.
enum RustDataBridge {

    // MARK: - Lifecycle

    /// Initialise the Rust data store, loading persisted JSON from the
    /// app's Documents directory.
    @discardableResult
    static func initialize() -> Bool {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return y2data_init(docsURL.path)
    }

    /// Persist all in-memory data to disk.
    @discardableResult
    static func save() -> Bool {
        y2data_save()
    }

    /// Tear down the Rust data store and flush to disk.
    static func shutdown() {
        y2data_shutdown()
    }

    // MARK: - Notes

    /// Retrieve all notes from the Rust data store.
    static func getAllNotes() -> [[String: Any]] {
        guard let ptr = y2data_get_all_notes() else { return [] }
        defer { y2data_free_string(ptr) }
        return decodeJSONArray(ptr)
    }

    /// Retrieve a single note by its UUID.
    static func getNote(id: UUID) -> [String: Any]? {
        guard let ptr = y2data_get_note(id.uuidString) else { return nil }
        defer { y2data_free_string(ptr) }
        return decodeJSONObject(ptr)
    }

    /// Create a new note with the given title.  Returns the UUID of the new note.
    @discardableResult
    static func addNote(title: String) -> UUID? {
        guard let ptr = y2data_add_note(title) else { return nil }
        defer { y2data_free_string(ptr) }
        return UUID(uuidString: String(cString: ptr))
    }

    /// Delete a note by its UUID.
    @discardableResult
    static func deleteNote(id: UUID) -> Bool {
        y2data_delete_note(id.uuidString)
    }

    /// Update the title of an existing note.
    @discardableResult
    static func updateNoteTitle(id: UUID, newTitle: String) -> Bool {
        y2data_update_note_title(id.uuidString, newTitle)
    }

    // MARK: - Notebooks

    /// Retrieve all notebooks.
    static func getAllNotebooks() -> [[String: Any]] {
        guard let ptr = y2data_get_all_notebooks() else { return [] }
        defer { y2data_free_string(ptr) }
        return decodeJSONArray(ptr)
    }

    /// Create a new notebook.  Returns the UUID.
    @discardableResult
    static func addNotebook(name: String) -> UUID? {
        guard let ptr = y2data_add_notebook(name) else { return nil }
        defer { y2data_free_string(ptr) }
        return UUID(uuidString: String(cString: ptr))
    }

    /// Delete a notebook by UUID.
    @discardableResult
    static func deleteNotebook(id: UUID) -> Bool {
        y2data_delete_notebook(id.uuidString)
    }

    // MARK: - Sections

    /// Retrieve all sections.
    static func getAllSections() -> [[String: Any]] {
        guard let ptr = y2data_get_all_sections() else { return [] }
        defer { y2data_free_string(ptr) }
        return decodeJSONArray(ptr)
    }

    /// Create a new section in a notebook.  Returns the UUID.
    @discardableResult
    static func addSection(name: String, notebookID: UUID) -> UUID? {
        guard let ptr = y2data_add_section(name, notebookID.uuidString) else { return nil }
        defer { y2data_free_string(ptr) }
        return UUID(uuidString: String(cString: ptr))
    }

    // MARK: - Private helpers

    private static func decodeJSONArray(_ ptr: UnsafeMutablePointer<CChar>) -> [[String: Any]] {
        let str = String(cString: ptr)
        guard let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let array = obj as? [[String: Any]] else { return [] }
        return array
    }

    private static func decodeJSONObject(_ ptr: UnsafeMutablePointer<CChar>) -> [String: Any]? {
        let str = String(cString: ptr)
        guard let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }
}
