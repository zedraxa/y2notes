import Foundation

// MARK: - Navigation anchor — universal deep-link target

/// A lightweight, serialisable pointer to any location within a notebook.
/// Used for bookmarks, history entries, search result jumps, and deep links.
///
/// The anchor uniquely identifies a page within a notebook's linearised
/// page list so navigation can resolve it regardless of section reordering.
struct NavigationAnchor: Identifiable, Codable, Hashable {
    let id: UUID
    /// The notebook containing the target page.
    var notebookID: UUID
    /// The note (page owner) this anchor points to.
    var noteID: UUID
    /// 0-based page index within the note's `pages` array.
    var pageIndex: Int
    /// Optional object ID on the target page (e.g. attachment UUID).
    /// When set, the navigation handler highlights this object after jumping.
    var objectID: UUID?
    /// Optional audio session ID for audio-linked search results.
    /// When set, the navigation handler starts playback of this session.
    var audioSessionID: UUID?
    /// Optional audio offset (seconds from session start) for keyword→audio jump.
    /// Used together with `audioSessionID` to seek to a specific playback position.
    var audioOffset: TimeInterval?

    init(
        id: UUID = UUID(),
        notebookID: UUID,
        noteID: UUID,
        pageIndex: Int,
        objectID: UUID? = nil,
        audioSessionID: UUID? = nil,
        audioOffset: TimeInterval? = nil
    ) {
        self.id = id
        self.notebookID = notebookID
        self.noteID = noteID
        self.pageIndex = pageIndex
        self.objectID = objectID
        self.audioSessionID = audioSessionID
        self.audioOffset = audioOffset
    }
}

// MARK: - Page bookmark

/// A user-pinned page within a notebook.
/// Bookmarks survive page reordering — they track note + pageIndex.
struct PageBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    /// The anchor this bookmark points to.
    var anchor: NavigationAnchor
    /// User-provided label (empty = auto-labelled "Page N").
    var label: String
    /// When the bookmark was created.
    var createdAt: Date
    /// Optional colour tag for visual grouping.
    var colorTag: BookmarkColor

    init(
        id: UUID = UUID(),
        anchor: NavigationAnchor,
        label: String = "",
        createdAt: Date = Date(),
        colorTag: BookmarkColor = .red
    ) {
        self.id = id
        self.anchor = anchor
        self.label = label
        self.createdAt = createdAt
        self.colorTag = colorTag
    }
}

/// Colour swatches for bookmark tabs.
enum BookmarkColor: String, CaseIterable, Codable {
    case red, orange, yellow, green, blue, purple
}

// MARK: - Navigation history entry

/// A single visited-page record in the back/forward stack.
struct NavigationHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var anchor: NavigationAnchor
    /// Flat page index at time of visit (for display; re-resolved on jump).
    var flatPageIndex: Int
    var visitedAt: Date

    init(
        id: UUID = UUID(),
        anchor: NavigationAnchor,
        flatPageIndex: Int,
        visitedAt: Date = Date()
    ) {
        self.id = id
        self.anchor = anchor
        self.flatPageIndex = flatPageIndex
        self.visitedAt = visitedAt
    }
}

// MARK: - Constants

enum NavigationConstants {
    /// Maximum entries kept in the back/forward history per notebook.
    static let maxHistoryEntries = 50
    /// Maximum recent locations shown in the popover.
    static let maxRecentLocations = 10
    /// Maximum bookmarks per notebook.
    static let maxBookmarksPerNotebook = 200
    /// Minimum seconds between consecutive history pushes (debounce rapid page flips).
    static let historyDebounceInterval: TimeInterval = 1.5
}
