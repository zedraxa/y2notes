import Foundation
import UIKit
import os

private let stickerLogger = Logger(subsystem: "com.y2notes", category: "StickerStore")

/// Manages the sticker asset library: built-in manifest, custom imports,
/// favorites, and recents.  Persists lightweight JSON indices to Documents.
///
/// This store does NOT manage placed stickers — those live inside
/// `Note.stickerLayers` and are saved/loaded by `NoteStore`.
@MainActor
final class StickerStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var builtinAssets: [StickerAsset] = []
    @Published private(set) var customAssets: [StickerAsset] = []
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var recentIDs: [String] = []

    // MARK: - Computed

    /// All assets across built-in + custom.
    var allAssets: [StickerAsset] { builtinAssets + customAssets }

    /// Assets in a given category.
    func assets(for category: StickerCategory) -> [StickerAsset] {
        allAssets.filter { $0.category == category }
    }

    /// Favorite assets, preserving insertion order.
    var favorites: [StickerAsset] {
        allAssets.filter { favoriteIDs.contains($0.id) }
    }

    /// Most-recently-placed assets.
    var recents: [StickerAsset] {
        recentIDs.compactMap { id in allAssets.first(where: { $0.id == id }) }
    }

    /// Search across name and tags.
    func search(query: String) -> [StickerAsset] {
        guard !query.isEmpty else { return allAssets }
        let q = query.lowercased()
        return allAssets.filter { asset in
            asset.name.lowercased().contains(q) ||
            asset.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    /// Look up an asset by its ID.
    func asset(for id: String) -> StickerAsset? {
        allAssets.first(where: { $0.id == id })
    }

    // MARK: - Image Loading

    /// Image cache to avoid re-decoding on every render pass.
    private let imageCache = NSCache<NSString, UIImage>()

    /// Returns the UIImage for the given asset, cached.
    func image(for asset: StickerAsset) -> UIImage? {
        let key = asset.id as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let img: UIImage?
        if asset.isCustom {
            let url = customStickersDir.appendingPathComponent(asset.filename)
            img = UIImage(contentsOfFile: url.path)
        } else {
            // Prefer a bundle PNG; fall back to the programmatic renderer.
            img = UIImage(named: asset.filename) ?? StickerRenderer.render(id: asset.id)
        }
        if let img {
            imageCache.setObject(img, forKey: key)
        }
        return img
    }

    // MARK: - Favorites

    func toggleFavorite(_ stickerID: String) {
        if favoriteIDs.contains(stickerID) {
            favoriteIDs.remove(stickerID)
        } else {
            favoriteIDs.insert(stickerID)
        }
        persistFavorites()
    }

    func isFavorite(_ stickerID: String) -> Bool {
        favoriteIDs.contains(stickerID)
    }

    // MARK: - Recents

    func recordRecent(_ stickerID: String) {
        recentIDs.removeAll(where: { $0 == stickerID })
        recentIDs.insert(stickerID, at: 0)
        if recentIDs.count > StickerConstants.maxRecents {
            recentIDs = Array(recentIDs.prefix(StickerConstants.maxRecents))
        }
        persistRecents()
    }

    // MARK: - Custom Import

    /// Imports an image as a custom sticker.  Returns the new `StickerAsset`
    /// or nil if the image is invalid / too large.
    @discardableResult
    func importCustomSticker(image sourceImage: UIImage, name: String = "Custom Sticker") -> StickerAsset? {
        // Resize to max dimension
        let maxDim = StickerConstants.maxCustomDimension
        let size = sourceImage.size
        let scale: CGFloat
        if size.width > maxDim || size.height > maxDim {
            scale = min(maxDim / size.width, maxDim / size.height)
        } else {
            scale = 1.0
        }
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let processed = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let pngData = processed.pngData() else { return nil }
        guard pngData.count <= StickerConstants.maxProcessedFileSize else { return nil }

        let uuid = UUID().uuidString
        let filename = "\(uuid).png"

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: customStickersDir, withIntermediateDirectories: true)
        let fileURL = customStickersDir.appendingPathComponent(filename)
        do {
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            stickerLogger.error("Failed to write custom sticker: \(error.localizedDescription, privacy: .public)")
            #endif
            return nil
        }

        let asset = StickerAsset(
            id: uuid,
            name: name,
            category: .custom,
            filename: filename,
            tags: [],
            naturalSize: targetSize,
            isCustom: true
        )
        customAssets.append(asset)
        persistCustomAssets()

        // Cache the image immediately
        imageCache.setObject(processed, forKey: uuid as NSString)

        return asset
    }

    /// Removes a custom sticker from the library and deletes the file.
    func deleteCustomSticker(id: String) {
        guard let asset = customAssets.first(where: { $0.id == id }), asset.isCustom else { return }
        let fileURL = customStickersDir.appendingPathComponent(asset.filename)
        try? FileManager.default.removeItem(at: fileURL)
        customAssets.removeAll(where: { $0.id == id })
        favoriteIDs.remove(id)
        recentIDs.removeAll(where: { $0 == id })
        imageCache.removeObject(forKey: id as NSString)
        persistCustomAssets()
        persistFavorites()
        persistRecents()
    }

    // MARK: - Init

    init() {
        imageCache.countLimit = 100
        imageCache.totalCostLimit = 20 * 1024 * 1024  // 20 MB
        loadBuiltinManifest()
        loadCustomAssets()
        loadFavorites()
        loadRecents()
    }

    // MARK: - File URLs

    private var stickersDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Stickers", isDirectory: true)
    }

    private var customStickersDir: URL {
        stickersDir.appendingPathComponent("CustomStickers", isDirectory: true)
    }

    private var customAssetsURL: URL {
        stickersDir.appendingPathComponent("custom_stickers.json")
    }

    private var favoritesURL: URL {
        stickersDir.appendingPathComponent("favorites.json")
    }

    private var recentsURL: URL {
        stickersDir.appendingPathComponent("recents.json")
    }

    // MARK: - Built-in Manifest

    /// Seeds the built-in sticker catalog.
    /// In a shipping app these would be PNG assets in Stickers.xcassets with a
    /// bundled JSON manifest.  For now we generate placeholder metadata so the
    /// library UI has something to show.
    private func loadBuiltinManifest() {
        builtinAssets = Self.defaultBuiltinAssets
    }

    /// Placeholder built-in stickers.  Replace with real asset-catalog PNGs.
    static let defaultBuiltinAssets: [StickerAsset] = {
        var assets: [StickerAsset] = []

        let essentials: [(String, String, [String])] = [
            ("star-gold",       "Gold Star",        ["star", "rating", "favorite", "achievement"]),
            ("checkmark-green", "Green Checkmark",  ["check", "done", "complete", "yes"]),
            ("arrow-right",     "Arrow Right",      ["arrow", "direction", "pointer"]),
            ("badge-important", "Important Badge",  ["badge", "important", "alert"]),
            ("heart-red",       "Red Heart",        ["heart", "love", "favorite"]),
            ("thumbsup",        "Thumbs Up",        ["thumb", "like", "good"]),
            ("lightning-bolt",  "Lightning Bolt",   ["lightning", "bolt", "energy", "power", "electric"]),
            ("trophy-gold",     "Gold Trophy",      ["trophy", "award", "win", "achievement", "first"]),
            ("exclamation-red", "Red Exclamation",  ["exclamation", "attention", "warning", "notice"]),
            ("pin-push",        "Push Pin",         ["pin", "tack", "note", "mark", "board"]),
        ]
        for (id, name, tags) in essentials {
            assets.append(StickerAsset(id: id, name: name, category: .essentials, filename: "sticker_\(id)", tags: tags))
        }

        let academic: [(String, String, [String])] = [
            ("grade-a",           "Grade A",          ["grade", "school", "excellent"]),
            ("book-open",         "Open Book",        ["book", "reading", "study"]),
            ("formula-e",         "Euler Formula",    ["math", "formula", "equation"]),
            ("microscope",        "Microscope",       ["science", "lab", "biology"]),
            ("pencil-sharp",      "Sharp Pencil",     ["pencil", "write", "draft", "note"]),
            ("lightbulb-idea",    "Light Bulb",       ["idea", "light", "think", "concept", "bulb"]),
            ("globe-world",       "World Globe",      ["globe", "world", "geography", "earth"]),
            ("chemistry-flask",   "Chemistry Flask",  ["chemistry", "flask", "science", "experiment", "beaker"]),
        ]
        for (id, name, tags) in academic {
            assets.append(StickerAsset(id: id, name: name, category: .academic, filename: "sticker_\(id)", tags: tags))
        }

        let planner: [(String, String, [String])] = [
            ("flag-priority",  "Priority Flag",  ["flag", "priority", "urgent"]),
            ("clock-time",     "Clock",          ["clock", "time", "deadline"]),
            ("calendar-day",   "Calendar Day",   ["calendar", "date", "schedule"]),
            ("pin-location",   "Location Pin",   ["pin", "location", "place"]),
            ("target-goal",    "Bullseye Target", ["target", "goal", "aim", "focus", "bullseye"]),
            ("hourglass-time", "Hourglass",       ["hourglass", "time", "deadline", "waiting", "sand"]),
            ("rocket-launch",  "Rocket Launch",   ["rocket", "launch", "start", "boost", "fast"]),
            ("notepad-memo",   "Notepad",         ["notepad", "memo", "notes", "list", "write"]),
        ]
        for (id, name, tags) in planner {
            assets.append(StickerAsset(id: id, name: name, category: .planner, filename: "sticker_\(id)", tags: tags))
        }

        let decorative: [(String, String, [String])] = [
            ("washi-stripe",    "Washi Tape Stripe",  ["washi", "tape", "decoration"]),
            ("corner-flourish", "Corner Flourish",    ["corner", "flourish", "ornament"]),
            ("divider-dots",    "Dot Divider",        ["divider", "dots", "separator"]),
            ("frame-simple",    "Simple Frame",       ["frame", "border", "box"]),
            ("rainbow-arc",     "Rainbow Arc",        ["rainbow", "colorful", "bright", "arc", "colors"]),
            ("leaf-green",      "Green Leaf",         ["leaf", "nature", "plant", "organic", "green"]),
            ("cloud-fluffy",    "Fluffy Cloud",       ["cloud", "sky", "soft", "fluffy", "weather"]),
            ("diamond-gem",     "Diamond",            ["diamond", "gem", "precious", "crystal", "jewel"]),
        ]
        for (id, name, tags) in decorative {
            assets.append(StickerAsset(id: id, name: name, category: .decorative, filename: "sticker_\(id)", tags: tags))
        }

        let emoji: [(String, String, [String])] = [
            ("smile-happy",   "Happy Smile",    ["smile", "happy", "face"]),
            ("face-think",    "Thinking Face",  ["think", "face", "hmm"]),
            ("fire-hot",      "Fire",           ["fire", "hot", "trending"]),
            ("sparkles",      "Sparkles",       ["sparkle", "shine", "magic"]),
            ("clover-lucky",  "Lucky Clover",   ["clover", "luck", "lucky", "green", "four"]),
            ("snowflake-ice", "Snowflake",      ["snowflake", "snow", "winter", "cold", "ice"]),
            ("gem-crystal",   "Crystal Gem",    ["gem", "crystal", "precious", "purple", "jewel"]),
            ("music-note",    "Music Note",     ["music", "note", "sound", "song", "melody"]),
        ]
        for (id, name, tags) in emoji {
            assets.append(StickerAsset(id: id, name: name, category: .emoji, filename: "sticker_\(id)", tags: tags))
        }

        return assets
    }()

    // MARK: - Persistence Helpers

    private func loadCustomAssets() {
        guard let data = try? Data(contentsOf: customAssetsURL),
              let loaded = try? JSONDecoder().decode([StickerAsset].self, from: data) else { return }
        customAssets = loaded
    }

    private func persistCustomAssets() {
        try? FileManager.default.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(customAssets) else { return }
        try? data.write(to: customAssetsURL, options: .atomic)
    }

    private func loadFavorites() {
        guard let data = try? Data(contentsOf: favoritesURL),
              let loaded = try? JSONDecoder().decode([String].self, from: data) else { return }
        favoriteIDs = Set(loaded)
    }

    private func persistFavorites() {
        try? FileManager.default.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Array(favoriteIDs)) else { return }
        try? data.write(to: favoritesURL, options: .atomic)
    }

    private func loadRecents() {
        guard let data = try? Data(contentsOf: recentsURL),
              let loaded = try? JSONDecoder().decode([String].self, from: data) else { return }
        recentIDs = loaded
    }

    private func persistRecents() {
        try? FileManager.default.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(recentIDs) else { return }
        try? data.write(to: recentsURL, options: .atomic)
    }
}
