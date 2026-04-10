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

// MARK: - CanvasMode

/// Whether a note uses a traditional paginated layout or an infinite whiteboard canvas.
///
/// Paginated mode presents pages in a horizontal carousel (standard note-taking).
/// Infinite mode provides a single, boundless canvas that the user can zoom
/// and pan freely — similar to GoodNotes' whiteboard or Apple Freeform.
enum CanvasMode: String, CaseIterable, Codable, Identifiable {
    /// Traditional multi-page layout with fixed-size pages.
    case paginated
    /// Single boundless canvas with unlimited space in all directions.
    case infinite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paginated: return "Paginated"
        case .infinite:  return "Infinite Canvas"
        }
    }

    var subtitle: String {
        switch self {
        case .paginated: return "Traditional multi-page notes"
        case .infinite:  return "Boundless whiteboard"
        }
    }

    var systemImage: String {
        switch self {
        case .paginated: return "doc.on.doc"
        case .infinite:  return "arrow.up.left.and.arrow.down.right"
        }
    }
}

