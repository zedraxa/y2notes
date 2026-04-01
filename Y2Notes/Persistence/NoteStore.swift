import Foundation
import Combine

// MARK: - Schema version

/// Current on-disk schema version.
/// Increment this constant and add a migration block in `load()` when a breaking store
/// change is required.  v1 is the first version that tracks sections, sortOrder, and templateID.
private let storeSchemaVersion = 1

/// Persistent store for notes, notebooks, and sections. Saves to the app's Documents directory
/// as JSON.  All mutations are performed on the main thread (via @Published / @MainActor).
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var notebooks: [Notebook] = []
    @Published private(set) var sections: [NotebookSection] = []

    private let notesURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_notes.json")
    }()

    private let notebooksURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_notebooks.json")
    }()

    private let sectionsURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_sections.json")
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
            notebookID: original.notebookID,
            sectionID: original.sectionID,
            sortOrder: original.sortOrder + 1,
            templateID: original.templateID
        )
        // Shift pages that follow the original so the copy slots in right after it.
        for i in notes.indices
        where notes[i].notebookID == original.notebookID
            && notes[i].sectionID == original.sectionID
            && notes[i].sortOrder > original.sortOrder
            && notes[i].id != id {
            notes[i].sortOrder += 1
        }
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
        notes[idx].sectionID = nil
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

    // MARK: - Page ordering

    /// Pages belonging to a section, sorted by `sortOrder` (then `modifiedAt` as tiebreaker).
    func pages(inSection sectionID: UUID) -> [Note] {
        notes
            .filter { $0.sectionID == sectionID }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.modifiedAt > $1.modifiedAt
                    : $0.sortOrder < $1.sortOrder
            }
    }

    /// Pages filed directly in a notebook with no section assignment.
    func unsectionedPages(inNotebook notebookID: UUID) -> [Note] {
        notes
            .filter { $0.notebookID == notebookID && $0.sectionID == nil }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.modifiedAt > $1.modifiedAt
                    : $0.sortOrder < $1.sortOrder
            }
    }

    /// Inserts a new page at an explicit position within a section (or at the notebook root
    /// when `sectionID` is nil).  Pages at or after `index` have their `sortOrder` shifted up.
    ///
    /// - Parameters:
    ///   - notebookID: The notebook the page belongs to.
    ///   - sectionID: Target section, or nil for notebook-level (no section).
    ///   - index: 0-based insertion position.  Pass `Int.max` to append at the end.
    ///   - templateID: Page template applied to the new page (default `"builtin.blank"`).
    @discardableResult
    func insertPage(
        inNotebook notebookID: UUID,
        sectionID: UUID? = nil,
        atIndex index: Int,
        templateID: String = "builtin.blank"
    ) -> Note {
        // Compact the existing order so there are no gaps, then shift.
        reindexPageSortOrders(notebookID: notebookID, sectionID: sectionID)
        let clampedIndex = min(index, pageCount(notebookID: notebookID, sectionID: sectionID))
        for i in notes.indices
        where notes[i].notebookID == notebookID
            && notes[i].sectionID == sectionID
            && notes[i].sortOrder >= clampedIndex {
            notes[i].sortOrder += 1
        }
        let note = Note(
            title: "New Page",
            notebookID: notebookID,
            sectionID: sectionID,
            sortOrder: clampedIndex,
            templateID: templateID
        )
        notes.insert(note, at: 0)
        save()
        return note
    }

    /// Moves a page to a different section (or the notebook root) at a specific position.
    ///
    /// - Parameters:
    ///   - id: The page to move.
    ///   - toSection: Target `NotebookSection` ID, or nil for the notebook root.
    ///   - atIndex: 0-based target position within the destination.
    func movePage(id: UUID, toSection targetSectionID: UUID?, atIndex targetIndex: Int) {
        guard let srcIdx = notes.firstIndex(where: { $0.id == id }) else { return }
        let notebookID   = notes[srcIdx].notebookID
        let fromSection  = notes[srcIdx].sectionID
        let fromOrder    = notes[srcIdx].sortOrder

        // Compact source so removal doesn't leave a gap.
        reindexPageSortOrders(notebookID: notebookID, sectionID: fromSection)

        // Remove from current position: close the gap.
        for i in notes.indices
        where notes[i].notebookID == notebookID
            && notes[i].sectionID == fromSection
            && notes[i].sortOrder > fromOrder
            && notes[i].id != id {
            notes[i].sortOrder -= 1
        }

        // Compact destination then open the insertion slot.
        reindexPageSortOrders(notebookID: notebookID, sectionID: targetSectionID)
        let clampedTarget = min(targetIndex, pageCount(notebookID: notebookID, sectionID: targetSectionID))
        for i in notes.indices
        where notes[i].notebookID == notebookID
            && notes[i].sectionID == targetSectionID
            && notes[i].sortOrder >= clampedTarget
            && notes[i].id != id {
            notes[i].sortOrder += 1
        }

        notes[srcIdx].sectionID = targetSectionID
        notes[srcIdx].sortOrder = clampedTarget
        notes[srcIdx].modifiedAt = Date()
        save()
    }

    /// Reorders pages within a section (or notebook root) using SwiftUI `List` drag offsets.
    ///
    /// - Parameters:
    ///   - sectionID: The section to reorder, or nil for the notebook root.
    ///   - notebookID: The owning notebook.
    ///   - fromOffsets: Source `IndexSet` as provided by `onMove`.
    ///   - toOffset: Destination offset as provided by `onMove`.
    func reorderPages(
        inSection sectionID: UUID?,
        ofNotebook notebookID: UUID,
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        var ordered: [Note]
        if let sid = sectionID {
            ordered = pages(inSection: sid)
        } else {
            ordered = unsectionedPages(inNotebook: notebookID)
        }
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for i in ordered.indices {
            if let idx = notes.firstIndex(where: { $0.id == ordered[i].id }) {
                notes[idx].sortOrder = i
            }
        }
        save()
    }

    // MARK: - Section CRUD

    /// Sections and dividers in a notebook, sorted by `sortOrder`.
    func sections(inNotebook notebookID: UUID) -> [NotebookSection] {
        sections
            .filter { $0.notebookID == notebookID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Adds a new named section at the end of a notebook's section list.
    @discardableResult
    func addSection(
        toNotebook notebookID: UUID,
        name: String,
        defaultTemplateID: String = "builtin.blank"
    ) -> NotebookSection {
        let nextOrder = nextSectionSortOrder(forNotebook: notebookID)
        let section = NotebookSection(
            notebookID: notebookID,
            name: name,
            kind: .section,
            sortOrder: nextOrder,
            defaultTemplateID: defaultTemplateID
        )
        sections.append(section)
        save()
        return section
    }

    /// Adds a visual divider row at the end of a notebook's section list.
    @discardableResult
    func addSectionDivider(toNotebook notebookID: UUID, label: String = "") -> NotebookSection {
        let nextOrder = nextSectionSortOrder(forNotebook: notebookID)
        let divider = NotebookSection(
            notebookID: notebookID,
            name: label,
            kind: .divider,
            sortOrder: nextOrder
        )
        sections.append(divider)
        save()
        return divider
    }

    func renameSection(id: UUID, name: String) {
        guard let idx = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[idx].name = name
        sections[idx].modifiedAt = Date()
        save()
    }

    /// Updates the default template used for new pages added to this section.
    func updateSectionDefaultTemplate(id: UUID, templateID: String) {
        guard let idx = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[idx].defaultTemplateID = templateID
        sections[idx].modifiedAt = Date()
        save()
    }

    /// Deletes a section (or divider).
    ///
    /// - Parameter movePagesToNotebook: When true (default), pages belonging to the section
    ///   are kept but their `sectionID` is cleared (notebook-level).  When false, they are
    ///   deleted along with the section.
    func deleteSection(id: UUID, movePagesToNotebook: Bool = true) {
        if movePagesToNotebook {
            for i in notes.indices where notes[i].sectionID == id {
                notes[i].sectionID = nil
            }
        } else {
            notes.removeAll { $0.sectionID == id }
        }
        sections.removeAll { $0.id == id }
        save()
    }

    /// Reorders sections within a notebook using SwiftUI `List` drag offsets.
    func reorderSections(
        inNotebook notebookID: UUID,
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        var ordered = sections(inNotebook: notebookID)
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for i in ordered.indices {
            if let idx = sections.firstIndex(where: { $0.id == ordered[i].id }) {
                sections[idx].sortOrder = i
            }
        }
        save()
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

    /// Creates a notebook together with an optional default section.
    ///
    /// This is the preferred entry point from the notebook creation wizard.
    ///
    /// - Parameters:
    ///   - name: Notebook display name (will be trimmed; "Untitled" if empty).
    ///   - cover: Cover colour theme.
    ///   - defaultTemplateID: Template applied by default to new pages in the first section.
    ///   - addDefaultSection: When true a section named "Notes" is created automatically.
    @discardableResult
    func createNotebook(
        name: String,
        cover: NotebookCover = .ocean,
        defaultTemplateID: String = "builtin.blank",
        addDefaultSection: Bool = true
    ) -> Notebook {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nb = addNotebook(name: trimmed.isEmpty ? "Untitled" : trimmed, cover: cover)
        if addDefaultSection {
            addSection(toNotebook: nb.id, name: "Notes", defaultTemplateID: defaultTemplateID)
        }
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

    /// Deletes a notebook, its sections, and unfiles all notes that belonged to it.
    func deleteNotebook(id: UUID) {
        for i in notes.indices where notes[i].notebookID == id {
            notes[i].notebookID = nil
            notes[i].sectionID = nil
        }
        sections.removeAll { $0.notebookID == id }
        notebooks.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    func save() {
        saveJSON(notes,     to: notesURL)
        saveJSON(notebooks, to: notebooksURL)
        saveJSON(sections,  to: sectionsURL)
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
        notes     = loadJSON([Note].self,            from: notesURL)     ?? []
        notebooks = loadJSON([Notebook].self,        from: notebooksURL) ?? []
        sections  = loadJSON([NotebookSection].self, from: sectionsURL)  ?? []
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

    // MARK: - Private helpers

    private func nextSectionSortOrder(forNotebook notebookID: UUID) -> Int {
        (sections.filter { $0.notebookID == notebookID }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func pageCount(notebookID: UUID, sectionID: UUID?) -> Int {
        notes.filter { $0.notebookID == notebookID && $0.sectionID == sectionID }.count
    }

    /// Renumbers `sortOrder` values for pages in a given context to be 0-based with no gaps.
    private func reindexPageSortOrders(notebookID: UUID, sectionID: UUID?) {
        let ordered = notes
            .filter { $0.notebookID == notebookID && $0.sectionID == sectionID }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.modifiedAt > $1.modifiedAt
                    : $0.sortOrder < $1.sortOrder
            }
        for (i, page) in ordered.enumerated() {
            if let idx = notes.firstIndex(where: { $0.id == page.id }) {
                notes[idx].sortOrder = i
            }
        }
    }
}
