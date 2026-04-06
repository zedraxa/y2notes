import Foundation
import CoreGraphics

// MARK: - StickerTintColor

/// RGBA tint override for a sticker.  When nil the sticker is displayed at its
/// original colours.
struct StickerTintColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.red = r; self.green = g; self.blue = b; self.alpha = a
    }
}

// MARK: - StickerObject

/// Metadata for a sticker or decorative element placed on the canvas.
///
/// Built-in stickers are rendered on-demand from Core Graphics drawing closures
/// registered in ``BuiltInStickerPack``.  Third-party stickers store their PNG
/// data inline in ``stickerData``.
struct StickerObject: Codable, Equatable {
    /// Unique identifier within the sticker pack (e.g. "academic.arrow.right").
    var stickerID: String
    /// PNG (or SVG rasterised to PNG) data.  Nil for built-in CG-rendered stickers,
    /// where data is produced at render time.
    var stickerData: Data?
    /// Category name from the pack registry (e.g. "Academic", "Shapes").
    var category: String
    /// Optional recolouring applied on top of the sticker.
    var tintColor: StickerTintColor?
    /// True when the sticker data originated from a built-in pack and can be
    /// regenerated without loading external data.
    var isBuiltIn: Bool

    init(
        stickerID: String,
        stickerData: Data? = nil,
        category: String,
        tintColor: StickerTintColor? = nil,
        isBuiltIn: Bool = true
    ) {
        self.stickerID = stickerID
        self.stickerData = stickerData
        self.category = category
        self.tintColor = tintColor
        self.isBuiltIn = isBuiltIn
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case stickerID, stickerData, category, tintColor, isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stickerID = try c.decode(String.self, forKey: .stickerID)
        stickerData = try c.decodeIfPresent(Data.self, forKey: .stickerData)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        tintColor = try c.decodeIfPresent(StickerTintColor.self, forKey: .tintColor)
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? true
    }
}
