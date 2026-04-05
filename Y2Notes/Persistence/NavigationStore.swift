import Foundation
import os

private let navLogger = Logger(subsystem: "com.y2notes", category: "NavigationStore")

// MARK: - NavigationStore

/// Manages bookmarks, back/forward history, and recent locations for notebook navigation.
///
/// **Persistence**: Bookmarks are saved to `y2notes_bookmarks.json` in the Documents directory.
/// Navigation history is kept in-memory only — ephemeral by design; it resets each session.
///
/// **Architecture**: One store shared across all notebooks. Keyed internally by `notebookID`.
final class NavigationStore: ObservableObject {

    // MARK: - Published state

    /// All bookmarks across all notebooks.
    @Published private(set) var bookmarks: [PageBookmark] = []

    /// Back stack for the currently active notebook (most recent at the end).
    @Published private(set) var backStack: [NavigationHistoryEntry] = []

    /// Forward stack (populated when the user goes "back"; cleared on new navigation).
    @Published private(set) var forwardStack: [NavigationHistoryEntry] = []

    /// The notebook currently being tracked for history.
    private(set) var activeNotebookID: UUID?

    /// Timestamp of the last history push — used for debounce.
    private var lastHistoryPush: Date = .distantPast

    // MARK: - Persistence

    private let bookmarksURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_bookmarks.json")
    }()

    init() {
        loadBookmarks()
    }

    // MARK: - Bookmark operations

    /// Returns bookmarks for the given notebook, ordered by creation date.
    func bookmarks(for notebookID: UUID) -> [PageBookmark] {
        bookmarks
            .filter { $0.anchor.notebookID == notebookID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Whether the given page is bookmarked.
    func isBookmarked(notebookID: UUID, noteID: UUID, pageIndex: Int) -> Bool {
        bookmarks.contains {
            $0.anchor.notebookID == notebookID &&
            $0.anchor.noteID == noteID &&
            $0.anchor.pageIndex == pageIndex
        }
    }

    /// Toggles a bookmark for the given page. Returns `true` if a bookmark was added.
    @discardableResult
    func toggleBookmark(
        notebookID: UUID,
        noteID: UUID,
        pageIndex: Int,
        label: String = "",
        colorTag: BookmarkColor = .red
    ) -> Bool {
        if let idx = bookmarks.firstIndex(where: {
            $0.anchor.notebookID == notebookID &&
            $0.anchor.noteID == noteID &&
            $0.anchor.pageIndex == pageIndex
        }) {
            bookmarks.remove(at: idx)
            saveBookmarks()
            return false
        } else {
            guard bookmarks(for: notebookID).count < NavigationConstants.maxBookmarksPerNotebook else {
                return false
            }
            let anchor = NavigationAnchor(
                notebookID: notebookID,
                noteID: noteID,
                pageIndex: pageIndex
            )
            let bookmark = PageBookmark(
                anchor: anchor,
                label: label,
                colorTag: colorTag
            )
            bookmarks.append(bookmark)
            saveBookmarks()
            return true
        }
    }

    /// Removes a specific bookmark by ID.
    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    /// Updates the label of an existing bookmark.
    func updateBookmarkLabel(id: UUID, label: String) {
        if let idx = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[idx].label = label
            saveBookmarks()
        }
    }

    /// Updates the colour tag of an existing bookmark.
    func updateBookmarkColor(id: UUID, colorTag: BookmarkColor) {
        if let idx = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[idx].colorTag = colorTag
            saveBookmarks()
        }
    }

    // MARK: - Navigation history

    /// Sets the active notebook for history tracking and clears the stacks.
    func activateNotebook(_ notebookID: UUID) {
        guard activeNotebookID != notebookID else { return }
        activeNotebookID = notebookID
        backStack = []
        forwardStack = []
        lastHistoryPush = .distantPast
    }

    /// Records a page visit. Debounces rapid sequential calls (e.g. fast page flips).
    func pushHistory(notebookID: UUID, noteID: UUID, pageIndex: Int, flatPageIndex: Int) {
        guard notebookID == activeNotebookID else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHistoryPush) >= NavigationConstants.historyDebounceInterval else {
            return
        }
        lastHistoryPush = now

        // Don't duplicate the current position
        if let last = backStack.last,
           last.anchor.noteID == noteID && last.anchor.pageIndex == pageIndex {
            return
        }

        let anchor = NavigationAnchor(
            notebookID: notebookID,
            noteID: noteID,
            pageIndex: pageIndex
        )
        let entry = NavigationHistoryEntry(
            anchor: anchor,
            flatPageIndex: flatPageIndex
        )
        backStack.append(entry)

        // Trim old entries
        if backStack.count > NavigationConstants.maxHistoryEntries {
            backStack.removeFirst(backStack.count - NavigationConstants.maxHistoryEntries)
        }

        // New navigation clears forward stack
        forwardStack.removeAll()
    }

    /// Pops the back stack and pushes current location onto forward stack.
    /// Returns the history entry to navigate to, or nil if stack is empty.
    func goBack(currentNotebookID: UUID, currentNoteID: UUID, currentPageIndex: Int, currentFlatIndex: Int) -> NavigationHistoryEntry? {
        guard !backStack.isEmpty else { return nil }
        let target = backStack.removeLast()

        // Push current location onto forward stack
        let currentAnchor = NavigationAnchor(
            notebookID: currentNotebookID,
            noteID: currentNoteID,
            pageIndex: currentPageIndex
        )
        let currentEntry = NavigationHistoryEntry(
            anchor: currentAnchor,
            flatPageIndex: currentFlatIndex
        )
        forwardStack.append(currentEntry)

        lastHistoryPush = .distantPast // Allow immediate re-push after manual navigation
        return target
    }

    /// Pops the forward stack and pushes current location onto back stack.
    /// Returns the history entry to navigate to, or nil if stack is empty.
    func goForward(currentNotebookID: UUID, currentNoteID: UUID, currentPageIndex: Int, currentFlatIndex: Int) -> NavigationHistoryEntry? {
        guard !forwardStack.isEmpty else { return nil }
        let target = forwardStack.removeLast()

        // Push current location onto back stack
        let currentAnchor = NavigationAnchor(
            notebookID: currentNotebookID,
            noteID: currentNoteID,
            pageIndex: currentPageIndex
        )
        let currentEntry = NavigationHistoryEntry(
            anchor: currentAnchor,
            flatPageIndex: currentFlatIndex
        )
        backStack.append(currentEntry)

        lastHistoryPush = .distantPast
        return target
    }

    /// Whether back navigation is available.
    var canGoBack: Bool { !backStack.isEmpty }

    /// Whether forward navigation is available.
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Returns unique recent locations (most recent first, de-duplicated by page).
    func recentLocations(for notebookID: UUID, limit: Int = NavigationConstants.maxRecentLocations) -> [NavigationHistoryEntry] {
        var seen = Set<String>()
        var result: [NavigationHistoryEntry] = []
        for entry in backStack.reversed() where entry.anchor.notebookID == notebookID {
            let key = "\(entry.anchor.noteID)-\(entry.anchor.pageIndex)"
            if seen.insert(key).inserted {
                result.append(entry)
                if result.count >= limit { break }
            }
        }
        return result
    }

    // MARK: - Persistence internals

    private func saveBookmarks() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: bookmarksURL, options: .atomic)
        } catch {
            #if DEBUG
            navLogger.error("Bookmark save failed: \(error.localizedDescription, privacy: .public)")
            #endif
        }
    }

    private func loadBookmarks() {
        guard FileManager.default.fileExists(atPath: bookmarksURL.path) else { return }
        do {
            let data = try Data(contentsOf: bookmarksURL)
            bookmarks = try JSONDecoder().decode([PageBookmark].self, from: data)
        } catch {
            #if DEBUG
            navLogger.error("Bookmark load failed: \(error.localizedDescription, privacy: .public)")
            #endif
            bookmarks = []
        }
    }
}
