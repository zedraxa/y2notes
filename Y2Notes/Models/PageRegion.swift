import Foundation
import CoreGraphics

// MARK: - Expansion Edge

/// Which edge(s) of a page a canvas expansion extends from.
enum ExpansionEdge: String, Codable, CaseIterable, Equatable {
    /// Expansion extends to the right of the page.
    case right
    /// Expansion extends below the page.
    case bottom
    /// Corner fill region when both right and bottom expansions exist.
    case rightBottom
}

// MARK: - Page Region

/// An expandable canvas region attached to a specific page edge.
///
/// Pages may grow into attached canvas regions when the user needs more space.
/// The original page boundary is always preserved — expansions are "fold-out flaps"
/// that extend the drawable area without altering the page identity.
///
/// Regions are stored sparsely — only pages that have been expanded carry entries.
struct PageRegion: Identifiable, Codable, Equatable {
    /// Stable identity for collaboration / merge.
    let id: UUID
    /// Which page this region extends (0-based index into `Note.pages`).
    var pageIndex: Int
    /// Which edge of the page this expansion attaches to.
    var edge: ExpansionEdge
    /// Extra canvas size beyond the page boundary (width delta, height delta in points).
    var size: CGSize
    /// Serialised `PKDrawing` for the expansion area.
    var drawingData: Data
    /// Widgets placed in the expansion region.
    var widgetLayers: [NoteWidget]
    /// Sticker instances placed in the expansion region.
    var stickerLayers: [StickerInstance]
    /// Shape instances placed in the expansion region.
    var shapeLayers: [ShapeInstance]
    /// Attachment objects placed in the expansion region.
    var attachmentLayers: [AttachmentObject]
    /// When the expansion was first created.
    var createdAt: Date
    /// Whether the expansion is collapsed (hidden but content preserved).
    var isCollapsed: Bool
    /// Monotonic version counter for CRDT-ready merge.
    var version: Int

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        edge: ExpansionEdge,
        size: CGSize,
        drawingData: Data = Data(),
        widgetLayers: [NoteWidget] = [],
        stickerLayers: [StickerInstance] = [],
        shapeLayers: [ShapeInstance] = [],
        attachmentLayers: [AttachmentObject] = [],
        createdAt: Date = Date(),
        isCollapsed: Bool = false,
        version: Int = 0
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.edge = edge
        self.size = size
        self.drawingData = drawingData
        self.widgetLayers = widgetLayers
        self.stickerLayers = stickerLayers
        self.shapeLayers = shapeLayers
        self.attachmentLayers = attachmentLayers
        self.createdAt = createdAt
        self.isCollapsed = isCollapsed
        self.version = version
    }

    // MARK: Custom Codable — CGSize is not Codable by default.

    enum CodingKeys: String, CodingKey {
        case id, pageIndex, edge, width, height, drawingData
        case widgetLayers, stickerLayers, shapeLayers, attachmentLayers
        case createdAt, isCollapsed, version
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        let rawIndex    = try c.decode(Int.self, forKey: .pageIndex)
        pageIndex       = max(0, rawIndex) // Guard against negative indices from corruption
        edge            = try c.decode(ExpansionEdge.self, forKey: .edge)
        let w           = try c.decode(CGFloat.self, forKey: .width)
        let h           = try c.decode(CGFloat.self, forKey: .height)
        size            = CGSize(width: w, height: h)
        drawingData     = try c.decodeIfPresent(Data.self, forKey: .drawingData) ?? Data()
        widgetLayers    = try c.decodeIfPresent([NoteWidget].self, forKey: .widgetLayers) ?? []
        stickerLayers   = try c.decodeIfPresent([StickerInstance].self, forKey: .stickerLayers) ?? []
        shapeLayers     = try c.decodeIfPresent([ShapeInstance].self, forKey: .shapeLayers) ?? []
        attachmentLayers = try c.decodeIfPresent([AttachmentObject].self, forKey: .attachmentLayers) ?? []
        createdAt       = try c.decode(Date.self, forKey: .createdAt)
        isCollapsed     = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        version         = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pageIndex, forKey: .pageIndex)
        try c.encode(edge, forKey: .edge)
        try c.encode(size.width, forKey: .width)
        try c.encode(size.height, forKey: .height)
        try c.encode(drawingData, forKey: .drawingData)
        try c.encode(widgetLayers, forKey: .widgetLayers)
        try c.encode(stickerLayers, forKey: .stickerLayers)
        try c.encode(shapeLayers, forKey: .shapeLayers)
        try c.encode(attachmentLayers, forKey: .attachmentLayers)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isCollapsed, forKey: .isCollapsed)
        try c.encode(version, forKey: .version)
    }
}

// MARK: - Page Region Constants

enum PageRegionConstants {
    /// Maximum right expansion: 2× page width (total 3× width).
    static let maxWidthMultiplier: CGFloat = 2.0
    /// Maximum bottom expansion: 2× page height (total 3× height).
    static let maxHeightMultiplier: CGFloat = 2.0
    /// Minimum expansion size to prevent micro-flaps (points).
    static let minimumExpansionSize: CGFloat = 100
    /// Grid snap interval when resizing expansions (points).
    static let resizeSnapInterval: CGFloat = 50
    /// Buffer distance before expansion boundary to trigger lazy loading (points).
    static let lazyLoadBuffer: CGFloat = 200
    /// Buffer beyond viewport where expansion content can be suspended (points).
    static let suspendBuffer: CGFloat = 300
    /// Maximum expansion regions loaded in memory at once.
    static let maxLoadedRegions: Int = 4
}
