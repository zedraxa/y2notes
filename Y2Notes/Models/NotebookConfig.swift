import SwiftUI

// MARK: - PageType

/// The ruling style printed on notebook pages.
enum PageType: String, CaseIterable, Codable, Identifiable {
    case blank   = "blank"
    case ruled   = "ruled"
    case dot     = "dot"
    case grid    = "grid"
    case cornell = "cornell"
    case music   = "music"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank:   return "Blank"
        case .ruled:   return "Ruled"
        case .dot:     return "Dot"
        case .grid:    return "Grid"
        case .cornell: return "Cornell"
        case .music:   return "Music"
        }
    }

    var subtitle: String {
        switch self {
        case .blank:   return "Clean canvas"
        case .ruled:   return "Lined writing"
        case .dot:     return "Flexible guide"
        case .grid:    return "Graph paper"
        case .cornell: return "Study notes"
        case .music:   return "Staff paper"
        }
    }

    var systemImage: String {
        switch self {
        case .blank:   return "square"
        case .ruled:   return "text.alignleft"
        case .dot:     return "circle.grid.3x3"
        case .grid:    return "grid"
        case .cornell: return "rectangle.split.2x1"
        case .music:   return "music.note.list"
        }
    }
}

// MARK: - PageSize

/// Standard page sizes for a notebook.
enum PageSize: String, CaseIterable, Codable, Identifiable {
    case letter = "letter"
    case a4     = "a4"
    case a5     = "a5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .letter: return "Letter"
        case .a4:     return "A4"
        case .a5:     return "A5"
        }
    }

    var subtitle: String {
        switch self {
        case .letter: return "8.5 × 11\""
        case .a4:     return "210 × 297 mm"
        case .a5:     return "148 × 210 mm"
        }
    }
}

// MARK: - PageOrientation

/// The default page orientation for new notes in the notebook.
enum PageOrientation: String, CaseIterable, Codable, Identifiable {
    case portrait  = "portrait"
    case landscape = "landscape"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .portrait:  return "Portrait"
        case .landscape: return "Landscape"
        }
    }

    var systemImage: String {
        switch self {
        case .portrait:  return "rectangle.portrait"
        case .landscape: return "rectangle"
        }
    }
}

// MARK: - PaperMaterial

/// Simulated paper surface / feel of notebook pages.
///
/// **Ink-response hooks (AGENT-13)**
/// Every case exposes two lightweight hooks that `DrawingToolStore.pkTool`
/// reads when building the active `PKInkingTool`:
///
/// - `inkAlphaMultiplier` — scale factor applied to stroke opacity.
///   Values below 1.0 simulate ink absorption (matte / textured surfaces).
///
/// - `grainIntensity` — alpha applied to the noise grain overlay in
///   `PageBackgroundView`.  Zero means no grain; higher values produce
///   visible paper tooth.
///
/// These hooks are applied in `DrawingToolStore.pkTool` and `PageBackgroundView`
/// respectively.  They are intentionally coarse-grained to stay reliable
/// across the full range of Apple Pencil pressure inputs.
enum PaperMaterial: String, CaseIterable, Codable, Identifiable {
    case standard = "standard"
    case premium  = "premium"
    case craft    = "craft"
    case recycled = "recycled"
    case textured = "textured"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .premium:  return "Premium"
        case .craft:    return "Craft"
        case .recycled: return "Recycled"
        case .textured: return "Textured"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Smooth, everyday writing surface"
        case .premium:  return "Thick, fountain-pen friendly weight"
        case .craft:    return "Warm kraft texture for creativity"
        case .recycled: return "Eco-friendly, lightly textured"
        case .textured: return "Laid paper with visible tooth"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "doc.plaintext"
        case .premium:  return "doc.fill"
        case .craft:    return "leaf.fill"
        case .recycled: return "arrow.3.trianglepath"
        case .textured: return "squareshape.controlhandles.on.squareshape.controlhandles"
        }
    }

    /// Subtle page background tint that evokes the material feel.
    /// Tints are more saturated than before so each material is visually distinct.
    var pageTint: Color {
        switch self {
        case .standard: return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .premium:  return Color(red: 0.98, green: 0.96, blue: 1.00)
        case .craft:    return Color(red: 0.93, green: 0.85, blue: 0.70)
        case .recycled: return Color(red: 0.91, green: 0.92, blue: 0.88)
        case .textured: return Color(red: 0.93, green: 0.90, blue: 0.85)
        }
    }

    // MARK: Ink-response hooks

    /// Multiplier applied to stroke opacity when generating `PKInkingTool`.
    /// Values below 1.0 simulate ink absorption by rough or matte paper.
    var inkAlphaMultiplier: Double {
        switch self {
        case .standard: return 1.00
        case .premium:  return 1.00
        case .craft:    return 0.82
        case .recycled: return 0.85
        case .textured: return 0.75
        }
    }

    /// Alpha applied to the 64×64 noise grain tile in `PageBackgroundView`.
    /// Zero produces a clean surface; higher values show visible paper tooth.
    var grainIntensity: Double {
        switch self {
        case .standard: return 0
        case .premium:  return 0.02
        case .craft:    return 0.12
        case .recycled: return 0.08
        case .textured: return 0.15
        }
    }
}
