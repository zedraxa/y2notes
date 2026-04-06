import Combine
import Foundation
import UIKit

// MARK: - NoteRepository

/// Framework-agnostic protocol for note and notebook CRUD operations.
///
/// Concrete implementations may back this with JSON files, SQLite, Core Data, etc.
/// The protocol exposes `AnyPublisher` streams so consumers can observe changes
/// **without** depending on SwiftUI's `ObservableObject` / `@Published` mechanism.
///
/// - Important: All publishers **must** deliver values on the main thread.
protocol NoteRepository: AnyObject {

    // MARK: - Reactive state

    var notesPublisher: AnyPublisher<[Note], Never> { get }
    var notebooksPublisher: AnyPublisher<[Notebook], Never> { get }
    var sectionsPublisher: AnyPublisher<[NotebookSection], Never> { get }
    var studySetsPublisher: AnyPublisher<[StudySet], Never> { get }
    var saveStatePublisher: AnyPublisher<SaveState, Never> { get }

    // MARK: - Snapshot accessors (current value)

    var notes: [Note] { get }
    var notebooks: [Notebook] { get }
    var sections: [NotebookSection] { get }
    var studySets: [StudySet] { get }

    // MARK: - Note CRUD

    @discardableResult
    func addNote(
        title: String,
        notebookID: UUID?,
        pageType: PageType?,
        pageSize: PageSize?,
        orientation: PageOrientation?,
        paperMaterial: PaperMaterial?,
        templateID: String?
    ) -> Note

    func deleteNotes(ids: [UUID])
    func duplicateNote(id: UUID) -> Note?
    func updateTitle(for noteID: UUID, title: String)
    func toggleFavorite(id: UUID)
    func moveNote(id: UUID, toNotebook notebookID: UUID?)

    // MARK: - Drawing

    func updateDrawing(for noteID: UUID, data: Data)
    func updateDrawing(for noteID: UUID, pageIndex: Int, data: Data)

    // MARK: - Page management

    func addPage(to noteID: UUID) -> Int?
    func removePage(from noteID: UUID, at pageIndex: Int)
    func reorderPageInNote(noteID: UUID, from source: Int, to destination: Int)
    func duplicatePageInNote(noteID: UUID, pageIndex: Int) -> Int?

    // MARK: - Page content

    func updateStickers(for noteID: UUID, pageIndex: Int, stickers: [StickerInstance])
    func updateShapes(for noteID: UUID, pageIndex: Int, shapes: [ShapeInstance])
    func updateAttachments(for noteID: UUID, pageIndex: Int, attachments: [AttachmentObject])
    func updateWidgets(for noteID: UUID, pageIndex: Int, widgets: [NoteWidget])
    func updateTextObjects(for noteID: UUID, pageIndex: Int, textObjects: [TextObject])
    func updatePageType(for noteID: UUID, pageType: PageType?)
    func updatePageType(for noteID: UUID, pageIndex: Int, pageType: PageType?)
    func updatePaperMaterial(for noteID: UUID, paperMaterial: PaperMaterial?)
    func updatePageColor(for noteID: UUID, pageIndex: Int, color: UIColor?)
    func updateThemeOverride(for noteID: UUID, theme: AppTheme?)

    // MARK: - Expansion regions

    func updateExpansionRegions(for noteID: UUID, regions: [PageRegion])
    func addExpansionRegion(to noteID: UUID, region: PageRegion)
    func removeExpansionRegion(from noteID: UUID, regionID: UUID)

    // MARK: - Notebook CRUD

    @discardableResult
    func addNotebook(
        name: String,
        cover: NotebookCover,
        defaultPageType: PageType,
        defaultPageSize: PageSize,
        defaultOrientation: PageOrientation,
        defaultPaperMaterial: PaperMaterial,
        colorTag: NotebookColorTag
    ) -> Notebook

    func renameNotebook(id: UUID, name: String)
    func deleteNotebook(id: UUID)
    func duplicateNotebook(id: UUID) -> Notebook?

    // MARK: - Notebook settings

    func updateNotebookCover(id: UUID, cover: NotebookCover)
    func updateNotebookTexture(id: UUID, texture: CoverTexture)
    func toggleNotebookPin(id: UUID)
    func toggleNotebookLock(id: UUID)
    func updateNotebookColorTag(id: UUID, colorTag: NotebookColorTag)

    // MARK: - Section CRUD

    @discardableResult
    func addSection(toNotebook notebookID: UUID, name: String, sortOrder: Int) -> NotebookSection

    func renameSection(id: UUID, name: String)
    func deleteSection(id: UUID, movePagesToNotebook: Bool)
    func reorderSections(inNotebook notebookID: UUID, fromOffsets: IndexSet, toOffset: Int)

    // MARK: - Text & OCR

    func updateTypedText(for noteID: UUID, text: String)
    func updateOCRText(for noteID: UUID, text: String)
    func updateTags(for noteID: UUID, tags: [String])

    // MARK: - Study

    func addStudySet(title: String, notebookID: UUID?) -> StudySet
    func addCard(toSet setID: UUID, front: String, back: String, noteID: UUID?, tags: [String]) -> StudyCard

    // MARK: - Query helpers

    func notes(inNotebook notebookID: UUID) -> [Note]
    func sections(inNotebook notebookID: UUID) -> [NotebookSection]

    // MARK: - Persistence

    func save()
    func reloadFromDisk()
}
