import Foundation
import CoreGraphics

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
    /// Optional expansion region ID for anchors that target content in an expansion area.
    /// When set, the navigation handler scrolls to the expansion region after jumping to the page.
    var regionID: UUID?
    /// Optional scroll-to point in canvas coordinates within the target page or expansion region.
    /// Used for precise viewport positioning after navigation.
    var canvasPoint: CGPoint?

    init(
        id: UUID = UUID(),
        notebookID: UUID,
        noteID: UUID,
        pageIndex: Int,
        objectID: UUID? = nil,
        audioSessionID: UUID? = nil,
        audioOffset: TimeInterval? = nil,
        regionID: UUID? = nil,
        canvasPoint: CGPoint? = nil
    ) {
        self.id = id
        self.notebookID = notebookID
        self.noteID = noteID
        self.pageIndex = pageIndex
        self.objectID = objectID
        self.audioSessionID = audioSessionID
        self.audioOffset = audioOffset
        self.regionID = regionID
        self.canvasPoint = canvasPoint
    }
}

// MARK: - Custom Codable for CGPoint support

extension NavigationAnchor {
    enum CodingKeys: String, CodingKey {
        case id, notebookID, noteID, pageIndex, objectID
        case audioSessionID, audioOffset
        case regionID, canvasPointX, canvasPointY
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        notebookID      = try c.decode(UUID.self, forKey: .notebookID)
        noteID          = try c.decode(UUID.self, forKey: .noteID)
        pageIndex       = try c.decode(Int.self, forKey: .pageIndex)
        objectID        = try c.decodeIfPresent(UUID.self, forKey: .objectID)
        audioSessionID  = try c.decodeIfPresent(UUID.self, forKey: .audioSessionID)
        audioOffset     = try c.decodeIfPresent(TimeInterval.self, forKey: .audioOffset)
        regionID        = try c.decodeIfPresent(UUID.self, forKey: .regionID)
        if let x = try c.decodeIfPresent(CGFloat.self, forKey: .canvasPointX),
           let y = try c.decodeIfPresent(CGFloat.self, forKey: .canvasPointY) {
            canvasPoint = CGPoint(x: x, y: y)
        } else {
            canvasPoint = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(notebookID, forKey: .notebookID)
        try c.encode(noteID, forKey: .noteID)
        try c.encode(pageIndex, forKey: .pageIndex)
        try c.encodeIfPresent(objectID, forKey: .objectID)
        try c.encodeIfPresent(audioSessionID, forKey: .audioSessionID)
        try c.encodeIfPresent(audioOffset, forKey: .audioOffset)
        try c.encodeIfPresent(regionID, forKey: .regionID)
        if let point = canvasPoint {
            try c.encode(point.x, forKey: .canvasPointX)
            try c.encode(point.y, forKey: .canvasPointY)
        }
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
