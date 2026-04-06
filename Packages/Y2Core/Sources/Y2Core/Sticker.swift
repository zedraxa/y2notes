import Foundation
import UIKit

// MARK: - Sticker Instance

public struct StickerInstance: Codable, Identifiable, Equatable {
    public let id: UUID
    public let stickerID: String
    public var position: CGPoint
    public var scale: CGFloat
    public var rotation: CGFloat
    public var opacity: CGFloat
    public var zIndex: Int
    public var isLocked: Bool
    public let placedAt: Date

    public init(
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

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, stickerID, posX, posY, scale, rotation, opacity, zIndex, isLocked, placedAt
    }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public enum StickerCategory: String, Codable, CaseIterable, Identifiable {
    case essentials
    case academic
    case planner
    case decorative
    case emoji
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .essentials: return "Essentials"
        case .academic:   return "Academic"
        case .planner:    return "Planner"
        case .decorative: return "Decorative"
        case .emoji:      return "Emoji"
        case .custom:     return "Custom"
        }
    }

    public var systemImage: String {
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

public struct StickerAsset: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var category: StickerCategory
    public let filename: String
    public var tags: [String]
    public var naturalSize: CGSize
    public let isCustom: Bool

    // MARK: Codable – CGSize manual handling

    enum CodingKeys: String, CodingKey {
        case id, name, category, filename, tags, naturalWidth, naturalHeight, isCustom
    }

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public enum StickerConstants {
    public static let maxStickersPerPage = 30
    public static let stickerWarningThreshold = 20
    public static let minScale: CGFloat = 0.25
    public static let maxScale: CGFloat = 4.0
    public static let defaultNaturalSize = CGSize(width: 64, height: 64)
    public static let maxCustomDimension: CGFloat = 512
    public static let maxSourceFileSize = 5_000_000
    public static let maxProcessedFileSize = 2_000_000
    public static let snapDistance: CGFloat = 6
    public static let rotationSnapZone: CGFloat = 5 * .pi / 180
    public static let maxRecents = 20
    public static let saveDebounce: TimeInterval = 0.8
}
