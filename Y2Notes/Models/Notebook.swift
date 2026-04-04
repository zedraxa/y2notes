import Foundation

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

// MARK: - Notebook model

struct Notebook: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
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

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        cover: NotebookCover = .ocean,
        pageType: PageType = .ruled,
        pageSize: PageSize = .letter,
        orientation: PageOrientation = .portrait,
        defaultTheme: AppTheme? = nil,
        paperMaterial: PaperMaterial = .standard,
        customCoverData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.cover = cover
        self.pageType = pageType
        self.pageSize = pageSize
        self.orientation = orientation
        self.defaultTheme = defaultTheme
        self.paperMaterial = paperMaterial
        self.customCoverData = customCoverData
    }

    // MARK: Codable — custom decoder for backward compatibility with saves that pre-date
    // the pageType / pageSize / orientation / defaultTheme / paperMaterial / customCoverData fields.
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, modifiedAt, cover
        case pageType, pageSize, orientation, defaultTheme, paperMaterial, customCoverData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,          forKey: .id)
        name            = try c.decode(String.self,        forKey: .name)
        createdAt       = try c.decode(Date.self,          forKey: .createdAt)
        modifiedAt      = try c.decode(Date.self,          forKey: .modifiedAt)
        cover           = try c.decode(NotebookCover.self, forKey: .cover)
        pageType        = try c.decodeIfPresent(PageType.self,        forKey: .pageType)      ?? .ruled
        pageSize        = try c.decodeIfPresent(PageSize.self,        forKey: .pageSize)      ?? .letter
        orientation     = try c.decodeIfPresent(PageOrientation.self, forKey: .orientation)   ?? .portrait
        defaultTheme    = try c.decodeIfPresent(AppTheme.self,        forKey: .defaultTheme)
        paperMaterial   = try c.decodeIfPresent(PaperMaterial.self,   forKey: .paperMaterial) ?? .standard
        customCoverData = try c.decodeIfPresent(Data.self,            forKey: .customCoverData)
    }

    // MARK: Hashable — identity only.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Notebook, rhs: Notebook) -> Bool { lhs.id == rhs.id }
}
