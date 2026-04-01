import SwiftUI

// MARK: - PageType

/// The ruling style printed on notebook pages.
enum PageType: String, CaseIterable, Codable, Identifiable {
    case blank   = "blank"
    case ruled   = "ruled"
    case dot     = "dot"
    case grid    = "grid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .ruled: return "Ruled"
        case .dot:   return "Dot"
        case .grid:  return "Grid"
        }
    }

    var subtitle: String {
        switch self {
        case .blank: return "Clean canvas"
        case .ruled: return "Lined writing"
        case .dot:   return "Flexible guide"
        case .grid:  return "Graph paper"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: return "square"
        case .ruled: return "text.alignleft"
        case .dot:   return "circle.grid.3x3"
        case .grid:  return "grid"
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

/// Simulated paper texture / physical feel of notebook pages.
enum PaperMaterial: String, CaseIterable, Codable, Identifiable {
    case standard = "standard"
    case premium  = "premium"
    case craft    = "craft"
    case recycled = "recycled"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .premium:  return "Premium"
        case .craft:    return "Craft"
        case .recycled: return "Recycled"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Smooth, everyday writing surface"
        case .premium:  return "Thick, fountain-pen friendly weight"
        case .craft:    return "Warm kraft texture for creativity"
        case .recycled: return "Eco-friendly, lightly textured"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "doc.plaintext"
        case .premium:  return "doc.fill"
        case .craft:    return "leaf.fill"
        case .recycled: return "arrow.3.trianglepath"
        }
    }

    /// Subtle page background tint that evokes the material feel.
    var pageTint: Color {
        switch self {
        case .standard: return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .premium:  return Color(red: 0.99, green: 0.98, blue: 1.00)
        case .craft:    return Color(red: 0.96, green: 0.90, blue: 0.79)
        case .recycled: return Color(red: 0.94, green: 0.94, blue: 0.92)
        }
    }
}
