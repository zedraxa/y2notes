import Foundation
import UIKit
import SwiftUI

// MARK: - Note color label

/// A visual color label that can be assigned to a note for quick category recognition.
/// Mirrors the "colored dot" feature in GoodNotes 6 and Apple Notes.
enum NoteColorLabel: String, Codable, CaseIterable, Identifiable {
    case red    = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green  = "green"
    case teal   = "teal"
    case blue   = "blue"
    case purple = "purple"

    var id: String { rawValue }

    var displayName: String {
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

    var color: Color {
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

    var uiColor: UIColor {
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

struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date

    /// Multi-page drawing storage.  Each element is a serialised `PKDrawing`
    /// (empty `Data` = blank page).  Index 0 is the first page.
    ///
    /// Old saves that pre-date multi-page support stored a single `drawingData`
    /// field — the backward-compatible decoder migrates it into `pages[0]`.
    var pages: [Data]

    /// Convenience accessor for the first page's drawing data.
    /// Thumbnails and search use this to represent the note at a glance.
    var drawingData: Data {
        get { pages.first ?? Data() }
        set {
            if pages.isEmpty {
                pages = [newValue]
            } else {
                pages[0] = newValue
            }
        }
    }

    /// Whether the user has starred this note.
    var isFavorited: Bool
    /// The notebook this note belongs to (nil = unfiled).
    var notebookID: UUID?
    /// The section within the notebook this page belongs to (nil = no section / notebook-level).
    var sectionID: UUID?
    /// 0-based position within the section (or notebook root if `sectionID` is nil).
    /// Lower numbers appear first in ordered page lists.
    var sortOrder: Int
    /// Stable ID of the page template applied when this page was created.
    /// See ``TemplateRegistry`` and ``PageTemplate``.
    var templateID: String
    /// Per-note theme override. When non-nil the editor canvas uses this theme instead
    /// of the global app theme. App chrome (sidebar, navigation) always follows the global theme.
    var themeOverride: AppTheme?

    /// Per-note page ruling override (nil = inherit from notebook, or `.blank` for unfiled notes).
    var pageType: PageType?

    /// Per-page ruling overrides — parallel array to `pages`.
    /// A nil element means that page inherits from `pageType` (note-level override).
    /// An empty array means all pages use `pageType`.
    /// Use `pageType(forPage:)` to resolve the effective ruling for a given page.
    var pageTypes: [PageType?]

    /// Returns the per-page ruling override for the given index, falling back to the
    /// note-level `pageType`.  Does **not** cascade to the notebook — callers in
    /// `NoteEditorView` are responsible for the final notebook/blank fallback.
    func pageType(forPage index: Int) -> PageType? {
        guard index >= 0 && index < pageTypes.count else { return pageType }
        return pageTypes[index] ?? pageType
    }

    /// Per-note paper material override (nil = inherit from notebook, or `.standard` for unfiled notes).
    var paperMaterial: PaperMaterial?

    /// Canvas mode for this note: paginated (default multi-page) or infinite (single boundless canvas).
    /// Nil means paginated for backward compatibility.
    var canvasMode: CanvasMode?

    /// Whether this note uses the infinite canvas layout.
    var isInfiniteCanvas: Bool { canvasMode == .infinite }

    /// Per-page background colour overrides — parallel array to `pages`.
    /// Each element stores RGBA components `[Double]` (0…1 range), or `nil` to
    /// inherit from the theme.  An empty array means all pages use the theme colour.
    var pageColors: [[Double]?]

    /// Per-page sticker instances — parallel array to `pages`.
    /// Each element is an array of stickers placed on that page, or `nil` (no stickers).
    /// An empty outer array means no pages have stickers yet.
    var stickerLayers: [[StickerInstance]?]

    /// Per-page shape objects — parallel array to `pages`.
    /// Each element is an array of shapes placed on that page, or `nil` (no shapes).
    /// An empty outer array means no pages have shape objects yet.
    var shapeLayers: [[ShapeInstance]?]

    /// Per-page attachment objects — parallel array to `pages`.
    /// Each element is an array of attachments placed on that page, or `nil` (no attachments).
    /// An empty outer array means no pages have attachments yet.
    var attachmentLayers: [[AttachmentObject]?]

    /// Per-page widget instances — parallel array to `pages`.
    /// Each element is an array of widgets placed on that page, or `nil` (no widgets).
    /// An empty outer array means no pages have widgets yet.
    var widgetLayers: [[NoteWidget]?]

    /// Per-page text objects — parallel array to `pages`.
    /// Each element is an array of text objects placed on that page, or `nil` (no text objects).
    /// An empty outer array means no pages have text objects yet.
    var textLayers: [[TextObject]?]

    /// Per-page rich embedded objects — parallel array to `pages`.
    /// Each element is an array of canvas objects (images, audio, stickers, links) placed on that
    /// page, or `nil` (no embedded objects).  An empty outer array means no pages have embedded
    /// objects yet.  Missing key decodes to an empty array for backward compatibility.
    var embeddedObjectLayers: [[CanvasObjectWrapper]?]

    /// Expandable canvas regions attached to page edges.
    /// Sparse — only pages that have been expanded carry entries.
    /// An empty array means no pages have expansion regions (default).
    var expansionRegions: [PageRegion]

    /// Returns the stickers for the given page index, or an empty array.
    func stickers(forPage index: Int) -> [StickerInstance] {
        guard index >= 0 && index < stickerLayers.count else { return [] }
        return stickerLayers[index] ?? []
    }

    /// Returns the shape objects for the given page index, or an empty array.
    func shapes(forPage index: Int) -> [ShapeInstance] {
        guard index >= 0 && index < shapeLayers.count else { return [] }
        return shapeLayers[index] ?? []
    }

    /// Returns the attachment objects for the given page index, or an empty array.
    func attachments(forPage index: Int) -> [AttachmentObject] {
        guard index >= 0 && index < attachmentLayers.count else { return [] }
        return attachmentLayers[index] ?? []
    }

    /// Returns the widget instances for the given page index, or an empty array.
    func widgets(forPage index: Int) -> [NoteWidget] {
        guard index >= 0 && index < widgetLayers.count else { return [] }
        return widgetLayers[index] ?? []
    }

    /// Returns the text objects for the given page index, or an empty array.
    func textObjects(forPage index: Int) -> [TextObject] {
        guard index >= 0 && index < textLayers.count else { return [] }
        return textLayers[index] ?? []
    }

    /// Returns the embedded canvas objects for the given page index, or an empty array.
    func embeddedObjects(forPage index: Int) -> [CanvasObjectWrapper] {
        guard index >= 0 && index < embeddedObjectLayers.count else { return [] }
        return embeddedObjectLayers[index] ?? []
    }

    /// Returns the visible (non-collapsed) expansion regions for the given page index.
    func visibleExpansions(forPage index: Int) -> [PageRegion] {
        guard index >= 0 && index < pages.count else { return [] }
        return expansionRegions.filter { $0.pageIndex == index && !$0.isCollapsed }
    }

    /// Returns all expansion regions (including collapsed) for the given page index.
    func allExpansions(forPage index: Int) -> [PageRegion] {
        guard index >= 0 && index < pages.count else { return [] }
        return expansionRegions.filter { $0.pageIndex == index }
    }

    /// Returns the per-page colour for the given index, or `nil` to inherit theme.
    func pageColor(forPage index: Int) -> UIColor? {
        guard index >= 0 && index < pageColors.count,
              let comps = pageColors[index], comps.count == 4 else { return nil }
        return UIColor(
            red: CGFloat(comps[0]), green: CGFloat(comps[1]),
            blue: CGFloat(comps[2]), alpha: CGFloat(comps[3])
        )
    }

    /// Basename of the automatically maintained PDF file inside `Documents/NotePDFs/`.
    /// When non-nil the editor renders this PDF as the page background and sharing
    /// exports the maintained file directly — giving the note a "book-like" feel.
    /// Nil for legacy notes that predate PDF-based storage; those are migrated lazily
    /// on first open.
    var pdfFilename: String?

    /// The ID of a `PDFNoteRecord` this note is a companion for.
    /// When non-nil, the note was created from a PDF viewer to annotate alongside the PDF.
    var linkedPDFID: UUID?

    /// The ID of an `ImportedDocument` this note is a companion for.
    /// When non-nil, the note was created from a document viewer to annotate alongside the import.
    var linkedDocumentID: UUID?

    /// Keyboard-typed text content for this note.
    /// Empty string = drawing-only note. Used by `SearchService` and the in-document find bar.
    var typedText: String

    /// Recognised text from handwriting via on-device OCR.
    /// Empty string until an OCR pass runs on the note's `drawingData`.
    /// Searched by `SearchService` as `SearchMatchType.handwritingOCR`.
    var ocrText: String

    /// User-defined tags for cross-notebook organisation.
    /// Comparable to Apple Notes' tags and GoodNotes' tag system.
    /// Each element is a lowercased, trimmed tag string (e.g. "lecture", "math").
    var tags: [String]

    /// Optional colour label for quick visual categorisation (e.g. red = urgent, green = done).
    /// Nil means no label is applied.
    var colorLabel: NoteColorLabel?

    /// Total number of pages in this note.
    var pageCount: Int { pages.count }

    init(
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
        canvasMode: CanvasMode? = nil,
        pageColors: [[Double]?] = [],
        stickerLayers: [[StickerInstance]?] = [],
        shapeLayers: [[ShapeInstance]?] = [],
        attachmentLayers: [[AttachmentObject]?] = [],
        widgetLayers: [[NoteWidget]?] = [],
        textLayers: [[TextObject]?] = [],
        embeddedObjectLayers: [[CanvasObjectWrapper]?] = [],
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
        self.canvasMode = canvasMode
        self.pageColors = pageColors
        self.stickerLayers = stickerLayers
        self.shapeLayers = shapeLayers
        self.attachmentLayers = attachmentLayers
        self.widgetLayers = widgetLayers
        self.textLayers = textLayers
        self.embeddedObjectLayers = embeddedObjectLayers
        self.expansionRegions = expansionRegions
        self.pdfFilename = pdfFilename
        self.linkedPDFID = linkedPDFID
        self.linkedDocumentID = linkedDocumentID
        self.typedText = typedText
        self.ocrText = ocrText
        self.tags = tags
        self.colorLabel = colorLabel
    }

    // MARK: Codable — custom decoder for backward compatibility with old saves
    // that pre-date the isFavorited / notebookID / themeOverride / sectionID / sortOrder /
    // templateID / multi-page fields.
    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, drawingData, pages
        case isFavorited, notebookID, sectionID, sortOrder, templateID, themeOverride
        case pageType, pageTypes, paperMaterial, canvasMode, pageColors, stickerLayers, shapeLayers, attachmentLayers, widgetLayers, textLayers, embeddedObjectLayers, expansionRegions, pdfFilename
        case linkedPDFID, linkedDocumentID
        case typedText, ocrText, tags, colorLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,   forKey: .id)
        title         = try c.decode(String.self, forKey: .title)
        createdAt     = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt    = try c.decode(Date.self,   forKey: .modifiedAt)

        // Multi-page backward compatibility: prefer `pages` if present, otherwise
        // migrate the legacy single-page `drawingData` into a one-element array.
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
        canvasMode    = try c.decodeIfPresent(CanvasMode.self,     forKey: .canvasMode)
        pageColors    = try c.decodeIfPresent([[Double]?].self,    forKey: .pageColors)  ?? []
        stickerLayers = try c.decodeIfPresent([[StickerInstance]?].self, forKey: .stickerLayers) ?? []
        shapeLayers   = try c.decodeIfPresent([[ShapeInstance]?].self,   forKey: .shapeLayers)   ?? []
        attachmentLayers = try c.decodeIfPresent([[AttachmentObject]?].self, forKey: .attachmentLayers) ?? []
        widgetLayers  = try c.decodeIfPresent([[NoteWidget]?].self, forKey: .widgetLayers) ?? []
        textLayers    = try c.decodeIfPresent([[TextObject]?].self,  forKey: .textLayers)   ?? []
        embeddedObjectLayers = try c.decodeIfPresent([[CanvasObjectWrapper]?].self, forKey: .embeddedObjectLayers) ?? []
        expansionRegions = try c.decodeIfPresent([PageRegion].self, forKey: .expansionRegions) ?? []
        pdfFilename   = try c.decodeIfPresent(String.self,         forKey: .pdfFilename)
        linkedPDFID      = try c.decodeIfPresent(UUID.self,   forKey: .linkedPDFID)
        linkedDocumentID = try c.decodeIfPresent(UUID.self,   forKey: .linkedDocumentID)
        typedText     = try c.decodeIfPresent(String.self,   forKey: .typedText)   ?? ""
        ocrText       = try c.decodeIfPresent(String.self,   forKey: .ocrText)     ?? ""
        tags          = try c.decodeIfPresent([String].self,          forKey: .tags)       ?? []
        colorLabel    = try c.decodeIfPresent(NoteColorLabel.self,    forKey: .colorLabel)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,            forKey: .id)
        try c.encode(title,         forKey: .title)
        try c.encode(createdAt,     forKey: .createdAt)
        try c.encode(modifiedAt,    forKey: .modifiedAt)

        // Write both `drawingData` (first page) and `pages` for maximum backward
        // compatibility — older app versions that only understand `drawingData`
        // will still load the first page correctly.
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
        try c.encodeIfPresent(canvasMode,    forKey: .canvasMode)
        try c.encode(pageColors,              forKey: .pageColors)
        try c.encode(stickerLayers,            forKey: .stickerLayers)
        try c.encode(shapeLayers,              forKey: .shapeLayers)
        try c.encode(attachmentLayers,         forKey: .attachmentLayers)
        try c.encode(widgetLayers,             forKey: .widgetLayers)
        try c.encode(textLayers,               forKey: .textLayers)
        try c.encode(embeddedObjectLayers,       forKey: .embeddedObjectLayers)
        try c.encode(expansionRegions,          forKey: .expansionRegions)
        try c.encodeIfPresent(pdfFilename,   forKey: .pdfFilename)
        try c.encodeIfPresent(linkedPDFID,      forKey: .linkedPDFID)
        try c.encodeIfPresent(linkedDocumentID, forKey: .linkedDocumentID)
        try c.encode(typedText,     forKey: .typedText)
        try c.encode(ocrText,       forKey: .ocrText)
        try c.encode(tags,          forKey: .tags)
        try c.encodeIfPresent(colorLabel, forKey: .colorLabel)
    }

    // MARK: Hashable — identity only, so list selection stays stable while content changes.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
}
