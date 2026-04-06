import SwiftUI
import UIKit

// MARK: - PageType

/// The ruling style printed on notebook pages.
public enum PageType: String, CaseIterable, Codable, Identifiable {
    case blank      = "blank"
    case ruled      = "ruled"
    case dot        = "dot"
    case grid       = "grid"
    case cornell    = "cornell"
    case hexagonal  = "hexagonal"
    case music      = "music"

    public var id: String { rawValue }

    public var displayName: String {
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

    public var subtitle: String {
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

    public var systemImage: String {
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
public enum PageSize: String, CaseIterable, Codable, Identifiable {
    case letter = "letter"
    case a4     = "a4"
    case a5     = "a5"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .letter: return "Letter"
        case .a4:     return "A4"
        case .a5:     return "A5"
        }
    }

    public var subtitle: String {
        switch self {
        case .letter: return "8.5 × 11\""
        case .a4:     return "210 × 297 mm"
        case .a5:     return "148 × 210 mm"
        }
    }
}

// MARK: - PageOrientation

/// The default page orientation for new notes in the notebook.
public enum PageOrientation: String, CaseIterable, Codable, Identifiable {
    case portrait  = "portrait"
    case landscape = "landscape"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .portrait:  return "Portrait"
        case .landscape: return "Landscape"
        }
    }

    public var systemImage: String {
        switch self {
        case .portrait:  return "rectangle.portrait"
        case .landscape: return "rectangle"
        }
    }
}

// MARK: - PaperMaterial

/// Simulated paper surface / feel of notebook pages.
public enum PaperMaterial: String, CaseIterable, Codable, Identifiable {
    case standard = "standard"
    case premium  = "premium"
    case craft    = "craft"
    case recycled = "recycled"
    case textured = "textured"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .premium:  return "Premium"
        case .craft:    return "Craft"
        case .recycled: return "Recycled"
        case .textured: return "Textured"
        }
    }

    public var description: String {
        switch self {
        case .standard: return "Smooth, everyday writing surface"
        case .premium:  return "Thick, fountain-pen friendly weight"
        case .craft:    return "Warm kraft texture for creativity"
        case .recycled: return "Eco-friendly, lightly textured"
        case .textured: return "Laid paper with visible tooth"
        }
    }

    public var systemImage: String {
        switch self {
        case .standard: return "doc.plaintext"
        case .premium:  return "doc.fill"
        case .craft:    return "leaf.fill"
        case .recycled: return "arrow.3.trianglepath"
        case .textured: return "squareshape.controlhandles.on.squareshape.controlhandles"
        }
    }

    public var pageTint: Color {
        switch self {
        case .standard: return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .premium:  return Color(red: 0.98, green: 0.96, blue: 1.00)
        case .craft:    return Color(red: 0.93, green: 0.85, blue: 0.70)
        case .recycled: return Color(red: 0.91, green: 0.92, blue: 0.88)
        case .textured: return Color(red: 0.93, green: 0.90, blue: 0.85)
        }
    }

    // MARK: Ink-response hooks

    public var inkAlphaMultiplier: Double {
        switch self {
        case .standard: return 1.00
        case .premium:  return 1.00
        case .craft:    return 0.82
        case .recycled: return 0.85
        case .textured: return 0.75
        }
    }

    public var grainIntensity: Double {
        switch self {
        case .craft:    return 0.70
        case .recycled: return 0.50
        case .textured: return 1.00
        default:        return 0.00
        }
    }

    public var hasGrainTexture: Bool { grainIntensity > 0 }

    public var rulingTint: UIColor? {
        switch self {
        case .craft:    return UIColor(red: 0.52, green: 0.36, blue: 0.18, alpha: 1.0)
        case .recycled: return UIColor(red: 0.44, green: 0.44, blue: 0.36, alpha: 1.0)
        default:        return nil
        }
    }
}
