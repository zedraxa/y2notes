import Foundation
import SwiftUI

// MARK: - Notebook colour tag

/// Named colour labels for notebook cards, mirroring ``SectionColorTag``.
/// Stored as a raw String for forward compatibility.
enum NotebookColorTag: String, CaseIterable, Codable {
    case none   = "none"
    case red    = "red"
    case orange = "orange"
    case teal   = "teal"
    case blue   = "blue"
    case purple = "purple"
    case green  = "green"
    case pink   = "pink"
}

extension NotebookColorTag {
    var color: Color {
        switch self {
        case .none:   return .clear
        case .red:    return Color(red: 0.86, green: 0.20, blue: 0.20)
        case .orange: return Color(red: 0.92, green: 0.50, blue: 0.10)
        case .teal:   return Color(red: 0.10, green: 0.65, blue: 0.60)
        case .blue:   return Color(red: 0.12, green: 0.45, blue: 0.90)
        case .purple: return Color(red: 0.55, green: 0.15, blue: 0.80)
        case .green:  return Color(red: 0.15, green: 0.65, blue: 0.30)
        case .pink:   return Color(red: 0.90, green: 0.30, blue: 0.55)
        }
    }

    var displayName: String {
        switch self {
        case .none:   return NSLocalizedString("NotebookColorTag.None",   comment: "")
        case .red:    return NSLocalizedString("NotebookColorTag.Red",    comment: "")
        case .orange: return NSLocalizedString("NotebookColorTag.Orange", comment: "")
        case .teal:   return NSLocalizedString("NotebookColorTag.Teal",   comment: "")
        case .blue:   return NSLocalizedString("NotebookColorTag.Blue",   comment: "")
        case .purple: return NSLocalizedString("NotebookColorTag.Purple", comment: "")
        case .green:  return NSLocalizedString("NotebookColorTag.Green",  comment: "")
        case .pink:   return NSLocalizedString("NotebookColorTag.Pink",   comment: "")
        }
    }
}

// MARK: - Cover theme

/// Named color themes for notebook covers.
/// The built-in library provides twelve gradient swatches that render entirely
/// in code — no asset catalogue needed.  Custom photo covers are stored
/// separately in `Notebook.customCoverData`.
enum NotebookCover: String, CaseIterable, Codable {
    // Original six
    case ocean
    case forest
    case sunset
    case lavender
    case slate
    case sand
    // Expanded library (AGENT-13)
    case ruby
    case midnight
    case jade
    case coral
    case copper
    case nebula

    var displayName: String {
        switch self {
        case .ocean:    return "Ocean"
        case .forest:   return "Forest"
        case .sunset:   return "Sunset"
        case .lavender: return "Lavender"
        case .slate:    return "Slate"
        case .sand:     return "Sand"
        case .ruby:     return "Ruby"
        case .midnight: return "Midnight"
        case .jade:     return "Jade"
        case .coral:    return "Coral"
        case .copper:   return "Copper"
        case .nebula:   return "Nebula"
        }
    }

    /// RGB components of the cover's primary colour as [r, g, b] in 0…1 range.
    /// Useful for lightweight serialisation (e.g. tab bar accent tint).
    var rgbComponents: [Double] {
        switch self {
        case .ocean:    return [0.0, 0.48, 1.0]
        case .forest:   return [0.10, 0.55, 0.30]
        case .sunset:   return [1.0, 0.58, 0.0]
        case .lavender: return [0.69, 0.32, 0.87]
        case .slate:    return [0.56, 0.56, 0.58]
        case .sand:     return [0.76, 0.60, 0.42]
        case .ruby:     return [0.86, 0.15, 0.20]
        case .midnight: return [0.10, 0.10, 0.25]
        case .jade:     return [0.0, 0.66, 0.55]
        case .coral:    return [1.0, 0.50, 0.31]
        case .copper:   return [0.72, 0.45, 0.20]
        case .nebula:   return [0.55, 0.27, 0.68]
        }
    }
}

// MARK: - Notebook template

/// Preset notebook configurations for common use cases.
/// Selecting a template in `NotebookQuickCreator` pre-fills the form fields;
/// the user can still customise individual settings afterwards.
enum NotebookTemplate: String, CaseIterable, Identifiable {
    case blank
    case study
    case journal
    case planner
    case sketchbook
    case music

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank:      return "Blank"
        case .study:      return "Study"
        case .journal:    return "Journal"
        case .planner:    return "Planner"
        case .sketchbook: return "Sketchbook"
        case .music:      return "Music"
        }
    }

    var subtitle: String {
        switch self {
        case .blank:      return "Empty canvas"
        case .study:      return "Cornell notes"
        case .journal:    return "Lined writing"
        case .planner:    return "Grid layout"
        case .sketchbook: return "Dot guide"
        case .music:      return "Staff paper"
        }
    }

    var systemImage: String {
        switch self {
        case .blank:      return "doc"
        case .study:      return "text.book.closed"
        case .journal:    return "book"
        case .planner:    return "calendar"
        case .sketchbook: return "pencil.and.outline"
        case .music:      return "music.note.list"
        }
    }

    /// Default page type for this template.
    var pageType: PageType {
        switch self {
        case .blank:      return .blank
        case .study:      return .cornell
        case .journal:    return .ruled
        case .planner:    return .grid
        case .sketchbook: return .dot
        case .music:      return .music
        }
    }

    /// Suggested paper material for this template.
    var paperMaterial: PaperMaterial {
        switch self {
        case .blank:      return .standard
        case .study:      return .standard
        case .journal:    return .premium
        case .planner:    return .standard
        case .sketchbook: return .textured
        case .music:      return .premium
        }
    }

    /// Suggested cover colour for this template.
    var suggestedCover: NotebookCover {
        switch self {
        case .blank:      return .ocean
        case .study:      return .midnight
        case .journal:    return .forest
        case .planner:    return .slate
        case .sketchbook: return .coral
        case .music:      return .lavender
        }
    }

    /// Suggested cover texture for this template.
    var suggestedTexture: CoverTexture {
        switch self {
        case .blank:      return .smooth
        case .study:      return .leather
        case .journal:    return .linen
        case .planner:    return .smooth
        case .sketchbook: return .canvas
        case .music:      return .cloth
        }
    }
}

// MARK: - Cover texture

/// Physical surface texture applied on top of the cover gradient or photo.
/// Each texture draws a procedural pattern via SwiftUI Canvas — no bitmap assets.
enum CoverTexture: String, CaseIterable, Identifiable, Codable {
    case smooth
    case leather
    case linen
    case canvas
    case cloth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smooth:  return "Smooth"
        case .leather: return "Leather"
        case .linen:   return "Linen"
        case .canvas:  return "Canvas"
        case .cloth:   return "Cloth"
        }
    }

    var systemImage: String {
        switch self {
        case .smooth:  return "circle.fill"
        case .leather: return "rectangle.pattern.checkered"
        case .linen:   return "line.3.horizontal"
        case .canvas:  return "square.grid.3x3.fill"
        case .cloth:   return "rectangle.split.3x1"
        }
    }
}

// MARK: - Notebook model

struct Notebook: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Optional subtitle or tagline shown on the notebook cover page.
    var description: String
    var createdAt: Date
    var modifiedAt: Date
    var cover: NotebookCover

    // MARK: Creation wizard configuration
    /// Page ruling style for new notes in this notebook.
    var pageType: PageType
    /// Standard page size for new notes.
    var pageSize: PageSize
    /// Default page orientation for new notes.
    var orientation: PageOrientation
    /// Optional theme override applied to notes in this notebook. nil = follow global app theme.
    var defaultTheme: AppTheme?
    /// Simulated paper texture / feel.
    var paperMaterial: PaperMaterial
    /// JPEG-compressed custom cover image chosen from the photo library. nil = use built-in gradient.
    var customCoverData: Data?
    /// Physical surface texture rendered over the cover gradient or photo.
    var coverTexture: CoverTexture
    /// When true the notebook is locked — page creation and editing are disabled.
    var isLocked: Bool
    /// Colour label for quick visual identification in the notebook shelf.
    var colorTag: NotebookColorTag
    /// When this notebook was last opened by the user. nil = never opened.
    var lastOpenedAt: Date?
    /// When true the notebook appears first in the notebook shelf regardless of sort order.
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        cover: NotebookCover = .ocean,
        pageType: PageType = .ruled,
        pageSize: PageSize = .letter,
        orientation: PageOrientation = .portrait,
        defaultTheme: AppTheme? = nil,
        paperMaterial: PaperMaterial = .standard,
        customCoverData: Data? = nil,
        coverTexture: CoverTexture = .smooth,
        isLocked: Bool = false,
        colorTag: NotebookColorTag = .none,
        lastOpenedAt: Date? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.cover = cover
        self.pageType = pageType
        self.pageSize = pageSize
        self.orientation = orientation
        self.defaultTheme = defaultTheme
        self.paperMaterial = paperMaterial
        self.customCoverData = customCoverData
        self.coverTexture = coverTexture
        self.isLocked = isLocked
        self.colorTag = colorTag
        self.lastOpenedAt = lastOpenedAt
        self.isPinned = isPinned
    }

    // MARK: Codable — custom decoder for backward compatibility with saves that pre-date
    // the pageType / pageSize / orientation / defaultTheme / paperMaterial / customCoverData /
    // coverTexture / colorTag / lastOpenedAt / isPinned fields.
    enum CodingKeys: String, CodingKey {
        case id, name, description, createdAt, modifiedAt, cover
        case pageType, pageSize, orientation, defaultTheme, paperMaterial, customCoverData
        case coverTexture, isLocked, colorTag, lastOpenedAt, isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,          forKey: .id)
        name            = try c.decode(String.self,        forKey: .name)
        description     = try c.decodeIfPresent(String.self,              forKey: .description)  ?? ""
        createdAt       = try c.decode(Date.self,          forKey: .createdAt)
        modifiedAt      = try c.decode(Date.self,          forKey: .modifiedAt)
        cover           = try c.decode(NotebookCover.self, forKey: .cover)
        pageType        = try c.decodeIfPresent(PageType.self,             forKey: .pageType)     ?? .ruled
        pageSize        = try c.decodeIfPresent(PageSize.self,             forKey: .pageSize)     ?? .letter
        orientation     = try c.decodeIfPresent(PageOrientation.self,      forKey: .orientation)  ?? .portrait
        defaultTheme    = try c.decodeIfPresent(AppTheme.self,             forKey: .defaultTheme)
        paperMaterial   = try c.decodeIfPresent(PaperMaterial.self,        forKey: .paperMaterial) ?? .standard
        customCoverData = try c.decodeIfPresent(Data.self,                 forKey: .customCoverData)
        coverTexture    = try c.decodeIfPresent(CoverTexture.self,         forKey: .coverTexture)  ?? .smooth
        isLocked        = try c.decodeIfPresent(Bool.self,                 forKey: .isLocked)      ?? false
        colorTag        = try c.decodeIfPresent(NotebookColorTag.self,     forKey: .colorTag)      ?? .none
        lastOpenedAt    = try c.decodeIfPresent(Date.self,                 forKey: .lastOpenedAt)
        isPinned        = try c.decodeIfPresent(Bool.self,                 forKey: .isPinned)      ?? false
    }

    // MARK: Hashable — identity only.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Notebook, rhs: Notebook) -> Bool { lhs.id == rhs.id }
}
