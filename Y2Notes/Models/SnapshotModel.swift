import Foundation

// MARK: - Note Snapshot Model
//
// Lightweight, immutable records that capture note state at a point in time.
// Each snapshot stores only the pages that changed, plus note-level metadata.
// Actual page data is kept on disk; the in-memory index holds metadata only.

/// A single point-in-time capture of a note's state.
struct NoteSnapshot: Codable, Identifiable {
    /// Unique identifier for this snapshot.
    let id: UUID
    /// The note this snapshot belongs to.
    let noteID: UUID
    /// Monotonic sequence number within this note's history (0-based).
    let sequenceNumber: Int
    /// Wall-clock time when the snapshot was created.
    let createdAt: Date
    /// ID of the snapshot this one was derived from (DAG parent for future sync).
    let parentSnapshotID: UUID?
    /// Which page indices were captured (dirty pages at the time of snapshot).
    let changedPageIndices: [Int]
    /// Total page count of the note at snapshot time.
    let totalPageCount: Int
    /// Note title at snapshot time.
    let title: String
    /// Note `modifiedAt` value at snapshot time.
    let noteModifiedAt: Date
    /// Human-readable summary of changes (e.g., "Page 3 edited", "Title changed").
    let summary: String
    /// Size in bytes of the snapshot's on-disk page data (for budget tracking).
    let dataSizeBytes: Int
    /// Whether the user has pinned this snapshot to prevent automatic pruning.
    var isPinned: Bool
    /// The trigger that caused this snapshot.
    let trigger: SnapshotTrigger

    init(
        noteID: UUID,
        sequenceNumber: Int,
        parentSnapshotID: UUID? = nil,
        changedPageIndices: [Int],
        totalPageCount: Int,
        title: String,
        noteModifiedAt: Date,
        summary: String,
        dataSizeBytes: Int,
        isPinned: Bool = false,
        trigger: SnapshotTrigger = .autosave
    ) {
        self.id = UUID()
        self.noteID = noteID
        self.sequenceNumber = sequenceNumber
        self.createdAt = Date()
        self.parentSnapshotID = parentSnapshotID
        self.changedPageIndices = changedPageIndices
        self.totalPageCount = totalPageCount
        self.title = title
        self.noteModifiedAt = noteModifiedAt
        self.summary = summary
        self.dataSizeBytes = dataSizeBytes
        self.isPinned = isPinned
        self.trigger = trigger
    }
}

/// What caused a snapshot to be created.
enum SnapshotTrigger: String, Codable {
    /// Background autosave timer fired.
    case autosave
    /// App is entering the background.
    case lifecycle
    /// Explicit user action ("Save version").
    case manual
    /// Created automatically before a destructive operation (delete, restore).
    case preDestructive
    /// Created automatically before a restore so the restore is reversible.
    case preRestore
}

/// Per-note snapshot history index — the lightweight metadata kept in memory.
/// The actual page data lives in per-snapshot files on disk.
struct SnapshotHistoryIndex: Codable {
    var version: Int = 1
    var noteID: UUID
    var snapshots: [NoteSnapshot] = []
    /// Next sequence number to assign.
    var nextSequenceNumber: Int = 0
}

// MARK: - Snapshot page data (on-disk only)

/// The data payload stored in each snapshot file on disk.
/// Contains only the pages that changed — unchanged pages reference
/// previous snapshots (copy-on-write at the page level).
struct SnapshotPageData: Codable {
    let snapshotID: UUID
    /// Maps page index → serialised PKDrawing bytes.
    let pages: [Int: Data]
    /// Sticker layers for changed pages (page index → stickers).
    let stickerLayers: [Int: [StickerInstance]]
    /// Shape layers for changed pages.
    let shapeLayers: [Int: [ShapeInstance]]
    /// Attachment metadata for changed pages.
    let attachmentLayers: [Int: [AttachmentObject]]
    /// Expansion regions at snapshot time (full array — sparse, only pages with expansions).
    let expansionRegions: [PageRegion]

    // MARK: Custom Codable — Dictionary<Int, _> needs String keys in JSON

    enum CodingKeys: String, CodingKey {
        case snapshotID, pages, stickerLayers, shapeLayers, attachmentLayers, expansionRegions
    }

    init(
        snapshotID: UUID,
        pages: [Int: Data],
        stickerLayers: [Int: [StickerInstance]] = [:],
        shapeLayers: [Int: [ShapeInstance]] = [:],
        attachmentLayers: [Int: [AttachmentObject]] = [:],
        expansionRegions: [PageRegion] = []
    ) {
        self.snapshotID = snapshotID
        self.pages = pages
        self.stickerLayers = stickerLayers
        self.shapeLayers = shapeLayers
        self.attachmentLayers = attachmentLayers
        self.expansionRegions = expansionRegions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snapshotID = try c.decode(UUID.self, forKey: .snapshotID)

        let rawPages = try c.decode([String: Data].self, forKey: .pages)
        pages = Dictionary(uniqueKeysWithValues: rawPages.compactMap { k, v in Int(k).map { ($0, v) } })

        let rawStickers = try c.decodeIfPresent([String: [StickerInstance]].self, forKey: .stickerLayers) ?? [:]
        stickerLayers = Dictionary(uniqueKeysWithValues: rawStickers.compactMap { k, v in Int(k).map { ($0, v) } })

        let rawShapes = try c.decodeIfPresent([String: [ShapeInstance]].self, forKey: .shapeLayers) ?? [:]
        shapeLayers = Dictionary(uniqueKeysWithValues: rawShapes.compactMap { k, v in Int(k).map { ($0, v) } })

        let rawAttachments = try c.decodeIfPresent([String: [AttachmentObject]].self, forKey: .attachmentLayers) ?? [:]
        attachmentLayers = Dictionary(uniqueKeysWithValues: rawAttachments.compactMap { k, v in Int(k).map { ($0, v) } })

        expansionRegions = try c.decodeIfPresent([PageRegion].self, forKey: .expansionRegions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(snapshotID, forKey: .snapshotID)

        let stringPages = Dictionary(uniqueKeysWithValues: pages.map { ("\($0.key)", $0.value) })
        try c.encode(stringPages, forKey: .pages)

        let stringStickers = Dictionary(uniqueKeysWithValues: stickerLayers.map { ("\($0.key)", $0.value) })
        try c.encode(stringStickers, forKey: .stickerLayers)

        let stringShapes = Dictionary(uniqueKeysWithValues: shapeLayers.map { ("\($0.key)", $0.value) })
        try c.encode(stringShapes, forKey: .shapeLayers)

        let stringAttachments = Dictionary(uniqueKeysWithValues: attachmentLayers.map { ("\($0.key)", $0.value) })
        try c.encode(stringAttachments, forKey: .attachmentLayers)

        try c.encode(expansionRegions, forKey: .expansionRegions)
    }
}

// MARK: - Retention tiers

/// Defines the tiered retention policy for snapshot compaction.
enum SnapshotRetention {
    struct Tier {
        let maxAge: TimeInterval
        let interval: TimeInterval
    }

    /// Last 1 hour: keep every 1-minute snapshot.
    static let hourly = Tier(maxAge: 3_600, interval: 60)
    /// Last 24 hours: keep 1 per 10 minutes.
    static let daily = Tier(maxAge: 86_400, interval: 600)
    /// Last 7 days: keep 1 per hour.
    static let weekly = Tier(maxAge: 604_800, interval: 3_600)
    /// Last 30 days: keep 1 per day.
    static let monthly = Tier(maxAge: 2_592_000, interval: 86_400)

    /// Ordered from finest to coarsest granularity.
    static let allTiers = [hourly, daily, weekly, monthly]

    /// Total disk budget for all history across all notes.
    static let diskBudgetBytes: Int64 = 100 * 1024 * 1024  // 100 MB
}
