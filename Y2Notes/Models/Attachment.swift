import Foundation
import CoreGraphics

// MARK: - Attachment Type

/// The kind of content an attachment represents.
enum AttachmentType: String, Codable, Equatable {
    case image
    case pdf
    case link
}

// MARK: - Attachment Frame

/// Position and size of an attachment on the page canvas.
struct AttachmentFrame: Codable, Equatable {
    /// Centre point in page coordinates (points).
    var position: CGPoint
    /// Display size in page coordinates.
    var size: CGSize
    /// Rotation in radians (reserved for P1 – always 0 for now).
    var rotation: CGFloat

    // Custom Codable – CGPoint / CGSize / CGFloat are not Codable by default.
    enum CodingKeys: String, CodingKey {
        case posX, posY, width, height, rotation
    }

    init(position: CGPoint, size: CGSize, rotation: CGFloat = 0) {
        self.position = position
        self.size = size
        self.rotation = rotation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(CGFloat.self, forKey: .posX)
        let y = try c.decode(CGFloat.self, forKey: .posY)
        position = CGPoint(x: x, y: y)
        let w = try c.decode(CGFloat.self, forKey: .width)
        let h = try c.decode(CGFloat.self, forKey: .height)
        size = CGSize(width: w, height: h)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(position.x, forKey: .posX)
        try c.encode(position.y, forKey: .posY)
        try c.encode(size.width, forKey: .width)
        try c.encode(size.height, forKey: .height)
        try c.encode(rotation, forKey: .rotation)
    }

    /// The bounding rectangle in page coordinates (origin at top-left of the attachment).
    var boundingRect: CGRect {
        CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Attachment Object

/// A single attachment instance placed on a note page.
struct AttachmentObject: Codable, Identifiable, Equatable {
    let id: UUID
    /// Type of content (image, pdf, link).
    var type: AttachmentType
    /// Position and size on the page canvas.
    var frame: AttachmentFrame
    /// Display label shown on the attachment card.
    var label: String
    /// Ordering index within the attachment layer.
    var zIndex: Int
    /// When true the attachment cannot be moved or resized.
    var isLocked: Bool
    /// Aspect ratio (width / height) of the original content, used for proportional resize.
    var aspectRatio: CGFloat
    /// Original file extension for the full-resolution content (e.g. "jpg", "pdf", "png").
    var fileExtension: String
    /// Optional URL for link-type attachments.
    var linkURL: String?
    /// Date the attachment was placed on the page.
    var placedAt: Date

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, frame, label, zIndex, isLocked, aspectRatio
        case fileExtension, linkURL, placedAt
    }

    init(
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

    init(from decoder: Decoder) throws {
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

enum AttachmentConstants {
    static let maxAttachmentsPerPage = 20
    static let attachmentWarningThreshold = 15

    /// Minimum display dimension in page points.
    static let minimumDimension: CGFloat = 60
    /// Default card size for newly placed attachments.
    static let defaultSize = CGSize(width: 200, height: 200)

    /// Thumbnail size (pixels) for the lightweight preview.
    static let thumbnailMaxDimension: CGFloat = 240
    /// JPEG compression quality for thumbnails.
    static let thumbnailQuality: CGFloat = 0.75

    /// Distance (points) for snap-to-guide behaviour.
    static let snapDistance: CGFloat = 6
    /// Hit-test tolerance around corner handles (points).
    static let handleTolerance: CGFloat = 20
    /// Visual handle radius drawn at corners when selected.
    static let handleRadius: CGFloat = 6

    /// Zoom scale threshold that triggers full-resolution loading.
    static let fullResZoomThreshold: CGFloat = 3.0
    /// Hysteresis: full-res images evicted below this zoom level.
    static let fullResEvictionZoom: CGFloat = 2.5
    /// Maximum number of full-resolution images kept in cache.
    static let maxFullResCache = 3

    /// Debounce interval (seconds) before persisting attachment changes.
    static let saveDebounce: TimeInterval = 0.8

    /// Corner radius for the attachment card background.
    static let cardCornerRadius: CGFloat = 8
    /// Selection border width.
    static let selectionBorderWidth: CGFloat = 2
    /// Selection border opacity.
    static let selectionBorderOpacity: CGFloat = 0.6

    /// Offset used when duplicating an attachment.
    static let duplicateOffset: CGFloat = 20
}
