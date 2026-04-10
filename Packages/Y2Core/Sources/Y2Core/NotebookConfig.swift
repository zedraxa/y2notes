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

