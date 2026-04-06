import Foundation
import CoreGraphics

// MARK: - Attachment Type

public enum AttachmentType: String, Codable, Equatable {
    case image
    case pdf
    case link
}

// MARK: - Attachment Frame

public struct AttachmentFrame: Codable, Equatable {
    public var position: CGPoint
    public var size: CGSize
    public var rotation: CGFloat

    enum CodingKeys: String, CodingKey {
        case posX, posY, width, height, rotation
    }

    public init(position: CGPoint, size: CGSize, rotation: CGFloat = 0) {
        self.position = position
        self.size = size
        self.rotation = rotation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(CGFloat.self, forKey: .posX)
        let y = try c.decode(CGFloat.self, forKey: .posY)
        position = CGPoint(x: x, y: y)
        let w = try c.decode(CGFloat.self, forKey: .width)
        let h = try c.decode(CGFloat.self, forKey: .height)
        size = CGSize(width: w, height: h)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(position.x, forKey: .posX)
        try c.encode(position.y, forKey: .posY)
        try c.encode(size.width, forKey: .width)
        try c.encode(size.height, forKey: .height)
        try c.encode(rotation, forKey: .rotation)
    }

    public var boundingRect: CGRect {
        CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Attachment Object

public struct AttachmentObject: Codable, Identifiable, Equatable {
    public let id: UUID
    public var type: AttachmentType
    public var frame: AttachmentFrame
    public var label: String
    public var zIndex: Int
    public var isLocked: Bool
    public var aspectRatio: CGFloat
    public var fileExtension: String
    public var linkURL: String?
    public var placedAt: Date

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, frame, label, zIndex, isLocked, aspectRatio
        case fileExtension, linkURL, placedAt
    }

    public init(
        id: UUID = UUID(),
        type: AttachmentType,
        frame: AttachmentFrame,
        label: String = "",
        zIndex: Int = 0,
        isLocked: Bool = false,
        aspectRatio: CGFloat = 1.0,
        fileExtension: String = "jpg",
        linkURL: String? = nil,
        placedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.frame = frame
        self.label = label
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.aspectRatio = aspectRatio
        self.fileExtension = fileExtension
        self.linkURL = linkURL
        self.placedAt = placedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(AttachmentType.self, forKey: .type)
        frame = try c.decode(AttachmentFrame.self, forKey: .frame)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        aspectRatio = try c.decodeIfPresent(CGFloat.self, forKey: .aspectRatio) ?? 1.0
        fileExtension = try c.decodeIfPresent(String.self, forKey: .fileExtension) ?? "jpg"
        linkURL = try c.decodeIfPresent(String.self, forKey: .linkURL)
        placedAt = try c.decodeIfPresent(Date.self, forKey: .placedAt) ?? Date()
    }
}

// MARK: - Constants

public enum AttachmentConstants {
    public static let maxAttachmentsPerPage = 20
    public static let attachmentWarningThreshold = 15
    public static let minimumDimension: CGFloat = 60
    public static let defaultSize = CGSize(width: 200, height: 200)
    public static let thumbnailMaxDimension: CGFloat = 240
    public static let thumbnailQuality: CGFloat = 0.75
    public static let snapDistance: CGFloat = 6
    public static let handleTolerance: CGFloat = 20
    public static let handleRadius: CGFloat = 6
    public static let fullResZoomThreshold: CGFloat = 3.0
    public static let fullResEvictionZoom: CGFloat = 2.5
    public static let maxFullResCache = 3
    public static let saveDebounce: TimeInterval = 0.8
    public static let cardCornerRadius: CGFloat = 8
    public static let selectionBorderWidth: CGFloat = 2
    public static let selectionBorderOpacity: CGFloat = 0.6
    public static let duplicateOffset: CGFloat = 20
}
