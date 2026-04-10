import Foundation
import CoreGraphics

// MARK: - Navigation anchor

public struct NavigationAnchor: Identifiable, Codable, Hashable {
    public let id: UUID
    public var notebookID: UUID
    public var noteID: UUID
    public var pageIndex: Int
    public var objectID: UUID?
    public var audioSessionID: UUID?
    public var audioOffset: TimeInterval?
    public var regionID: UUID?
    public var canvasPoint: CGPoint?

    public init(
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

// MARK: - Hashable (CGPoint is not Hashable)

extension NavigationAnchor {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(notebookID)
        hasher.combine(noteID)
        hasher.combine(pageIndex)
        hasher.combine(objectID)
        hasher.combine(audioSessionID)
        hasher.combine(audioOffset)
        hasher.combine(regionID)
        hasher.combine(canvasPoint?.x)
        hasher.combine(canvasPoint?.y)
    }

    public static func == (lhs: NavigationAnchor, rhs: NavigationAnchor) -> Bool {
        lhs.id == rhs.id
        && lhs.notebookID == rhs.notebookID
        && lhs.noteID == rhs.noteID
        && lhs.pageIndex == rhs.pageIndex
        && lhs.objectID == rhs.objectID
        && lhs.audioSessionID == rhs.audioSessionID
        && lhs.audioOffset == rhs.audioOffset
        && lhs.regionID == rhs.regionID
        && lhs.canvasPoint == rhs.canvasPoint
    }
}

// MARK: - Custom Codable for CGPoint support

extension NavigationAnchor {
    enum CodingKeys: String, CodingKey {
        case id, notebookID, noteID, pageIndex, objectID
        case audioSessionID, audioOffset
        case regionID, canvasPointX, canvasPointY
    }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public struct PageBookmark: Identifiable, Codable, Hashable {
    public let id: UUID
    public var anchor: NavigationAnchor
    public var label: String
    public var createdAt: Date
    public var colorTag: BookmarkColor

    public init(
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

public enum BookmarkColor: String, CaseIterable, Codable {
    case red, orange, yellow, green, blue, purple
}

// MARK: - Navigation history entry

public struct NavigationHistoryEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    public var anchor: NavigationAnchor
    public var flatPageIndex: Int
    public var visitedAt: Date

    public init(
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

public enum NavigationConstants {
    public static let maxHistoryEntries = 50
    public static let maxRecentLocations = 10
    public static let maxBookmarksPerNotebook = 200
    public static let historyDebounceInterval: TimeInterval = 1.5
}
