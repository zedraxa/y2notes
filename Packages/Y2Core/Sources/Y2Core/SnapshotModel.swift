import Foundation

// MARK: - Note Snapshot Model

public struct NoteSnapshot: Codable, Identifiable {
    public let id: UUID
    public let noteID: UUID
    public let sequenceNumber: Int
    public let createdAt: Date
    public let parentSnapshotID: UUID?
    public let changedPageIndices: [Int]
    public let totalPageCount: Int
    public let title: String
    public let noteModifiedAt: Date
    public let summary: String
    public let dataSizeBytes: Int
    public var isPinned: Bool
    public let trigger: SnapshotTrigger

    public init(
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

public enum SnapshotTrigger: String, Codable {
    case autosave
    case lifecycle
    case manual
    case preDestructive
    case preRestore
}

public struct SnapshotHistoryIndex: Codable {
    public var version: Int = 1
    public var noteID: UUID
    public var snapshots: [NoteSnapshot] = []
    public var nextSequenceNumber: Int = 0

    public init(version: Int = 1, noteID: UUID, snapshots: [NoteSnapshot] = [], nextSequenceNumber: Int = 0) {
        self.version = version
        self.noteID = noteID
        self.snapshots = snapshots
        self.nextSequenceNumber = nextSequenceNumber
    }
}

// MARK: - Snapshot page data

public struct SnapshotPageData: Codable {
    public let snapshotID: UUID
    public let pages: [Int: Data]
    public let stickerLayers: [Int: [StickerInstance]]
    public let shapeLayers: [Int: [ShapeInstance]]
    public let attachmentLayers: [Int: [AttachmentObject]]
    public let expansionRegions: [PageRegion]

    enum CodingKeys: String, CodingKey {
        case snapshotID, pages, stickerLayers, shapeLayers, attachmentLayers, expansionRegions
    }

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public enum SnapshotRetention {
    public struct Tier {
        public let maxAge: TimeInterval
        public let interval: TimeInterval

        public init(maxAge: TimeInterval, interval: TimeInterval) {
            self.maxAge = maxAge
            self.interval = interval
        }
    }

    public static let hourly = Tier(maxAge: 3_600, interval: 60)
    public static let daily = Tier(maxAge: 86_400, interval: 600)
    public static let weekly = Tier(maxAge: 604_800, interval: 3_600)
    public static let monthly = Tier(maxAge: 2_592_000, interval: 86_400)
    public static let allTiers = [hourly, daily, weekly, monthly]
    public static let diskBudgetBytes: Int64 = 100 * 1024 * 1024
}
