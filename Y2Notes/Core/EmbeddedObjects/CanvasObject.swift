import Foundation
import CoreGraphics

// MARK: - CanvasObjectType

/// Discriminator enum that carries the typed payload for each embedded object.
enum CanvasObjectType: Codable, Equatable {
    case image(ImageObject)
    case scannedDocument(ScannedDocObject)
    case audioClip(AudioClipObject)
    case sticker(StickerObject)
    case link(LinkObject)
    case textBlock(TextBlockObject)

    // MARK: Codable

    private enum TypeKey: String, CodingKey { case type }
    private enum PayloadKey: String, CodingKey { case payload }

    private enum TypeName: String, Codable {
        case image, scannedDocument, audioClip, sticker, link, textBlock
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: TypeKey.self)
        let name = try root.decode(TypeName.self, forKey: .type)
        let payload = try decoder.container(keyedBy: PayloadKey.self)
        switch name {
        case .image:
            self = .image(try payload.decode(ImageObject.self, forKey: .payload))
        case .scannedDocument:
            self = .scannedDocument(try payload.decode(ScannedDocObject.self, forKey: .payload))
        case .audioClip:
            self = .audioClip(try payload.decode(AudioClipObject.self, forKey: .payload))
        case .sticker:
            self = .sticker(try payload.decode(StickerObject.self, forKey: .payload))
        case .link:
            self = .link(try payload.decode(LinkObject.self, forKey: .payload))
        case .textBlock:
            self = .textBlock(try payload.decode(TextBlockObject.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: TypeKey.self)
        var payload = encoder.container(keyedBy: PayloadKey.self)
        switch self {
        case .image(let obj):
            try root.encode(TypeName.image, forKey: .type)
            try payload.encode(obj, forKey: .payload)
        case .scannedDocument(let obj):
            try root.encode(TypeName.scannedDocument, forKey: .type)
            try payload.encode(obj, forKey: .payload)
        case .audioClip(let obj):
            try root.encode(TypeName.audioClip, forKey: .type)
            try payload.encode(obj, forKey: .payload)
        case .sticker(let obj):
            try root.encode(TypeName.sticker, forKey: .type)
            try payload.encode(obj, forKey: .payload)
        case .link(let obj):
            try root.encode(TypeName.link, forKey: .type)
            try payload.encode(obj, forKey: .payload)
        case .textBlock(let obj):
            try root.encode(TypeName.textBlock, forKey: .type)
            try payload.encode(obj, forKey: .payload)
        }
    }
}

// MARK: - CanvasObject Protocol

/// Common interface for all embedded objects that live on the canvas.
///
/// Objects are positioned in page content-coordinate space — the same
/// coordinate system used by `PKDrawing` strokes.  The overlay controller
/// applies the canvas zoom/scroll transform so objects move in sync with ink.
protocol CanvasObject: Codable, Identifiable, Equatable where ID == UUID {
    /// Stable identity — survives serialisation round-trips.
    var id: UUID { get }
    /// Bounding rectangle in page content coordinates.
    var frame: CGRect { get set }
    /// Rotation in degrees (clockwise positive).
    var rotation: CGFloat { get set }
    /// Z-ordering index within the object layer.  Higher = closer to user.
    var zIndex: Int { get set }
    /// When true, the user cannot move or resize this object.
    var isLocked: Bool { get set }
    /// Typed payload identifying what kind of object this is.
    var objectType: CanvasObjectType { get }
}

// MARK: - ScannedDocObject

/// A document page captured via the VisionKit document scanner.
struct ScannedDocObject: Codable, Equatable {
    /// Filename inside Documents/Scans/ (no path, just name+ext).
    var filename: String
    /// Original page index within the scan session (0-based).
    var pageIndex: Int
    /// JPEG thumbnail for quick display (pre-rendered at scan time).
    var thumbnailData: Data?
}

// MARK: - TextBlockObject

/// Typed or pasted text rendered as a floating box on the canvas.
struct TextBlockObject: Codable, Equatable {
    var text: String
    /// Encoded font descriptor data (NSKeyedArchiver of UIFontDescriptor).
    var fontData: Data?
    var fontSize: CGFloat
    /// Hex colour string, e.g. "#1A1A1A".
    var textColorHex: String
    var backgroundColorHex: String?
    var isBold: Bool
    var isItalic: Bool
    var alignment: Int  // NSTextAlignment raw value
}
