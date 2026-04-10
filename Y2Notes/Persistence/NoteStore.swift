import Foundation
import Combine
import UIKit
import os

// swiftlint:disable file_length

private let storeLogger = Logger(subsystem: "com.y2notes", category: "NoteStore")

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
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var notebooks: [Notebook] = []
    @Published private(set) var sections: [NotebookSection] = []
    @Published private(set) var studySets: [StudySet] = []
    @Published private(set) var studyCards: [StudyCard] = []
    @Published private(set) var cardProgress: [StudyCardProgress] = []
    @Published private(set) var reviewHistory: [StudyReviewEntry] = []
    @Published private(set) var studyTestQuestions: [StudyTestQuestion] = []
    @Published private(set) var studyTestAttempts: [StudyTestAttempt] = []
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
    /// Per-note set of page indices that have been mutated since the last snapshot.
    /// Used by `SnapshotStore` to capture only changed pages.
    private var dirtyPages: [UUID: Set<Int>] = [:]
    /// The note ID currently being actively edited (set by the editor view).
    /// Used to apply the faster 5-second autosave debounce.
    var activeNoteID: UUID?
    /// Repeating timer that autosaves dirty state approximately every 30 s.
    private var autosaveTimer: Timer?
    /// Per-note debounced autosave timer (5 s) for the actively edited note.
    private var noteAutosaveTimer: Timer?

    /// Per-note OCR debounce timers.  A timer is started (or restarted) each time a page
    /// drawing changes, and fires 4 seconds later to trigger a background Vision pass.
    private var ocrTimers: [UUID: Timer] = [:]

    /// Per-note PDF regeneration debounce timers.  Fires 2 seconds after the last drawing
    /// change to composite page backgrounds + strokes into the backing PDF file.
    private var pdfRegenTimers: [UUID: Timer] = [:]
    private static let pdfRegenerationDebounceInterval: TimeInterval = 2.0

    /// Optional persistence driver. When set, the store reads/writes through this
    /// driver instead of per-file JSON.  See ``SQLitePersistenceDriver``.
    var persistenceDriver: PersistenceDriver?

    // Logical keys used by PersistenceDriver.
    private static let notesKey = "y2notes_notes"
    private static let notebooksKey = "y2notes_notebooks"
    private static let sectionsKey = "y2notes_sections"
    private static let studyKey = "y2notes_study"

    // MARK: - Last page position (notebook illusion — object permanence)

    /// Remembers the last viewed flat-page index per notebook so reopening
    /// a notebook returns the user to where they left off.
    /// Cached in memory; persisted to UserDefaults on write.
    private static let lastPageKey = "notebookLastPage"
    private lazy var lastPageCache: [String: Int] = {
        UserDefaults.standard.dictionary(forKey: Self.lastPageKey) as? [String: Int] ?? [:]
    }()

    func lastPageIndex(for notebookID: UUID) -> Int {
        lastPageCache[notebookID.uuidString] ?? 0
    }

    func setLastPageIndex(_ index: Int, for notebookID: UUID) {
        lastPageCache[notebookID.uuidString] = index
        UserDefaults.standard.set(lastPageCache, forKey: Self.lastPageKey)
    }

    /// - Parameter persistenceDriver: Optional storage backend.
    ///   When provided, `load()` reads from the driver first and
    ///   migrates legacy JSON files on the initial launch.
    init(persistenceDriver: PersistenceDriver? = nil) {
        self.persistenceDriver = persistenceDriver
        load()
        loadStudy()
        ensurePDFsForLegacyNotes()
        startAutosaveTimer()
        setupLifecycleObservers()
        writeCrashFlag()
        checkCrashRecovery()
        // Run snapshot compaction on background queue at launch.
        PerformanceConstraints.storageQueue.async {
            SnapshotStore.shared.runCompaction()
        }
    }

    deinit {
        autosaveTimer?.invalidate()
        noteAutosaveTimer?.invalidate()
        ocrTimers.values.forEach { $0.invalidate() }
        pdfRegenTimers.values.forEach { $0.invalidate() }
        NotificationCenter.default.removeObserver(self)
        removeCrashFlag()
    }

    // MARK: - Autosave / lifecycle

    private func startAutosaveTimer() {
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.isDirty else { return }
            self.flushToDisk()
        }
        autosaveTimer?.tolerance = 5
    }

    /// Schedules a 5-second debounced autosave for the actively edited note.
    /// Called each time a per-note mutation marks `isDirty`.
    private func scheduleNoteAutosave() {
        noteAutosaveTimer?.invalidate()
        noteAutosaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, self.isDirty else { return }
            self.flushToDisk()
        }
        noteAutosaveTimer?.tolerance = 1
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
        flushToDisk(trigger: .lifecycle)
    }

    // MARK: - Crash detection

    private nonisolated static var crashFlagURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("session_active.flag")
    }

    private func writeCrashFlag() {
        let data = Data("active".utf8)
        try? data.write(to: Self.crashFlagURL, options: .atomic)
    }

    private nonisolated func removeCrashFlag() {
        try? FileManager.default.removeItem(at: Self.crashFlagURL)
    }

    /// Detects if the previous session ended in a crash (flag file still present).
    private func checkCrashRecovery() {
        let flagURL = Self.crashFlagURL
        guard FileManager.default.fileExists(atPath: flagURL.path) else { return }
        // Previous session did not exit cleanly. Data is safe due to atomic writes
        // and rolling backups. Log for diagnostics.
        storeLogger.warning("Crash detected — previous session did not exit cleanly. Data recovered from last save.")
    }

    // MARK: - Note CRUD

    /// Creates a new note, optionally filing it into a notebook and with per-note paper settings.
    /// Generates a backing PDF template so the note is PDF-based from the start.
    @discardableResult
    func addNote(
        inNotebook notebookID: UUID? = nil,
        pageType: PageType? = nil,
        canvasMode: CanvasMode? = nil
    ) -> Note {
        // Generate the template PDF before creating the note so `pdfFilename` is set immediately.
        let effectiveType = pageType
            ?? notebooks.first(where: { $0.id == notebookID })?.pageType
            ?? .blank
        let pdfFilename = NotePDFGenerator.generateTemplatePDF(
            pageCount: 1,
            backgroundColor: .white,
            pageTypes: [effectiveType]
        )
        let isInfinite = canvasMode == .infinite
        let noteTitle = isInfinite
            ? "Canvas \(notes.count + 1)"
            : "Note \(notes.count + 1)"
        let note = Note(
            title: noteTitle,
            notebookID: notebookID,
            pageType: pageType,
            canvasMode: canvasMode,
            pdfFilename: pdfFilename
        )
        notes.insert(note, at: 0)
        save()
        return note
    }

    /// Creates a companion note for an imported PDF record and returns it.
    ///
    /// The note is pre-titled with the PDF's title and has `linkedPDFID` set so the editor
    /// can surface a quick-open action for the source file.
    @discardableResult
    func addNote(forPDF record: PDFNoteRecord) -> Note {
        let pdfFilename = NotePDFGenerator.generateTemplatePDF(
            pageCount: 1,
            backgroundColor: .white,
            pageTypes: [.blank]
        )
        let note = Note(
            title: record.title,
            pdfFilename: pdfFilename,
            linkedPDFID: record.id
        )
        notes.insert(note, at: 0)
        save()
        return note
    }

    /// Creates a companion note for an imported document and returns it.
    ///
    /// The note is pre-titled with the document's display name and has `linkedDocumentID` set
    /// so the editor can surface a quick-open action for the source file.
    @discardableResult
    func addNote(forDocument doc: ImportedDocument) -> Note {
        let pdfFilename = NotePDFGenerator.generateTemplatePDF(
            pageCount: 1,
            backgroundColor: .white,
            pageTypes: [.blank]
        )
        let note = Note(
            title: doc.displayName,
            pdfFilename: pdfFilename,
            linkedDocumentID: doc.id
        )
        notes.insert(note, at: 0)
        save()
        return note
    }

    // MARK: - Import-linked note queries

    /// Returns all notes that are linked to the given PDF record.
    func notes(forPDF pdfID: UUID) -> [Note] {
        notes.filter { $0.linkedPDFID == pdfID }
    }

    /// Returns all notes that are linked to the given imported document.
    func notes(forDocument docID: UUID) -> [Note] {
        notes.filter { $0.linkedDocumentID == docID }
    }

    /// Returns true if a companion note already exists for the given PDF.
    func hasCompanionNote(forPDF pdfID: UUID) -> Bool {
        notes.contains { $0.linkedPDFID == pdfID }
    }

    /// Returns true if a companion note already exists for the given document.
    func hasCompanionNote(forDocument docID: UUID) -> Bool {
        notes.contains { $0.linkedDocumentID == docID }
    }

    /// Removes the companion-note link from a note without deleting the note itself.
    func unlinkCompanionNote(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].linkedPDFID = nil
        notes[idx].linkedDocumentID = nil
        save()
    }

    /// Returns all import-linked notes whose source PDF/document is no longer present.
    /// The caller must supply the set of live PDF and document IDs.
    func orphanedImportNotes(livePDFIDs: Set<UUID>, liveDocumentIDs: Set<UUID>) -> [Note] {
        notes.filter {
            if let pdfID = $0.linkedPDFID { return !livePDFIDs.contains(pdfID) }
            if let docID = $0.linkedDocumentID { return !liveDocumentIDs.contains(docID) }
            return false
        }
    }

    /// Removes companion-note links from notes whose source is no longer present.
    func removeOrphanedImportLinks(livePDFIDs: Set<UUID>, liveDocumentIDs: Set<UUID>) {
        let orphans = orphanedImportNotes(livePDFIDs: livePDFIDs, liveDocumentIDs: liveDocumentIDs)
        for orphan in orphans {
            guard let idx = notes.firstIndex(where: { $0.id == orphan.id }) else { continue }
            notes[idx].linkedPDFID = nil
            notes[idx].linkedDocumentID = nil
        }
        if !orphans.isEmpty { save() }
    }

    func deleteNotes(at offsets: IndexSet) {
        for i in offsets {
            createPreDestructiveSnapshot(for: notes[i].id)
            if let filename = notes[i].pdfFilename {
                NotePDFGenerator.deletePDF(filename: filename)
            }
            MediaFileManager.shared.deleteMediaForNote(noteID: notes[i].id)
        }
        notes.remove(atOffsets: offsets)
        save()
    }

    /// Deletes notes whose IDs are in `ids`. Safe when caller holds a filtered/sorted view.
    func deleteNotes(ids: [UUID]) {
        for note in notes where ids.contains(note.id) {
            createPreDestructiveSnapshot(for: note.id)
            if let filename = note.pdfFilename {
                NotePDFGenerator.deletePDF(filename: filename)
            }
            MediaFileManager.shared.deleteMediaForNote(noteID: note.id)
        }
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
        notes[idx].modifiedAt = Date()
        save()
    }

    /// Sets or clears the per-note page type override.
    /// Pass nil to inherit from the notebook (or fall back to `.blank` for unfiled notes).
    func updatePageType(for noteID: UUID, pageType: PageType?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].pageType = pageType
        notes[idx].modifiedAt = Date()
        save()
    }

    /// Sets the ruling override for a single page within a note.
    /// Pass nil to clear the per-page override and inherit from the note-level setting.
    func updatePageType(for noteID: UUID, pageIndex: Int, pageType: PageType?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              notes[idx].pages.indices.contains(pageIndex) else { return }
        // Grow pageTypes to match pages count if needed (backward compat with old notes)
        while notes[idx].pageTypes.count < notes[idx].pages.count {
            notes[idx].pageTypes.append(nil)
        }
        notes[idx].pageTypes[pageIndex] = pageType
        notes[idx].modifiedAt = Date()
        save()
    }

    /// Sets or clears the background colour for a single page.
    /// Pass nil to inherit from the theme.  Colour is stored as `[r, g, b, a]` in 0…1.
    func updatePageColor(for noteID: UUID, pageIndex: Int, color: UIColor?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              notes[idx].pages.indices.contains(pageIndex) else { return }
        while notes[idx].pageColors.count < notes[idx].pages.count {
            notes[idx].pageColors.append(nil)
        }
        if let color {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            notes[idx].pageColors[pageIndex] = [Double(r), Double(g), Double(b), Double(a)]
        } else {
            notes[idx].pageColors[pageIndex] = nil
        }
        notes[idx].modifiedAt = Date()
        save()
    }

    func updateDrawing(for noteID: UUID, data: Data) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].drawingData = data
        notes[idx].modifiedAt = Date()
        // Mark dirty so autosave timer and willResignActive flush pick this up.
        // The canvas coordinator owns the debounced 0.8 s save trigger.
        isDirty = true
        dirtyPages[noteID, default: []].insert(0)
        scheduleNoteAutosave()
        schedulePDFRegeneration(for: noteID)
    }

    /// Updates drawing data for a specific page within a multi-page note.
    func updateDrawing(for noteID: UUID, pageIndex: Int, data: Data) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        guard pageIndex >= 0 && pageIndex < notes[idx].pages.count else { return }
        notes[idx].pages[pageIndex] = data
        notes[idx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(pageIndex)
        scheduleNoteAutosave()
        scheduleOCR(for: noteID)
        schedulePDFRegeneration(for: noteID)
    }

    /// Updates the sticker instances for a specific page.
    func updateStickers(for noteID: UUID, pageIndex: Int, stickers: [StickerInstance]) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        // Ensure stickerLayers array is sized to match pages
        while notes[idx].stickerLayers.count < notes[idx].pages.count {
            notes[idx].stickerLayers.append(nil)
        }
        guard pageIndex >= 0 && pageIndex < notes[idx].stickerLayers.count else { return }
        notes[idx].stickerLayers[pageIndex] = stickers.isEmpty ? nil : stickers
        notes[idx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(pageIndex)
        scheduleNoteAutosave()
    }
    /// Updates the shape objects for a specific page.
    func updateShapes(for noteID: UUID, pageIndex: Int, shapes: [ShapeInstance]) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        // Ensure shapeLayers array is sized to match pages
        while notes[idx].shapeLayers.count < notes[idx].pages.count {
            notes[idx].shapeLayers.append(nil)
        }
        guard pageIndex >= 0 && pageIndex < notes[idx].shapeLayers.count else { return }
        notes[idx].shapeLayers[pageIndex] = shapes.isEmpty ? nil : shapes
        notes[idx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(pageIndex)
        scheduleNoteAutosave()
    }

    func updateAttachments(for noteID: UUID, pageIndex: Int, attachments: [AttachmentObject]) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        // Ensure attachmentLayers array is sized to match pages
        while notes[idx].attachmentLayers.count < notes[idx].pages.count {
            notes[idx].attachmentLayers.append(nil)
        }
        guard pageIndex >= 0 && pageIndex < notes[idx].attachmentLayers.count else { return }
        notes[idx].attachmentLayers[pageIndex] = attachments.isEmpty ? nil : attachments
        notes[idx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(pageIndex)
        scheduleNoteAutosave()
    }

    /// Updates the widget instances for a specific page.
    func updateWidgets(for noteID: UUID, pageIndex: Int, widgets: [NoteWidget]) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        // Ensure widgetLayers array is sized to match pages
        while notes[idx].widgetLayers.count < notes[idx].pages.count {
            notes[idx].widgetLayers.append(nil)
        }
        guard pageIndex >= 0 && pageIndex < notes[idx].widgetLayers.count else { return }
        notes[idx].widgetLayers[pageIndex] = widgets.isEmpty ? nil : widgets
        notes[idx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(pageIndex)
        scheduleNoteAutosave()
    }

    /// Updates the text objects for a specific page.
    func updateTextObjects(for noteID: UUID, pageIndex: Int, textObjects: [TextObject]) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        // Ensure textLayers array is sized to match pages
        while notes[idx].textLayers.count < notes[idx].pages.count {
            notes[idx].textLayers.append(nil)
        }
        guard pageIndex >= 0 && pageIndex < notes[idx].textLayers.count else { return }
        notes[idx].textLayers[pageIndex] = textObjects.isEmpty ? nil : textObjects
        notes[idx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(pageIndex)
        scheduleNoteAutosave()
    }

    // MARK: - Expansion Region Updates

    /// Replaces the full set of expansion regions for a note.
    /// Used when creating, resizing, collapsing, or deleting expansion regions.
    func updateExpansionRegions(for noteID: UUID, regions: [PageRegion]) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].expansionRegions = regions
        notes[idx].modifiedAt = Date()
        isDirty = true
        scheduleNoteAutosave()
    }

    /// Updates a single expansion region identified by its ID.
    /// If no region with the given ID exists, the update is silently ignored.
    func updateExpansionRegion(for noteID: UUID, region: PageRegion) {
        guard let noteIdx = notes.firstIndex(where: { $0.id == noteID }),
              let regionIdx = notes[noteIdx].expansionRegions.firstIndex(where: { $0.id == region.id })
        else { return }
        notes[noteIdx].expansionRegions[regionIdx] = region
        notes[noteIdx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(region.pageIndex)
        scheduleNoteAutosave()
    }

    /// Adds a new expansion region to a note.
    func addExpansionRegion(to noteID: UUID, region: PageRegion) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].expansionRegions.append(region)
        notes[idx].modifiedAt = Date()
        isDirty = true
        dirtyPages[noteID, default: []].insert(region.pageIndex)
        scheduleNoteAutosave()
    }

    /// Removes an expansion region by its ID, permanently deleting all contained content.
    func removeExpansionRegion(from noteID: UUID, regionID: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].expansionRegions.removeAll { $0.id == regionID }
        notes[idx].modifiedAt = Date()
        isDirty = true
        scheduleNoteAutosave()
    }

    /// Appends a blank page to the note and returns the new page index.
    @discardableResult
    func addPage(to noteID: UUID) -> Int? {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return nil }
        notes[idx].pages.append(Data())
        // Keep pageTypes and pageColors in sync with pages.
        notes[idx].pageTypes.append(nil)   // nil = inherit from note-level pageType
        notes[idx].pageColors.append(nil)  // nil = inherit from theme
        notes[idx].stickerLayers.append(nil)  // nil = no stickers
        notes[idx].shapeLayers.append(nil)    // nil = no shapes
        notes[idx].attachmentLayers.append(nil) // nil = no attachments
        notes[idx].widgetLayers.append(nil) // nil = no widgets
        notes[idx].modifiedAt = Date()
        isDirty = true
        schedulePDFRegeneration(for: noteID)
        return notes[idx].pages.count - 1
    }

    /// Removes a page at the given index.  A note must always keep at least
    /// one page — the call is a no-op when only one page remains.
    func removePage(from noteID: UUID, at pageIndex: Int) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              notes[idx].pages.count > 1,
              notes[idx].pages.indices.contains(pageIndex) else { return }
        notes[idx].pages.remove(at: pageIndex)
        if notes[idx].pageTypes.indices.contains(pageIndex) {
            notes[idx].pageTypes.remove(at: pageIndex)
        }
        if notes[idx].pageColors.indices.contains(pageIndex) {
            notes[idx].pageColors.remove(at: pageIndex)
        }
        if notes[idx].stickerLayers.indices.contains(pageIndex) {
            notes[idx].stickerLayers.remove(at: pageIndex)
        }
        if notes[idx].shapeLayers.indices.contains(pageIndex) {
            notes[idx].shapeLayers.remove(at: pageIndex)
        }
        if notes[idx].attachmentLayers.indices.contains(pageIndex) {
            notes[idx].attachmentLayers.remove(at: pageIndex)
        }
        if notes[idx].widgetLayers.indices.contains(pageIndex) {
            notes[idx].widgetLayers.remove(at: pageIndex)
        }
        // Remove expansion regions attached to the deleted page and adjust
        // pageIndex for regions on subsequent pages.
        notes[idx].expansionRegions.removeAll { $0.pageIndex == pageIndex }
        for i in notes[idx].expansionRegions.indices
        where notes[idx].expansionRegions[i].pageIndex > pageIndex {
            notes[idx].expansionRegions[i].pageIndex -= 1
        }
        notes[idx].modifiedAt = Date()
        isDirty = true
        schedulePDFRegeneration(for: noteID)
    }

    /// Reorders pages within a note by moving a page from one index to another.
    func reorderPageInNote(noteID: UUID, from source: Int, to destination: Int) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              notes[idx].pages.indices.contains(source),
              destination >= 0, destination <= notes[idx].pages.count else { return }
        let page = notes[idx].pages.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        notes[idx].pages.insert(page, at: min(insertAt, notes[idx].pages.count))
        // Keep per-page types in sync during reorder
        if notes[idx].pageTypes.indices.contains(source) {
            let pt = notes[idx].pageTypes.remove(at: source)
            let ptInsert = min(insertAt, notes[idx].pageTypes.count)
            notes[idx].pageTypes.insert(pt, at: ptInsert)
        }
        if notes[idx].attachmentLayers.indices.contains(source) {
            let al = notes[idx].attachmentLayers.remove(at: source)
            let alInsert = min(insertAt, notes[idx].attachmentLayers.count)
            notes[idx].attachmentLayers.insert(al, at: alInsert)
        }
        // Remap expansion region pageIndex values to reflect the new page order.
        for i in notes[idx].expansionRegions.indices {
            let pi = notes[idx].expansionRegions[i].pageIndex
            if pi == source {
                notes[idx].expansionRegions[i].pageIndex = insertAt
            } else if source < insertAt {
                // Page moved forward: pages in (source, insertAt] shift back by 1
                if pi > source && pi <= insertAt {
                    notes[idx].expansionRegions[i].pageIndex -= 1
                }
            } else {
                // Page moved backward: pages in [insertAt, source) shift forward by 1
                if pi >= insertAt && pi < source {
                    notes[idx].expansionRegions[i].pageIndex += 1
                }
            }
        }
        notes[idx].modifiedAt = Date()
        isDirty = true
        schedulePDFRegeneration(for: noteID)
    }

    /// Duplicates a page within a note, inserting the copy immediately after the original.
    @discardableResult
    func duplicatePageInNote(noteID: UUID, pageIndex: Int) -> Int? {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              notes[idx].pages.indices.contains(pageIndex) else { return nil }
        let copy = notes[idx].pages[pageIndex]
        let insertIndex = pageIndex + 1
        notes[idx].pages.insert(copy, at: insertIndex)
        // Duplicate the per-page type as well so the copy inherits the same ruling.
        let ptCopy: PageType? = notes[idx].pageTypes.indices.contains(pageIndex)
            ? notes[idx].pageTypes[pageIndex] : nil
        // Grow pageTypes to match pages length (minus 1 — the new page hasn't been counted yet).
        // This handles old notes that were saved before per-page pageTypes existed.
        while notes[idx].pageTypes.count < notes[idx].pages.count - 1 {
            notes[idx].pageTypes.append(nil)
        }
        notes[idx].pageTypes.insert(ptCopy, at: min(insertIndex, notes[idx].pageTypes.count))
        // Shift expansion regions on pages after the insertion point,
        // then duplicate expansion regions from the source page for the copy.
        for i in notes[idx].expansionRegions.indices
        where notes[idx].expansionRegions[i].pageIndex >= insertIndex {
            notes[idx].expansionRegions[i].pageIndex += 1
        }
        let sourceRegions = notes[idx].expansionRegions.filter { $0.pageIndex == pageIndex }
        for region in sourceRegions {
            let dup = PageRegion(
                pageIndex: insertIndex,
                edge: region.edge,
                size: region.size,
                drawingData: region.drawingData,
                widgetLayers: region.widgetLayers,
                stickerLayers: region.stickerLayers,
                shapeLayers: region.shapeLayers,
                attachmentLayers: region.attachmentLayers,
                isCollapsed: region.isCollapsed,
                version: 0
            )
            notes[idx].expansionRegions.append(dup)
        }
        notes[idx].modifiedAt = Date()
        isDirty = true
        return insertIndex
    }

    /// Creates a copy of the note inserted directly after the original.
    @discardableResult
    func duplicateNote(id: UUID) -> Note? {
        guard let original = notes.first(where: { $0.id == id }) else { return nil }
        // Duplicate expansion regions with new IDs to avoid ID collisions.
        let copiedRegions = original.expansionRegions.map { region in
            PageRegion(
                pageIndex: region.pageIndex,
                edge: region.edge,
                size: region.size,
                drawingData: region.drawingData,
                widgetLayers: region.widgetLayers,
                stickerLayers: region.stickerLayers,
                shapeLayers: region.shapeLayers,
                attachmentLayers: region.attachmentLayers,
                isCollapsed: region.isCollapsed,
                version: 0
            )
        }
        let copy = Note(
            title: original.title.isEmpty ? "Copy" : "\(original.title) (Copy)",
            createdAt: Date(),
            modifiedAt: Date(),
            pages: original.pages,
            isFavorited: false,
            notebookID: original.notebookID,
            sectionID: original.sectionID,
            sortOrder: original.sortOrder + 1,
            templateID: original.templateID,
            pageType: original.pageType,
            expansionRegions: copiedRegions
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

    /// All notes that are linked to a PDF or imported document (companion notes).
    var importLinkedNotes: [Note] {
        notes.filter { $0.linkedPDFID != nil || $0.linkedDocumentID != nil }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Companion notes (PDF / Document)

    /// Creates a new companion note linked to a PDF record.
    @discardableResult
    func addNote(forPDF pdfID: UUID, title: String) -> Note {
        let pdfFilename = NotePDFGenerator.generateTemplatePDF(
            pageCount: 1, backgroundColor: .white, pageTypes: [.blank]
        )
        let note = Note(
            title: title,
            pdfFilename: pdfFilename,
            linkedPDFID: pdfID
        )
        notes.insert(note, at: 0)
        save()
        return note
    }

    /// Creates a new companion note linked to an imported document.
    @discardableResult
    func addNote(forDocument documentID: UUID, title: String) -> Note {
        let pdfFilename = NotePDFGenerator.generateTemplatePDF(
            pageCount: 1, backgroundColor: .white, pageTypes: [.blank]
        )
        let note = Note(
            title: title,
            pdfFilename: pdfFilename,
            linkedDocumentID: documentID
        )
        notes.insert(note, at: 0)
        save()
        return note
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
        guard let srcIdx = notes.firstIndex(where: { $0.id == id }),
              let notebookID = notes[srcIdx].notebookID else { return }
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
        defaultTemplateID: String = "builtin.blank",
        colorTag: SectionColorTag = .none
    ) -> NotebookSection {
        let nextOrder = nextSectionSortOrder(forNotebook: notebookID)
        let section = NotebookSection(
            notebookID: notebookID,
            name: name,
            kind: .section,
            sortOrder: nextOrder,
            defaultTemplateID: defaultTemplateID,
            colorTag: colorTag
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
        description: String = "",
        cover: NotebookCover = .ocean,
        pageType: PageType = .ruled,
        pageSize: PageSize = .letter,
        orientation: PageOrientation = .portrait,
        defaultTheme: AppTheme? = nil,
        customCoverData: Data? = nil
    ) -> Notebook {
        let nb = Notebook(
            name: name,
            description: description,
            cover: cover,
            pageType: pageType,
            pageSize: pageSize,
            orientation: orientation,
            defaultTheme: defaultTheme,
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

    func updateNotebookDescription(id: UUID, description: String) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].description = description
        notebooks[idx].modifiedAt = Date()
        save()
    }

    func updateNotebookCover(id: UUID, cover: NotebookCover) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].cover = cover
        notebooks[idx].modifiedAt = Date()
        save()
    }

    func updateNotebookLastOpened(id: UUID) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].lastOpenedAt = Date()
        save()
    }

    func toggleNotebookPin(id: UUID) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].isPinned.toggle()
        notebooks[idx].modifiedAt = Date()
        save()
    }

    func toggleNotebookLock(id: UUID) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].isLocked.toggle()
        notebooks[idx].modifiedAt = Date()
        save()
    }

    @discardableResult
    func duplicateNotebook(id: UUID) -> Notebook? {
        guard let original = notebooks.first(where: { $0.id == id }) else { return nil }
        let copy = addNotebook(
            name: "\(original.name) (Copy)",
            description: original.description,
            cover: original.cover,
            pageType: original.pageType,
            pageSize: original.pageSize,
            orientation: original.orientation,
            defaultTheme: original.defaultTheme,
            customCoverData: original.customCoverData
        )
        // Duplicate all sections from the original notebook.
        let originalSections = sections(inNotebook: original.id)
        for section in originalSections {
            addSection(toNotebook: copy.id, name: section.name,
                       defaultTemplateID: section.defaultTemplateID,
                       colorTag: section.colorTag)
        }
        return copy
    }

    func updateNotebookColorTag(id: UUID, colorTag: NotebookColorTag) {
        guard let idx = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[idx].colorTag = colorTag
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
    /// Optionally creates a snapshot for notes with dirty pages.
    private func flushToDisk(trigger: SnapshotTrigger = .autosave) {
        saveState = .saving
        var firstError: Error?

        if let driver = persistenceDriver {
            // SQLite / abstract driver path.
            do { try driver.encode(notes, forKey: Self.notesKey) }
            catch { firstError = error }
            do { try driver.encode(notebooks, forKey: Self.notebooksKey) }
            catch { if firstError == nil { firstError = error } }
            do { try driver.encode(sections, forKey: Self.sectionsKey) }
            catch { if firstError == nil { firstError = error } }
        } else {
            // Legacy per-file JSON path.
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
        }

        if let error = firstError {
            saveState = .error(error.localizedDescription)
            assertionFailure("Y2Notes: save failed — \(error)")
        } else {
            saveState = .saved
        }

        // Create snapshots for notes with dirty pages (background queue).
        let pendingDirtyPages = dirtyPages
        dirtyPages.removeAll()
        if !pendingDirtyPages.isEmpty {
            let notesCopy = notes
            PerformanceConstraints.storageQueue.async {
                for (noteID, pages) in pendingDirtyPages {
                    guard let note = notesCopy.first(where: { $0.id == noteID }) else { continue }
                    SnapshotStore.shared.createSnapshot(for: note, dirtyPages: pages, trigger: trigger)
                }
            }
        }
    }

    /// Writes `data` to `url` using an atomic swap (write-to-temp + rename), while keeping
    /// three rolling backup generations at `url.bak.1`, `.bak.2`, `.bak.3` to allow recovery
    /// from interrupted writes or corruption.
    fileprivate func writeAtomically(_ data: Data, to url: URL) throws {
        let bak1 = url.appendingPathExtension("bak.1")
        let bak2 = url.appendingPathExtension("bak.2")
        let bak3 = url.appendingPathExtension("bak.3")
        let fm = FileManager.default

        // Rotate backups: bak.2 → bak.3, bak.1 → bak.2, current → bak.1.
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: bak3)
            if fm.fileExists(atPath: bak2.path) {
                try? fm.moveItem(at: bak2, to: bak3)
            }
            if fm.fileExists(atPath: bak1.path) {
                try? fm.moveItem(at: bak1, to: bak2)
            }
            if (try? fm.copyItem(at: url, to: bak1)) == nil {
                storeLogger.error("Backup creation failed for \(url.lastPathComponent, privacy: .public)")
            }
            // Also maintain the legacy .bak for backward compatibility.
            let legacyBak = url.appendingPathExtension("bak")
            try? fm.removeItem(at: legacyBak)
            try? fm.copyItem(at: bak1, to: legacyBak)
        }
        // .atomic writes to a temp sibling then renames into place, making the
        // final swap as close to atomic as the filesystem permits.
        try data.write(to: url, options: .atomic)
    }

    private func load() {
        if let driver = persistenceDriver {
            // Try PersistenceDriver first.  If the DB is empty, fall back
            // to legacy JSON files and migrate data into the driver.
            let dbNotes = (try? driver.decode([Note].self, forKey: Self.notesKey)) ?? nil
            if let dbNotes {
                notes     = dbNotes
                notebooks = (try? driver.decode([Notebook].self,        forKey: Self.notebooksKey)) ?? []
                sections  = (try? driver.decode([NotebookSection].self, forKey: Self.sectionsKey))  ?? []
            } else {
                // First launch with driver — migrate from JSON files.
                notes     = loadJSON([Note].self,            from: notesURL)     ?? []
                notebooks = loadJSON([Notebook].self,        from: notebooksURL) ?? []
                sections  = loadJSON([NotebookSection].self, from: sectionsURL)  ?? []
                // Seed the driver so subsequent launches use it directly.
                migrateJSONToDriver(driver)
            }
        } else {
            notes     = loadJSON([Note].self,            from: notesURL)     ?? []
            notebooks = loadJSON([Notebook].self,        from: notebooksURL) ?? []
            sections  = loadJSON([NotebookSection].self, from: sectionsURL)  ?? []
        }
    }

    /// One-time migration: writes current in-memory state into the persistence
    /// driver and logs the result.
    private func migrateJSONToDriver(_ driver: PersistenceDriver) {
        storeLogger.info("Migrating JSON data to persistence driver…")
        do {
            try driver.encode(notes,     forKey: Self.notesKey)
            try driver.encode(notebooks, forKey: Self.notebooksKey)
            try driver.encode(sections,  forKey: Self.sectionsKey)
            storeLogger.info("Migration complete — \(self.notes.count) notes, \(self.notebooks.count) notebooks, \(self.sections.count) sections")
        } catch {
            storeLogger.error("Migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Decodes `type` from `url`. On missing or corrupt primary file, falls back to
    /// the rolling backups created by `writeAtomically` so interrupted writes are recoverable.
    fileprivate func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        if let value = attemptLoad(type, from: url) {
            return value
        }
        // Try rolling backups: bak.1, bak.2, bak.3, then legacy .bak.
        let backupSuffixes = ["bak.1", "bak.2", "bak.3", "bak"]
        for suffix in backupSuffixes {
            let backupURL = url.appendingPathExtension(suffix)
            if let value = attemptLoad(type, from: backupURL) {
                // Promote the backup to primary so the next save goes to the right place.
                if (try? FileManager.default.copyItem(at: backupURL, to: url)) == nil {
                    storeLogger.warning("Backup promotion failed for \(url.lastPathComponent, privacy: .public) from .\(suffix, privacy: .public); data will be rewritten on next save")
                }
                return value
            }
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

    // MARK: - Tags & color label

    /// Replaces the entire tag array for a note.
    /// Each tag is lowercased and whitespace-trimmed before saving.
    func updateTags(for noteID: UUID, tags: [String]) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].tags = tags
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        isDirty = true
    }

    /// Adds a single tag to a note if it is not already present.
    func addTag(_ tag: String, to noteID: UUID) {
        let normalised = tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty,
              let idx = notes.firstIndex(where: { $0.id == noteID }),
              !notes[idx].tags.contains(normalised) else { return }
        notes[idx].tags.append(normalised)
        isDirty = true
    }

    /// Removes a single tag from a note.
    func removeTag(_ tag: String, from noteID: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].tags.removeAll { $0 == tag }
        isDirty = true
    }

    /// Sets or clears the colour label on a note.
    func updateColorLabel(for noteID: UUID, colorLabel: NoteColorLabel?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].colorLabel = colorLabel
        isDirty = true
    }

    /// All unique, sorted tags across every note in the store.
    var allTags: [String] {
        let flat = notes.flatMap { $0.tags }
        return Array(Set(flat)).sorted()
    }

    /// All notes that carry the given tag.
    func notes(withTag tag: String) -> [Note] {
        notes.filter { $0.tags.contains(tag) }
    }

    /// Schedules a Vision OCR pass on all pages of the note 4 seconds after the last
    /// drawing change.  Calling this method resets the timer so rapid drawing strokes
    /// don't trigger redundant recognition passes.
    ///
    /// Called automatically by `updateDrawing(for:pageIndex:data:)`.
    func scheduleOCR(for noteID: UUID) {
        ocrTimers[noteID]?.invalidate()
        ocrTimers[noteID] = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.ocrTimers.removeValue(forKey: noteID)
            // Capture page data on the main thread before switching to async context.
            let pages = self.notes.first(where: { $0.id == noteID })?.pages ?? []
            guard !pages.isEmpty else { return }
            // Recompute the canonical canvas page size (mirrors CanvasView.pageSize).
            let screenBounds = UIScreen.main.bounds
            let screenW = max(screenBounds.width, screenBounds.height)
            let pageSize = CGSize(width: screenW, height: ceil(screenW * 1.414))
            Task { [weak self] in
                let text = await OCREngine.recognizeText(inPages: pages, pageSize: pageSize)
                await MainActor.run { [weak self] in
                    self?.updateOCRText(for: noteID, text: text)
                }
            }
        }
    }

    // MARK: - PDF regeneration

    /// Schedules a background PDF regeneration for the given note.  The timer fires 2 seconds
    /// after the last drawing change so rapid strokes don't cause redundant PDF writes.
    func schedulePDFRegeneration(for noteID: UUID) {
        pdfRegenTimers[noteID]?.invalidate()
        pdfRegenTimers[noteID] = Timer.scheduledTimer(
            withTimeInterval: Self.pdfRegenerationDebounceInterval, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.pdfRegenTimers.removeValue(forKey: noteID)
            guard let note = self.notes.first(where: { $0.id == noteID }),
                  let filename = note.pdfFilename else { return }
            let pages = note.pages
            let pageTypes = self.resolvedPageTypes(for: note)
            Task.detached(priority: .utility) {
                NotePDFGenerator.regeneratePDF(
                    filename: filename,
                    pages: pages,
                    attachmentLayers: note.attachmentLayers,
                    noteID: note.id,
                    backgroundColor: .white,
                    pageTypes: pageTypes
                )
            }
        }
    }

    /// Resolves the effective `PageType` array for every page of a note by cascading
    /// per-page → note-level → notebook-level → `.blank`.
    func resolvedPageTypes(for note: Note) -> [PageType] {
        let notebook = notebooks.first(where: { $0.id == note.notebookID })
        return (0 ..< note.pageCount).map { i in
            note.pageType(forPage: i) ?? notebook?.pageType ?? .blank
        }
    }

    /// Lazily generates backing PDFs for notes created before the PDF-based storage migration.
    /// Called once during `init()`.  Only touches notes whose `pdfFilename` is nil.
    private func ensurePDFsForLegacyNotes() {
        var changed = false
        for i in notes.indices where notes[i].pdfFilename == nil {
            let pageTypes = resolvedPageTypes(for: notes[i])
            if let filename = NotePDFGenerator.generateTemplatePDF(
                pageCount: notes[i].pageCount,
                backgroundColor: .white,
                pageTypes: pageTypes
            ) {
                notes[i].pdfFilename = filename
                changed = true
                // Regenerate immediately with strokes if the note has drawing data.
                let hasStrokes = notes[i].pages.contains { !$0.isEmpty }
                if hasStrokes {
                    NotePDFGenerator.regeneratePDF(
                        filename: filename,
                        pages: notes[i].pages,
                        attachmentLayers: notes[i].attachmentLayers,
                        noteID: notes[i].id,
                        backgroundColor: .white,
                        pageTypes: pageTypes
                    )
                }
            }
        }
        if changed {
            isDirty = true
        }
    }

    /// Returns the on-disk PDF URL for a given note, or nil if the note has no backing PDF.
    func notePDFURL(for note: Note) -> URL? {
        guard let filename = note.pdfFilename else { return nil }
        return NotePDFGenerator.pdfURL(for: filename)
    }

    // MARK: - Reload from disk (Drive sync)

    /// Reloads all data from disk. Called after a Google Drive import or backup restore
    /// overwrites the local JSON files.
    func reloadFromDisk() {
        load()
        loadStudy()
    }

    // MARK: - Version history restoration

    /// Replaces a note in the store with a restored version.
    /// Used by `VersionHistoryView` to restore an entire note from a snapshot.
    func replaceNote(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx] = note
        save()
        schedulePDFRegeneration(for: note.id)
    }

    /// Restores a single page of a note from snapshot data.
    func restorePage(
        noteID: UUID,
        pageIndex: Int,
        data: Data,
        stickers: [StickerInstance]?,
        shapes: [ShapeInstance]?,
        attachments: [AttachmentObject]?
    ) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              pageIndex >= 0 && pageIndex < notes[idx].pages.count else { return }
        notes[idx].pages[pageIndex] = data
        // Ensure parallel arrays are sized correctly.
        while notes[idx].stickerLayers.count < notes[idx].pages.count {
            notes[idx].stickerLayers.append(nil)
        }
        notes[idx].stickerLayers[pageIndex] = stickers
        while notes[idx].shapeLayers.count < notes[idx].pages.count {
            notes[idx].shapeLayers.append(nil)
        }
        notes[idx].shapeLayers[pageIndex] = shapes
        while notes[idx].attachmentLayers.count < notes[idx].pages.count {
            notes[idx].attachmentLayers.append(nil)
        }
        notes[idx].attachmentLayers[pageIndex] = attachments
        notes[idx].modifiedAt = Date()
        save()
        schedulePDFRegeneration(for: noteID)
    }

    /// Inserts a restored note (copy) into the store.
    func insertRestoredNote(_ note: Note) {
        notes.insert(note, at: 0)
        save()
    }

    /// Creates a pre-destructive snapshot of a note before deletion.
    func createPreDestructiveSnapshot(for noteID: UUID) {
        guard let note = notes.first(where: { $0.id == noteID }) else { return }
        PerformanceConstraints.storageQueue.async {
            SnapshotStore.shared.createSnapshot(
                for: note,
                dirtyPages: Set(0 ..< note.pages.count),
                trigger: .preDestructive
            )
        }
    }
}

// MARK: - Study set & flashcard persistence

extension NoteStore {
    /// Non-printable separator unlikely to appear in prompts/options.
    private static let studyTestKeyOptionSeparator = "\u{1F}"

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
        reviewHistory.removeAll { cardIDs.contains($0.cardID) }
        studyCards.removeAll { $0.setID == id }
        let questionIDs = studyTestQuestions.filter { $0.setID == id }.map(\.id)
        studyTestAttempts.removeAll { questionIDs.contains($0.questionID) || $0.setID == id }
        studyTestQuestions.removeAll { $0.setID == id }
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
        reviewHistory.removeAll { $0.cardID == id }
        studyCards.removeAll { $0.id == id }
        saveStudy()
    }

    /// Updates tags on an existing card.
    func updateCardTags(id: UUID, tags: [String]) {
        guard let idx = studyCards.firstIndex(where: { $0.id == id }) else { return }
        studyCards[idx].tags = tags
        studyCards[idx].modifiedAt = Date()
        saveStudy()
    }

    /// Bulk-imports multiple cards from a structured text block.
    /// Each line should contain "front :: back". Lines without "::" are skipped.
    @discardableResult
    func bulkImportCards(toSet setID: UUID, text: String, noteID: UUID? = nil) -> Int {
        let lines = text.components(separatedBy: .newlines)
        var imported = 0
        for line in lines {
            let parts = line.components(separatedBy: "::")
            guard parts.count >= 2 else { continue }
            let front = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { continue }
            let card = StudyCard(setID: setID, noteID: noteID, front: front, back: back)
            studyCards.insert(card, at: 0)
            cardProgress.append(StudyCardProgress(cardID: card.id))
            imported += 1
        }
        if imported > 0 { saveStudy() }
        return imported
    }

    // MARK: Study tests (multiple choice)

    func testQuestions(inSet setID: UUID) -> [StudyTestQuestion] {
        studyTestQuestions
            .filter { $0.setID == setID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func addTestQuestion(
        toSet setID: UUID,
        prompt: String,
        options: [String],
        correctOptionIndex: Int,
        explanation: String? = nil,
        noteID: UUID? = nil,
        tags: [String] = [],
        source: String? = nil
    ) -> StudyTestQuestion? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmedPrompt.isEmpty else { return nil }
        guard normalizedOptions.count >= 2 else { return nil }
        guard normalizedOptions.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard normalizedOptions.indices.contains(correctOptionIndex) else { return nil }

        let question = StudyTestQuestion(
            setID: setID,
            noteID: noteID,
            prompt: trimmedPrompt,
            options: normalizedOptions,
            correctOptionIndex: correctOptionIndex,
            explanation: explanation?.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags,
            source: source?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        studyTestQuestions.append(question)
        saveStudy()
        return question
    }

    @discardableResult
    func importTestQuestions(toSet setID: UUID, jsonData: Data) -> StudyTestImportSummary {
        let decoder = JSONDecoder()
        do {
            let payload = try decoder.decode(StudyTestImportPayload.self, from: jsonData)
            let validated = try payload.validatedQuestions()

            var addedCount = 0
            var skippedCount = 0
            var messages: [String] = []
            var existingKeys = Set(
                testQuestions(inSet: setID).map {
                    normalizedQuestionKey(prompt: $0.prompt, options: $0.options)
                }
            )

            for question in validated {
                let trimmedPrompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedOptions = question.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let key = normalizedQuestionKey(prompt: trimmedPrompt, options: normalizedOptions)
                let duplicate = existingKeys.contains(key)

                if duplicate {
                    skippedCount += 1
                    continue
                }

                let saved = addTestQuestion(
                    toSet: setID,
                    prompt: trimmedPrompt,
                    options: normalizedOptions,
                    correctOptionIndex: question.correctOptionIndex,
                    explanation: question.explanation,
                    noteID: question.noteID,
                    tags: question.tags ?? [],
                    source: question.source
                )
                if saved != nil {
                    addedCount += 1
                    existingKeys.insert(key)
                }
            }

            if skippedCount > 0 {
                messages.append("Skipped \(skippedCount) duplicate question\(skippedCount == 1 ? "" : "s").")
            }
            return StudyTestImportSummary(
                addedCount: addedCount,
                skippedCount: skippedCount,
                invalidCount: 0,
                messages: messages
            )
        } catch {
            return StudyTestImportSummary(
                addedCount: 0,
                skippedCount: 0,
                invalidCount: 1,
                messages: [error.localizedDescription]
            )
        }
    }

    func testImportPreview(from jsonData: Data) -> Result<StudyTestImportPayload, Error> {
        let decoder = JSONDecoder()
        do {
            let payload = try decoder.decode(StudyTestImportPayload.self, from: jsonData)
            _ = try payload.validatedQuestions()
            return .success(payload)
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    func recordTestAttempt(
        questionID: UUID,
        selectedOptionIndex: Int?,
        durationSeconds: TimeInterval? = nil,
        answeredAt: Date = Date()
    ) -> Bool? {
        guard let question = studyTestQuestions.first(where: { $0.id == questionID }) else { return nil }
        let isCorrect = selectedOptionIndex == question.correctOptionIndex
        let attempt = StudyTestAttempt(
            questionID: question.id,
            setID: question.setID,
            selectedOptionIndex: selectedOptionIndex,
            isCorrect: isCorrect,
            answeredAt: answeredAt,
            durationSeconds: durationSeconds
        )
        studyTestAttempts.append(attempt)
        saveStudy()
        return isCorrect
    }

    func testStats(forQuestion questionID: UUID) -> StudyTestQuestionStats {
        let attempts = studyTestAttempts.filter { $0.questionID == questionID }
        let total = attempts.count
        let correct = attempts.filter(\.isCorrect).count
        let incorrect = total - correct
        let accuracy = total > 0 ? Double(correct) / Double(total) : 0
        return StudyTestQuestionStats(
            questionID: questionID,
            attempts: total,
            correctAttempts: correct,
            incorrectAttempts: incorrect,
            accuracy: accuracy,
            lastAttemptedAt: attempts.map(\.answeredAt).max()
        )
    }

    func testStats(forSet setID: UUID) -> StudyTestSetStats {
        let questions = testQuestions(inSet: setID)
        let questionIDs = Set(questions.map(\.id))
        let attempts = studyTestAttempts
            .filter { $0.setID == setID && questionIDs.contains($0.questionID) }
            .sorted { $0.answeredAt < $1.answeredAt }
        let total = attempts.count
        let correct = attempts.filter(\.isCorrect).count
        let incorrect = total - correct
        let accuracy = total > 0 ? Double(correct) / Double(total) : 0

        let weakQuestions = questions
            .map { question -> StudyTestWeakQuestion in
                let stats = testStats(forQuestion: question.id)
                return StudyTestWeakQuestion(
                    id: question.id,
                    prompt: question.prompt,
                    accuracy: stats.accuracy,
                    attempts: stats.attempts
                )
            }
            .filter { $0.attempts > 0 }
            .sorted { StudyTestWeakQuestion.ranksWeaker($0, than: $1) }
            .prefix(5)

        let calendar = Calendar.current
        let now = Date()
        let points: [StudyTestDailyAccuracyPoint] = (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let dayAttempts = attempts.filter { $0.answeredAt >= dayStart && $0.answeredAt < dayEnd }
            let dayTotal = dayAttempts.count
            let dayAccuracy = dayTotal > 0 ? Double(dayAttempts.filter(\.isCorrect).count) / Double(dayTotal) : 0
            return StudyTestDailyAccuracyPoint(date: dayStart, attempts: dayTotal, accuracy: dayAccuracy)
        }

        return StudyTestSetStats(
            setID: setID,
            questionCount: questions.count,
            totalAttempts: total,
            correctAttempts: correct,
            incorrectAttempts: incorrect,
            accuracy: accuracy,
            weakQuestions: Array(weakQuestions),
            dailyTrend: points
        )
    }

    private func normalizedQuestionKey(prompt: String, options: [String]) -> String {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: Self.studyTestKeyOptionSeparator)
        return "\(normalizedPrompt)|\(normalizedOptions)"
    }

    // MARK: Spaced repetition

    /// Records a review result for `cardID` and advances its scheduling state.
    func recordReview(cardID: UUID, rating: ReviewRating, reviewedAt: Date = Date()) {
        // Determine the set for the history entry.
        let setID = studyCards.first { $0.id == cardID }?.setID ?? UUID()

        if let idx = cardProgress.firstIndex(where: { $0.cardID == cardID }) {
            cardProgress[idx] = cardProgress[idx].applying(rating: rating, reviewedAt: reviewedAt)
        } else {
            // Safety: create progress record if missing (shouldn't normally happen).
            var progress = StudyCardProgress(cardID: cardID)
            progress = progress.applying(rating: rating, reviewedAt: reviewedAt)
            cardProgress.append(progress)
        }

        // Append to review history for analytics.
        let entry = StudyReviewEntry(cardID: cardID, setID: setID, rating: rating, reviewedAt: reviewedAt)
        reviewHistory.append(entry)

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
            cardProgress: cardProgress,
            reviewHistory: reviewHistory,
            studyTestQuestions: studyTestQuestions,
            studyTestAttempts: studyTestAttempts
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? writeAtomically(data, to: studyURL)
        }
    }

    /// Loads study data from disk into the published properties.
    func loadStudy() {
        guard let payload = loadJSON(StudyPayload.self, from: studyURL) else { return }
        studySets      = payload.studySets
        studyCards     = payload.studyCards
        cardProgress   = payload.cardProgress
        reviewHistory  = payload.reviewHistory
        studyTestQuestions = payload.studyTestQuestions
        studyTestAttempts = payload.studyTestAttempts
    }

    /// Private container used for encoding/decoding study data as a single JSON file.
    private struct StudyPayload: Codable {
        var studySets:     [StudySet]
        var studyCards:    [StudyCard]
        var cardProgress:  [StudyCardProgress]
        var reviewHistory: [StudyReviewEntry]
        var studyTestQuestions: [StudyTestQuestion]
        var studyTestAttempts: [StudyTestAttempt]

        // Backward-compatible: old data may not have reviewHistory
        enum CodingKeys: String, CodingKey {
            case studySets, studyCards, cardProgress, reviewHistory
            case studyTestQuestions, studyTestAttempts
        }

        init(
            studySets: [StudySet],
            studyCards: [StudyCard],
            cardProgress: [StudyCardProgress],
            reviewHistory: [StudyReviewEntry],
            studyTestQuestions: [StudyTestQuestion],
            studyTestAttempts: [StudyTestAttempt]
        ) {
            self.studySets = studySets
            self.studyCards = studyCards
            self.cardProgress = cardProgress
            self.reviewHistory = reviewHistory
            self.studyTestQuestions = studyTestQuestions
            self.studyTestAttempts = studyTestAttempts
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            studySets     = try c.decode([StudySet].self, forKey: .studySets)
            studyCards    = try c.decode([StudyCard].self, forKey: .studyCards)
            cardProgress  = try c.decode([StudyCardProgress].self, forKey: .cardProgress)
            reviewHistory = try c.decodeIfPresent([StudyReviewEntry].self, forKey: .reviewHistory) ?? []
            studyTestQuestions = try c.decodeIfPresent([StudyTestQuestion].self, forKey: .studyTestQuestions) ?? []
            studyTestAttempts = try c.decodeIfPresent([StudyTestAttempt].self, forKey: .studyTestAttempts) ?? []
        }
    }
}

// MARK: - NoteRepository conformance

extension NoteStore: NoteRepository {

    var notesPublisher: AnyPublisher<[Note], Never> {
        $notes.eraseToAnyPublisher()
    }

    var notebooksPublisher: AnyPublisher<[Notebook], Never> {
        $notebooks.eraseToAnyPublisher()
    }

    var sectionsPublisher: AnyPublisher<[NotebookSection], Never> {
        $sections.eraseToAnyPublisher()
    }

    var studySetsPublisher: AnyPublisher<[StudySet], Never> {
        $studySets.eraseToAnyPublisher()
    }

    var saveStatePublisher: AnyPublisher<SaveState, Never> {
        $saveState.eraseToAnyPublisher()
    }

    @discardableResult
    func addNote(
        title: String,
        notebookID: UUID?,
        pageType: PageType?,
        pageSize: PageSize?,
        orientation: PageOrientation?,
        templateID: String?
    ) -> Note {
        // NoteStore.addNote(inNotebook:) sets the title automatically ("Note N+1"),
        // and does not yet support pageSize/orientation/templateID — those are
        // silently ignored here to satisfy the protocol interface.
        addNote(inNotebook: notebookID, pageType: pageType)
    }

    @discardableResult
    func addNotebook(
        name: String,
        cover: NotebookCover,
        defaultPageType: PageType,
        defaultPageSize: PageSize,
        defaultOrientation: PageOrientation,
        colorTag: NotebookColorTag
    ) -> Notebook {
        // colorTag is not yet exposed by NoteStore.addNotebook; call updateNotebookColorTag
        // on the returned notebook to apply the tag after creation if needed.
        var nb = addNotebook(
            name: name,
            cover: cover,
            pageType: defaultPageType,
            pageSize: defaultPageSize,
            orientation: defaultOrientation
        )
        if colorTag != .none {
            updateNotebookColorTag(id: nb.id, colorTag: colorTag)
            nb = notebooks.first(where: { $0.id == nb.id }) ?? nb
        }
        return nb
    }

    @discardableResult
    func addSection(toNotebook notebookID: UUID, name: String, sortOrder: Int) -> NotebookSection {
        // sortOrder is computed automatically by NoteStore.addSection; the protocol
        // parameter is accepted for interface compatibility but the concrete implementation
        // always appends at the next available sort position.
        addSection(toNotebook: notebookID, name: name)
    }
}

// swiftlint:enable file_length
