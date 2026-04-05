import SwiftUI
import UIKit

// MARK: - PageType

/// The ruling style printed on notebook pages.
enum PageType: String, CaseIterable, Codable, Identifiable {
    case blank      = "blank"
    case ruled      = "ruled"
    case dot        = "dot"
    case grid       = "grid"
    case cornell    = "cornell"
    case hexagonal  = "hexagonal"
    case music      = "music"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank:     return "Blank"
        case .ruled:     return "Ruled"
        case .dot:       return "Dot"
        case .grid:      return "Grid"
        case .cornell:   return "Cornell"
        case .hexagonal: return "Hexagonal"
        case .music:     return "Music"
        }
    }

    var subtitle: String {
        switch self {
        case .blank:     return "Clean canvas"
        case .ruled:     return "Lined writing"
        case .dot:       return "Flexible guide"
        case .grid:      return "Graph paper"
        case .cornell:   return "Organised note-taking"
        case .hexagonal: return "Creative layouts"
        case .music:     return "Five-line staff"
        }
    }

    var systemImage: String {
        switch self {
        case .blank:     return "square"
        case .ruled:     return "text.alignleft"
        case .dot:       return "circle.grid.3x3"
        case .grid:      return "grid"
        case .cornell:   return "rectangle.split.2x1"
        case .hexagonal: return "hexagon"
        case .music:     return "music.note.list"
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
///   This is subtle by design: the minimum shipped value is 0.84.
///
/// - `hasGrainTexture` — when `true` the canvas host adds a very faint noise
///   overlay (`PageBackgroundView`) to suggest paper tooth without impacting
///   drawing performance.
///
/// These hooks are applied in `DrawingToolStore.pkTool` and `PageBackgroundView`
/// respectively.  They are intentionally coarse-grained to stay reliable
/// across the full range of Apple Pencil pressure inputs.
enum PaperMaterial: String, CaseIterable, Codable, Identifiable {
    // Original four
    case standard = "standard"
    case premium  = "premium"
    case craft    = "craft"
    case recycled = "recycled"
    // Surface-finish variants (AGENT-13)
    case matte    = "matte"
    case glossy   = "glossy"
    case textured = "textured"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .premium:  return "Premium"
        case .craft:    return "Craft"
        case .recycled: return "Recycled"
        case .matte:    return "Matte"
        case .glossy:   return "Glossy"
        case .textured: return "Textured"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Smooth, everyday writing surface"
        case .premium:  return "Thick, fountain-pen friendly weight"
        case .craft:    return "Warm kraft texture for creativity"
        case .recycled: return "Eco-friendly, lightly textured"
        case .matte:    return "Soft finish, reduced glare"
        case .glossy:   return "High-sheen, vibrant ink colors"
        case .textured: return "Laid paper with visible tooth"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "doc.plaintext"
        case .premium:  return "doc.fill"
        case .craft:    return "leaf.fill"
        case .recycled: return "arrow.3.trianglepath"
        case .matte:    return "square.on.square"
        case .glossy:   return "sparkles"
        case .textured: return "squareshape.controlhandles.on.squareshape.controlhandles"
        }
    }

    /// Subtle page background tint that evokes the material feel.
    var pageTint: Color {
        switch self {
        case .standard: return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .premium:  return Color(red: 0.99, green: 0.98, blue: 1.00)
        case .craft:    return Color(red: 0.96, green: 0.90, blue: 0.79)
        case .recycled: return Color(red: 0.94, green: 0.94, blue: 0.92)
        case .matte:    return Color(red: 0.97, green: 0.97, blue: 0.97)
        case .glossy:   return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .textured: return Color(red: 0.95, green: 0.93, blue: 0.90)
        }
    }

    // MARK: Ink-response hooks

    /// Multiplier applied to stroke opacity when generating `PKInkingTool`.
    /// Values below 1.0 simulate ink absorption by rough or matte paper.
    /// Kept in the range [0.84, 1.0] so the effect is always perceptible but
    /// never harsh.
    var inkAlphaMultiplier: Double {
        switch self {
        case .standard: return 1.00
        case .premium:  return 1.00
        case .matte:    return 0.92
        case .glossy:   return 1.00
        case .craft:    return 0.88
        case .recycled: return 0.90
        case .textured: return 0.84
        }
    }

    /// Graduated grain intensity (0.0 = no grain, 1.0 = full grain).
    /// Used by `PageBackgroundView` to render multi-octave paper tooth noise.
    /// Replaces the former Boolean `hasGrainTexture`.
    var grainIntensity: Double {
        switch self {
        case .craft:    return 0.70
        case .recycled: return 0.50
        case .textured: return 1.00
        default:        return 0.00
        }
    }

    /// `true` when the material carries any grain texture (convenience wrapper).
    var hasGrainTexture: Bool { grainIntensity > 0 }

    /// Optional tint applied to accent ruling elements (margin lines, Cornell
    /// separators).  `nil` means use the default contrasting `lineColor`.
    var rulingTint: UIColor? {
        switch self {
        case .craft:    return UIColor(red: 0.52, green: 0.36, blue: 0.18, alpha: 1.0)
        case .recycled: return UIColor(red: 0.44, green: 0.44, blue: 0.36, alpha: 1.0)
        default:        return nil
        }
    }
}
