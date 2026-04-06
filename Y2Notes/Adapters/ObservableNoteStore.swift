import Combine
import SwiftUI

// MARK: - ObservableNoteStore

/// Thin SwiftUI adapter that bridges `NoteRepository` → `ObservableObject`.
///
/// Subscribe to the repository's Combine publishers and mirror state via
/// `@Published` so SwiftUI views can keep using `@EnvironmentObject`.
final class ObservableNoteStore: ObservableObject {

    @Published private(set) var notes: [Note] = []
    @Published private(set) var notebooks: [Notebook] = []
    @Published private(set) var sections: [NotebookSection] = []
    @Published private(set) var studySets: [StudySet] = []
    @Published private(set) var saveState: SaveState = .idle

    let repository: NoteRepository
    private var cancellables = Set<AnyCancellable>()

    init(repository: NoteRepository) {
        self.repository = repository

        repository.notesPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$notes)

        repository.notebooksPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$notebooks)

        repository.sectionsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$sections)

        repository.studySetsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$studySets)

        repository.saveStatePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$saveState)
    }
}
