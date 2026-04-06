import Foundation
import CoreGraphics

// MARK: - CanvasObjectWrapper

/// Type-erased, `Codable` container for any ``CanvasObject`` variant.
///
/// All per-page embedded objects are stored as an array of these wrappers.
/// The `objectType` discriminator drives decoding and rendering dispatch.
///
/// - Note: Using a concrete struct rather than an `any CanvasObject` existential
///   keeps `Codable` synthesis simple and avoids existential boxing overhead.
struct CanvasObjectWrapper: Codable, Identifiable, Equatable {
    /// Stable identity — mirrors the wrapped object's `id`.
    let id: UUID
    /// Position and size in page content-coordinate space.
    var frame: CGRect
    /// Rotation in degrees (clockwise positive).
    var rotation: CGFloat
    /// Z-ordering index within the embedded-object layer.
    var zIndex: Int
    /// Prevents the user from moving or resizing this object.
    var isLocked: Bool
    /// Typed payload.
    var objectType: CanvasObjectType

    init(
        id: UUID = UUID(),
        frame: CGRect,
        rotation: CGFloat = 0,
        zIndex: Int = 0,
        isLocked: Bool = false,
        objectType: CanvasObjectType
    ) {
        self.id = id
        self.frame = frame
        self.rotation = rotation
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.objectType = objectType
    }

    // MARK: Codable — CGRect is not Codable natively

    enum CodingKeys: String, CodingKey {
        case id, rotation, zIndex, isLocked, objectType
        case frameX, frameY, frameWidth, frameHeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let x = try c.decodeIfPresent(CGFloat.self, forKey: .frameX) ?? 0
        let y = try c.decodeIfPresent(CGFloat.self, forKey: .frameY) ?? 0
        let w = try c.decodeIfPresent(CGFloat.self, forKey: .frameWidth) ?? 200
        let h = try c.decodeIfPresent(CGFloat.self, forKey: .frameHeight) ?? 200
        frame = CGRect(x: x, y: y, width: w, height: h)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        objectType = try c.decode(CanvasObjectType.self, forKey: .objectType)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(frame.origin.x, forKey: .frameX)
        try c.encode(frame.origin.y, forKey: .frameY)
        try c.encode(frame.size.width, forKey: .frameWidth)
        try c.encode(frame.size.height, forKey: .frameHeight)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(zIndex, forKey: .zIndex)
        try c.encode(isLocked, forKey: .isLocked)
        try c.encode(objectType, forKey: .objectType)
    }
}

// MARK: - Factory helpers

extension CanvasObjectWrapper {
    /// Creates a wrapper for an image object centred in the given visible area.
    static func makeImage(
        _ image: ImageObject,
        centeredIn visibleRect: CGRect,
        size: CGSize = CGSize(width: 300, height: 300)
    ) -> CanvasObjectWrapper {
        let origin = CGPoint(
            x: visibleRect.midX - size.width / 2,
            y: visibleRect.midY - size.height / 2
        )
        return CanvasObjectWrapper(
            frame: CGRect(origin: origin, size: size),
            objectType: .image(image)
        )
    }

    /// Creates a wrapper for an audio clip widget.
    static func makeAudioClip(
        _ clip: AudioClipObject,
        at point: CGPoint
    ) -> CanvasObjectWrapper {
        let size = CGSize(width: 280, height: 80)
        return CanvasObjectWrapper(
            frame: CGRect(origin: point, size: size),
            objectType: .audioClip(clip)
        )
    }

    /// Creates a wrapper for a sticker centred at the given point.
    static func makeSticker(
        _ sticker: StickerObject,
        centeredAt point: CGPoint,
        size: CGSize = CGSize(width: 100, height: 100)
    ) -> CanvasObjectWrapper {
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        return CanvasObjectWrapper(
            frame: CGRect(origin: origin, size: size),
            objectType: .sticker(sticker)
        )
    }

    /// Creates a wrapper for a link chip.
    static func makeLink(
        _ link: LinkObject,
        at point: CGPoint
    ) -> CanvasObjectWrapper {
        let size: CGSize
        switch link.displayStyle {
        case .chip: size = CGSize(width: 220, height: 48)
        case .card: size = CGSize(width: 280, height: 140)
        case .inline: size = CGSize(width: 200, height: 32)
        }
        return CanvasObjectWrapper(
            frame: CGRect(origin: point, size: size),
            objectType: .link(link)
        )
    }

    /// Creates a wrapper for a text block centred at the given point.
    static func makeTextBlock(
        _ textBlock: TextBlockObject,
        centeredAt point: CGPoint,
        size: CGSize = CGSize(width: 240, height: 60)
    ) -> CanvasObjectWrapper {
        let origin = CGPoint(x: point.x - size.width / 2,
                             y: point.y - size.height / 2)
        return CanvasObjectWrapper(
            frame: CGRect(origin: origin, size: size),
            objectType: .textBlock(textBlock)
        )
    }
}
