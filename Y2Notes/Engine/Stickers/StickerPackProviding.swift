import Foundation
import UIKit

// MARK: - StickerPackProviding

/// Protocol that any sticker pack must conform to.
///
/// The sticker system is extensible: built-in packs use Core Graphics rendering;
/// third-party packs can store PNG blobs.  All packs register with the shared
/// ``StickerRegistry``.
protocol StickerPackProviding {
    /// Stable identifier for the pack (e.g. "builtin.academic").
    var packID: String { get }
    /// User-visible name shown in the sticker panel header.
    var displayName: String { get }
    /// Small preview icon rendered at `previewSize`.
    func packPreviewImage(size: CGSize) -> UIImage?
    /// All sticker definitions in this pack.
    var stickers: [StickerDefinition] { get }
    /// Renders the sticker identified by `stickerID` at `size`.
    /// Returns `nil` if the ID is not in this pack.
    func render(stickerID: String, size: CGSize) -> UIImage?
}

// MARK: - StickerDefinition

/// Metadata for a single sticker item within a pack.
struct StickerDefinition {
    /// Globally-unique identifier (pack prefix + local name, e.g. "academic.arrow.right").
    let id: String
    /// Pack-level category for grouping in the panel (e.g. "Arrows").
    let category: String
    /// Short user-visible name (e.g. "Arrow Right").
    let displayName: String
    /// SF Symbol fallback shown while the full sticker renders.
    let symbolFallback: String
}

// MARK: - StickerRegistry

/// Global registry that aggregates all registered sticker packs.
final class StickerRegistry {
    static let shared = StickerRegistry()
    private init() {
        register(BuiltInStickerPack.shared)
    }

    private var packs: [String: StickerPackProviding] = [:]

    func register(_ pack: StickerPackProviding) {
        packs[pack.packID] = pack
    }

    var allPacks: [StickerPackProviding] { Array(packs.values) }

    func pack(for packID: String) -> StickerPackProviding? { packs[packID] }

    func render(stickerID: String, size: CGSize) -> UIImage? {
        for pack in packs.values {
            if let image = pack.render(stickerID: stickerID, size: size) { return image }
        }
        return nil
    }
}
