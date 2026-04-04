import Foundation
import UIKit

// MARK: - Sticker Instance

/// A single sticker placed on a notebook page.  Lightweight value type
/// stored in the Note model's `stickerLayers` parallel array.
struct StickerInstance: Codable, Identifiable, Equatable {
    let id: UUID
    /// References an asset in the sticker library (built-in or custom).
    let stickerID: String
    /// Center point in page coordinates (points, relative to page origin).
    var position: CGPoint
    /// Uniform scale factor (1.0 = natural size).
    var scale: CGFloat
    /// Rotation in radians.
    var rotation: CGFloat
    /// Visual opacity (0.0–1.0).  Default 1.0.
    var opacity: CGFloat
    /// Ordering within the sticker layer.  Higher values render on top.
    var zIndex: Int
    /// When true the sticker cannot be moved, scaled, or rotated.
    var isLocked: Bool
    /// Timestamp of initial placement — used by Recents sort.
    let placedAt: Date

    init(
        id: UUID = UUID(),
        stickerID: String,
        position: CGPoint = .zero,
        scale: CGFloat = 1.0,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1.0,
        zIndex: Int = 0,
        isLocked: Bool = false,
        placedAt: Date = Date()
    ) {
        self.id = id
        self.stickerID = stickerID
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.placedAt = placedAt
    }

    // MARK: Codable – manual to handle CGPoint / CGFloat gracefully

    enum CodingKeys: String, CodingKey {
        case id, stickerID, posX, posY, scale, rotation, opacity, zIndex, isLocked, placedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        stickerID = try c.decode(String.self, forKey: .stickerID)
        let px    = try c.decode(Double.self, forKey: .posX)
        let py    = try c.decode(Double.self, forKey: .posY)
        position  = CGPoint(x: px, y: py)
        scale     = try c.decodeIfPresent(CGFloat.self, forKey: .scale)    ?? 1.0
        rotation  = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        opacity   = try c.decodeIfPresent(CGFloat.self, forKey: .opacity)  ?? 1.0
        zIndex    = try c.decodeIfPresent(Int.self,     forKey: .zIndex)   ?? 0
        isLocked  = try c.decodeIfPresent(Bool.self,    forKey: .isLocked) ?? false
        placedAt  = try c.decodeIfPresent(Date.self,    forKey: .placedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                  forKey: .id)
        try c.encode(stickerID,           forKey: .stickerID)
        try c.encode(Double(position.x),  forKey: .posX)
        try c.encode(Double(position.y),  forKey: .posY)
        try c.encode(scale,               forKey: .scale)
        try c.encode(rotation,            forKey: .rotation)
        try c.encode(opacity,             forKey: .opacity)
        try c.encode(zIndex,              forKey: .zIndex)
        try c.encode(isLocked,            forKey: .isLocked)
        try c.encode(placedAt,            forKey: .placedAt)
    }
}

// MARK: - Sticker Category

/// Categories used to organise the sticker library.
enum StickerCategory: String, Codable, CaseIterable, Identifiable {
    case essentials   // checkmarks, stars, arrows, badges
    case academic     // grade labels, subject icons, formula symbols
    case planner      // calendar bits, priority flags, time markers
    case decorative   // washi-tape strips, corner flourishes, dividers
    case emoji        // curated subset, notebook-friendly style
    case custom       // user imports

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .essentials: return "Essentials"
        case .academic:   return "Academic"
        case .planner:    return "Planner"
        case .decorative: return "Decorative"
        case .emoji:      return "Emoji"
        case .custom:     return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .essentials: return "star.fill"
        case .academic:   return "book.fill"
        case .planner:    return "calendar"
        case .decorative: return "paintpalette.fill"
        case .emoji:      return "face.smiling.fill"
        case .custom:     return "photo.on.rectangle"
        }
    }
}

// MARK: - Sticker Asset

/// Metadata for a sticker in the library (built-in or user-imported).
struct StickerAsset: Codable, Identifiable, Equatable {
    /// Unique identifier used by `StickerInstance.stickerID`.
    let id: String
    var name: String
    var category: StickerCategory
    /// Filename relative to the sticker storage directory.
    let filename: String
    /// Search keywords.
    var tags: [String]
    /// Intrinsic size in points.
    var naturalSize: CGSize
    /// True for user-imported stickers.
    let isCustom: Bool

    // MARK: Codable – CGSize manual handling

    enum CodingKeys: String, CodingKey {
        case id, name, category, filename, tags, naturalWidth, naturalHeight, isCustom
    }

    init(
        id: String,
        name: String,
        category: StickerCategory,
        filename: String,
        tags: [String] = [],
        naturalSize: CGSize = CGSize(width: 64, height: 64),
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.filename = filename
        self.tags = tags
        self.naturalSize = naturalSize
        self.isCustom = isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        category  = try c.decodeIfPresent(StickerCategory.self, forKey: .category) ?? .essentials
        filename  = try c.decode(String.self, forKey: .filename)
        tags      = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        let w     = try c.decodeIfPresent(Double.self, forKey: .naturalWidth) ?? 64
        let h     = try c.decodeIfPresent(Double.self, forKey: .naturalHeight) ?? 64
        naturalSize = CGSize(width: w, height: h)
        isCustom  = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                        forKey: .id)
        try c.encode(name,                      forKey: .name)
        try c.encode(category,                  forKey: .category)
        try c.encode(filename,                  forKey: .filename)
        try c.encode(tags,                      forKey: .tags)
        try c.encode(Double(naturalSize.width),  forKey: .naturalWidth)
        try c.encode(Double(naturalSize.height), forKey: .naturalHeight)
        try c.encode(isCustom,                  forKey: .isCustom)
    }
}

// MARK: - Sticker Constants

enum StickerConstants {
    /// Maximum stickers allowed per page.
    static let maxStickersPerPage = 30
    /// Warning threshold — show subtle "getting crowded" indicator.
    static let stickerWarningThreshold = 20
    /// Minimum scale factor.
    static let minScale: CGFloat = 0.25
    /// Maximum scale factor.
    static let maxScale: CGFloat = 4.0
    /// Default natural size for built-in stickers (points).
    static let defaultNaturalSize = CGSize(width: 64, height: 64)
    /// Maximum custom sticker dimension after processing (points).
    static let maxCustomDimension: CGFloat = 512
    /// Maximum source file size for custom import (bytes).
    static let maxSourceFileSize = 5_000_000  // 5 MB
    /// Maximum processed file size (bytes).
    static let maxProcessedFileSize = 2_000_000  // 2 MB
    /// Snap distance for alignment guides (points).
    static let snapDistance: CGFloat = 6
    /// Rotation snap zone (radians, ~5°).
    static let rotationSnapZone: CGFloat = 5 * .pi / 180
    /// Maximum number of recent stickers to track.
    static let maxRecents = 20
    /// Save debounce interval (seconds).
    static let saveDebounce: TimeInterval = 0.8
}
