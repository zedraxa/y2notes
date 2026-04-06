import Foundation
import UIKit
import SwiftUI

// MARK: - Note color label

/// A visual color label that can be assigned to a note for quick category recognition.
/// Mirrors the "colored dot" feature in GoodNotes 6 and Apple Notes.
public enum NoteColorLabel: String, Codable, CaseIterable, Identifiable {
    case red    = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green  = "green"
    case teal   = "teal"
    case blue   = "blue"
    case purple = "purple"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .red:    return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .teal:   return "Teal"
        case .blue:   return "Blue"
        case .purple: return "Purple"
        }
    }

    public var color: Color {
        switch self {
        case .red:    return Color(red: 0.90, green: 0.24, blue: 0.18)
        case .orange: return Color(red: 1.00, green: 0.55, blue: 0.10)
        case .yellow: return Color(red: 1.00, green: 0.80, blue: 0.10)
        case .green:  return Color(red: 0.18, green: 0.72, blue: 0.40)
        case .teal:   return Color(red: 0.18, green: 0.66, blue: 0.72)
        case .blue:   return Color(red: 0.20, green: 0.50, blue: 0.95)
        case .purple: return Color(red: 0.58, green: 0.20, blue: 0.85)
        }
    }

    public var uiColor: UIColor {
        switch self {
        case .red:    return UIColor(red: 0.90, green: 0.24, blue: 0.18, alpha: 1)
        case .orange: return UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1)
        case .yellow: return UIColor(red: 1.00, green: 0.80, blue: 0.10, alpha: 1)
        case .green:  return UIColor(red: 0.18, green: 0.72, blue: 0.40, alpha: 1)
        case .teal:   return UIColor(red: 0.18, green: 0.66, blue: 0.72, alpha: 1)
        case .blue:   return UIColor(red: 0.20, green: 0.50, blue: 0.95, alpha: 1)
        case .purple: return UIColor(red: 0.58, green: 0.20, blue: 0.85, alpha: 1)
        }
    }
}

// MARK: - Note model

public struct Note: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date

    public var pages: [Data]

    public var drawingData: Data {
        get { pages.first ?? Data() }
        set {
            if pages.isEmpty {
                pages = [newValue]
            } else {
                pages[0] = newValue
            }
        }
    }

    public var isFavorited: Bool
    public var notebookID: UUID?
    public var sectionID: UUID?
    public var sortOrder: Int
    public var templateID: String
    public var themeOverride: AppTheme?
    public var pageType: PageType?
    public var pageTypes: [PageType?]

    public func pageType(forPage index: Int) -> PageType? {
        guard index >= 0 && index < pageTypes.count else { return pageType }
        return pageTypes[index] ?? pageType
    }

    public var paperMaterial: PaperMaterial?
    public var pageColors: [[Double]?]
    public var stickerLayers: [[StickerInstance]?]
    public var shapeLayers: [[ShapeInstance]?]
    public var attachmentLayers: [[AttachmentObject]?]
    public var widgetLayers: [[NoteWidget]?]
    public var textLayers: [[TextObject]?]
    public var expansionRegions: [PageRegion]

    public func stickers(forPage index: Int) -> [StickerInstance] {
        guard index >= 0 && index < stickerLayers.count else { return [] }
        return stickerLayers[index] ?? []
    }

    public func shapes(forPage index: Int) -> [ShapeInstance] {
        guard index >= 0 && index < shapeLayers.count else { return [] }
        return shapeLayers[index] ?? []
    }

    public func attachments(forPage index: Int) -> [AttachmentObject] {
        guard index >= 0 && index < attachmentLayers.count else { return [] }
        return attachmentLayers[index] ?? []
    }

    public func widgets(forPage index: Int) -> [NoteWidget] {
        guard index >= 0 && index < widgetLayers.count else { return [] }
        return widgetLayers[index] ?? []
    }

    public func textObjects(forPage index: Int) -> [TextObject] {
        guard index >= 0 && index < textLayers.count else { return [] }
        return textLayers[index] ?? []
    }

    public func visibleExpansions(forPage index: Int) -> [PageRegion] {
        guard index >= 0 && index < pages.count else { return [] }
        return expansionRegions.filter { $0.pageIndex == index && !$0.isCollapsed }
    }

    public func allExpansions(forPage index: Int) -> [PageRegion] {
        guard index >= 0 && index < pages.count else { return [] }
        return expansionRegions.filter { $0.pageIndex == index }
    }

    public func pageColor(forPage index: Int) -> UIColor? {
        guard index >= 0 && index < pageColors.count,
              let comps = pageColors[index], comps.count == 4 else { return nil }
        return UIColor(
            red: CGFloat(comps[0]), green: CGFloat(comps[1]),
            blue: CGFloat(comps[2]), alpha: CGFloat(comps[3])
        )
    }

    public var pdfFilename: String?
    public var linkedPDFID: UUID?
    public var linkedDocumentID: UUID?
    public var typedText: String
    public var ocrText: String
    public var tags: [String]
    public var colorLabel: NoteColorLabel?
    public var pageCount: Int { pages.count }

    public init(
        id: UUID = UUID(),
        title: String = "New Note",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        drawingData: Data = Data(),
        pages: [Data]? = nil,
        isFavorited: Bool = false,
        notebookID: UUID? = nil,
        sectionID: UUID? = nil,
        sortOrder: Int = 0,
        templateID: String = "builtin.blank",
        themeOverride: AppTheme? = nil,
        pageType: PageType? = nil,
        pageTypes: [PageType?] = [],
        paperMaterial: PaperMaterial? = nil,
        pageColors: [[Double]?] = [],
        stickerLayers: [[StickerInstance]?] = [],
        shapeLayers: [[ShapeInstance]?] = [],
        attachmentLayers: [[AttachmentObject]?] = [],
        widgetLayers: [[NoteWidget]?] = [],
        textLayers: [[TextObject]?] = [],
        expansionRegions: [PageRegion] = [],
        pdfFilename: String? = nil,
        linkedPDFID: UUID? = nil,
        linkedDocumentID: UUID? = nil,
        typedText: String = "",
        ocrText: String = "",
        tags: [String] = [],
        colorLabel: NoteColorLabel? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pages = pages ?? [drawingData]
        self.isFavorited = isFavorited
        self.notebookID = notebookID
        self.sectionID = sectionID
        self.sortOrder = sortOrder
        self.templateID = templateID
        self.themeOverride = themeOverride
        self.pageType = pageType
        self.pageTypes = pageTypes
        self.paperMaterial = paperMaterial
        self.pageColors = pageColors
        self.stickerLayers = stickerLayers
        self.shapeLayers = shapeLayers
        self.attachmentLayers = attachmentLayers
        self.widgetLayers = widgetLayers
        self.textLayers = textLayers
        self.expansionRegions = expansionRegions
        self.pdfFilename = pdfFilename
        self.linkedPDFID = linkedPDFID
        self.linkedDocumentID = linkedDocumentID
        self.typedText = typedText
        self.ocrText = ocrText
        self.tags = tags
        self.colorLabel = colorLabel
    }

    // MARK: Codable
    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, drawingData, pages
        case isFavorited, notebookID, sectionID, sortOrder, templateID, themeOverride
        case pageType, pageTypes, paperMaterial, pageColors, stickerLayers, shapeLayers, attachmentLayers, widgetLayers, textLayers, expansionRegions, pdfFilename
        case linkedPDFID, linkedDocumentID
        case typedText, ocrText, tags, colorLabel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,   forKey: .id)
        title         = try c.decode(String.self, forKey: .title)
        createdAt     = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt    = try c.decode(Date.self,   forKey: .modifiedAt)

        if let pagesArray = try c.decodeIfPresent([Data].self, forKey: .pages) {
            pages = pagesArray.isEmpty ? [Data()] : pagesArray
        } else {
            let legacy = try c.decode(Data.self, forKey: .drawingData)
            pages = [legacy]
        }

        isFavorited   = try c.decodeIfPresent(Bool.self,     forKey: .isFavorited)  ?? false
        notebookID    = try c.decodeIfPresent(UUID.self,     forKey: .notebookID)
        sectionID     = try c.decodeIfPresent(UUID.self,     forKey: .sectionID)
        sortOrder     = try c.decodeIfPresent(Int.self,      forKey: .sortOrder)    ?? 0
        templateID    = try c.decodeIfPresent(String.self,   forKey: .templateID)   ?? "builtin.blank"
        themeOverride = try c.decodeIfPresent(AppTheme.self, forKey: .themeOverride)
        pageType      = try c.decodeIfPresent(PageType.self,      forKey: .pageType)
        pageTypes     = try c.decodeIfPresent([PageType?].self,   forKey: .pageTypes)   ?? []
        paperMaterial = try c.decodeIfPresent(PaperMaterial.self,  forKey: .paperMaterial)
        pageColors    = try c.decodeIfPresent([[Double]?].self,    forKey: .pageColors)  ?? []
        stickerLayers = try c.decodeIfPresent([[StickerInstance]?].self, forKey: .stickerLayers) ?? []
        shapeLayers   = try c.decodeIfPresent([[ShapeInstance]?].self,   forKey: .shapeLayers)   ?? []
        attachmentLayers = try c.decodeIfPresent([[AttachmentObject]?].self, forKey: .attachmentLayers) ?? []
        widgetLayers  = try c.decodeIfPresent([[NoteWidget]?].self, forKey: .widgetLayers) ?? []
        textLayers    = try c.decodeIfPresent([[TextObject]?].self,  forKey: .textLayers)   ?? []
        expansionRegions = try c.decodeIfPresent([PageRegion].self, forKey: .expansionRegions) ?? []
        pdfFilename   = try c.decodeIfPresent(String.self,         forKey: .pdfFilename)
        linkedPDFID      = try c.decodeIfPresent(UUID.self,   forKey: .linkedPDFID)
        linkedDocumentID = try c.decodeIfPresent(UUID.self,   forKey: .linkedDocumentID)
        typedText     = try c.decodeIfPresent(String.self,   forKey: .typedText)   ?? ""
        ocrText       = try c.decodeIfPresent(String.self,   forKey: .ocrText)     ?? ""
        tags          = try c.decodeIfPresent([String].self,          forKey: .tags)       ?? []
        colorLabel    = try c.decodeIfPresent(NoteColorLabel.self,    forKey: .colorLabel)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,            forKey: .id)
        try c.encode(title,         forKey: .title)
        try c.encode(createdAt,     forKey: .createdAt)
        try c.encode(modifiedAt,    forKey: .modifiedAt)
        try c.encode(pages.first ?? Data(), forKey: .drawingData)
        try c.encode(pages,                 forKey: .pages)
        try c.encode(isFavorited,   forKey: .isFavorited)
        try c.encodeIfPresent(notebookID,    forKey: .notebookID)
        try c.encodeIfPresent(sectionID,     forKey: .sectionID)
        try c.encode(sortOrder,     forKey: .sortOrder)
        try c.encode(templateID,    forKey: .templateID)
        try c.encodeIfPresent(themeOverride, forKey: .themeOverride)
        try c.encodeIfPresent(pageType,      forKey: .pageType)
        try c.encode(pageTypes,              forKey: .pageTypes)
        try c.encodeIfPresent(paperMaterial, forKey: .paperMaterial)
        try c.encode(pageColors,              forKey: .pageColors)
        try c.encode(stickerLayers,            forKey: .stickerLayers)
        try c.encode(shapeLayers,              forKey: .shapeLayers)
        try c.encode(attachmentLayers,         forKey: .attachmentLayers)
        try c.encode(widgetLayers,             forKey: .widgetLayers)
        try c.encode(textLayers,               forKey: .textLayers)
        try c.encode(expansionRegions,          forKey: .expansionRegions)
        try c.encodeIfPresent(pdfFilename,   forKey: .pdfFilename)
        try c.encodeIfPresent(linkedPDFID,      forKey: .linkedPDFID)
        try c.encodeIfPresent(linkedDocumentID, forKey: .linkedDocumentID)
        try c.encode(typedText,     forKey: .typedText)
        try c.encode(ocrText,       forKey: .ocrText)
        try c.encode(tags,          forKey: .tags)
        try c.encodeIfPresent(colorLabel, forKey: .colorLabel)
    }

    // MARK: Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
}
