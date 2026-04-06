import Foundation
import CoreGraphics

// MARK: - Expansion Edge

public enum ExpansionEdge: String, Codable, CaseIterable, Equatable {
    case right
    case bottom
    case rightBottom
}

// MARK: - Page Region

public struct PageRegion: Identifiable, Codable, Equatable {
    public let id: UUID
    public var pageIndex: Int
    public var edge: ExpansionEdge
    public var size: CGSize
    public var drawingData: Data
    public var widgetLayers: [NoteWidget]
    public var stickerLayers: [StickerInstance]
    public var shapeLayers: [ShapeInstance]
    public var attachmentLayers: [AttachmentObject]
    public var createdAt: Date
    public var isCollapsed: Bool
    public var version: Int

    public init(
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

    // MARK: Custom Codable

    enum CodingKeys: String, CodingKey {
        case id, pageIndex, edge, width, height, drawingData
        case widgetLayers, stickerLayers, shapeLayers, attachmentLayers
        case createdAt, isCollapsed, version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        let rawIndex    = try c.decode(Int.self, forKey: .pageIndex)
        pageIndex       = max(0, rawIndex)
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

    public func encode(to encoder: Encoder) throws {
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

public enum PageRegionConstants {
    public static let maxWidthMultiplier: CGFloat = 2.0
    public static let maxHeightMultiplier: CGFloat = 2.0
    public static let minimumExpansionSize: CGFloat = 100
    public static let resizeSnapInterval: CGFloat = 50
    public static let lazyLoadBuffer: CGFloat = 200
    public static let suspendBuffer: CGFloat = 300
    public static let maxLoadedRegions: Int = 4
}
