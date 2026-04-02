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

// MARK: - NoteStore / Schema version

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
    @Published private(set) var studySets: [StudySet] = []
    @Published private(set) var studyCards: [StudyCard] = []
    @Published private(set) var cardProgress: [StudyCardProgress] = []
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

    private let sectionsURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_sections.json")
    }()

    /// True when in-memory state has been mutated but not yet flushed to disk.
    private var isDirty = false
    /// Repeating timer that autosaves dirty state approximately every 30 s.
    private var autosaveTimer: Timer?

    init() {
        load()
        loadStudy()
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

    // MARK: - Persistence public API

    /// Marks state dirty-clean and immediately flushes all data files to disk.
    func save() {
        isDirty = false
        flushToDisk()
    }

    // MARK: - Persistence internals

    /// Writes all data files atomically and updates `saveState`.
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
        do {
            let data = try JSONEncoder().encode(sections)
            try writeAtomically(data, to: sectionsURL)
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
    fileprivate func writeAtomically(_ data: Data, to url: URL) throws {
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
        notes     = loadJSON([Note].self,            from: notesURL)     ?? []
        notebooks = loadJSON([Notebook].self,        from: notebooksURL) ?? []
        sections  = loadJSON([NotebookSection].self, from: sectionsURL)  ?? []
    }

    /// Decodes `type` from `url`. On missing or corrupt primary file, falls back to
    /// the `.bak` sibling created by `writeAtomically` so interrupted writes are recoverable.
    fileprivate func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
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

    // MARK: - Typed text

    /// Updates the keyboard-entered typed text for a note.
    /// This is the plain-text field used by `SearchService` and the in-document find bar.
    func updateTypedText(for noteID: UUID, text: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].typedText = text
        notes[idx].modifiedAt = Date()
        isDirty = true
    }

    /// Updates the OCR-recognised text for a note.
    /// Called by a future handwriting-OCR agent after processing `drawingData`.
    func updateOCRText(for noteID: UUID, text: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].ocrText = text
        notes[idx].modifiedAt = Date()
        isDirty = true
    }
}

// MARK: - Study set & flashcard persistence

extension NoteStore {

    // MARK: StudySet CRUD

    @discardableResult
    func addStudySet(title: String, notebookID: UUID? = nil) -> StudySet {
        let set = StudySet(title: title, notebookID: notebookID)
        studySets.insert(set, at: 0)
        saveStudy()
        return set
    }

    func renameStudySet(id: UUID, title: String) {
        guard let idx = studySets.firstIndex(where: { $0.id == id }) else { return }
        studySets[idx].title = title
        studySets[idx].modifiedAt = Date()
        saveStudy()
    }

    func deleteStudySet(id: UUID) {
        let cardIDs = studyCards.filter { $0.setID == id }.map(\.id)
        cardProgress.removeAll { cardIDs.contains($0.cardID) }
        studyCards.removeAll { $0.setID == id }
        studySets.removeAll { $0.id == id }
        saveStudy()
    }

    // MARK: StudyCard CRUD

    @discardableResult
    func addCard(toSet setID: UUID, front: String, back: String, noteID: UUID? = nil, tags: [String] = []) -> StudyCard {
        let card = StudyCard(setID: setID, noteID: noteID, front: front, back: back, tags: tags)
        studyCards.insert(card, at: 0)
        // Seed a fresh progress record for this card.
        cardProgress.append(StudyCardProgress(cardID: card.id))
        saveStudy()
        return card
    }

    func updateCard(id: UUID, front: String, back: String) {
        guard let idx = studyCards.firstIndex(where: { $0.id == id }) else { return }
        studyCards[idx].front = front
        studyCards[idx].back = back
        studyCards[idx].modifiedAt = Date()
        saveStudy()
    }

    func deleteCard(id: UUID) {
        cardProgress.removeAll { $0.cardID == id }
        studyCards.removeAll { $0.id == id }
        saveStudy()
    }

    // MARK: Spaced repetition

    /// Records a review result for `cardID` and advances its scheduling state.
    func recordReview(cardID: UUID, rating: ReviewRating, reviewedAt: Date = Date()) {
        if let idx = cardProgress.firstIndex(where: { $0.cardID == cardID }) {
            cardProgress[idx] = cardProgress[idx].applying(rating: rating, reviewedAt: reviewedAt)
        } else {
            // Safety: create progress record if missing (shouldn't normally happen).
            var progress = StudyCardProgress(cardID: cardID)
            progress = progress.applying(rating: rating, reviewedAt: reviewedAt)
            cardProgress.append(progress)
        }
        saveStudy()
    }

    // MARK: Study helpers

    /// Cards in a study set, sorted by due date ascending (most overdue first).
    func cards(inSet setID: UUID) -> [StudyCard] {
        let cards = studyCards.filter { $0.setID == setID }
        return cards.sorted { a, b in
            let pa = progress(for: a.id)
            let pb = progress(for: b.id)
            return pa.dueDate < pb.dueDate
        }
    }

    /// Cards due today or overdue in a study set.
    func dueCards(inSet setID: UUID) -> [StudyCard] {
        cards(inSet: setID).filter { progress(for: $0.id).isDueToday }
    }

    /// Progress record for a card, or a fresh default if not yet reviewed.
    func progress(for cardID: UUID) -> StudyCardProgress {
        cardProgress.first { $0.cardID == cardID } ?? StudyCardProgress(cardID: cardID)
    }

    // MARK: Study persistence internals

    /// URL for the combined study data file.
    private var studyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("y2notes_study.json")
    }

    /// Persists study sets, cards, and progress to disk.
    private func saveStudy() {
        let payload = StudyPayload(
            studySets: studySets,
            studyCards: studyCards,
            cardProgress: cardProgress
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? writeAtomically(data, to: studyURL)
        }
    }

    /// Loads study data from disk into the published properties.
    func loadStudy() {
        guard let payload = loadJSON(StudyPayload.self, from: studyURL) else { return }
        studySets     = payload.studySets
        studyCards    = payload.studyCards
        cardProgress  = payload.cardProgress
    }

    /// Private container used for encoding/decoding study data as a single JSON file.
    private struct StudyPayload: Codable {
        var studySets:    [StudySet]
        var studyCards:   [StudyCard]
        var cardProgress: [StudyCardProgress]
    }
}

