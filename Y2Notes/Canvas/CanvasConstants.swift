import UIKit

// MARK: - CanvasConstants

/// Shared constants used by all canvas UIViewRepresentable implementations
/// (`CanvasView`, `CanvasPageView`, `InfiniteCanvasPageView`) and their
/// supporting infrastructure (DiffUpdate, NoteStore OCR, export).
///
/// Before this enum the same values were duplicated across `CanvasView` and
/// `CanvasPageView` — any change to page dimensions, ruling colours, or desk
/// surface had to be applied in two places.  `CanvasConstants` is the single
/// source of truth.
enum CanvasConstants {

    // MARK: - Page Dimensions

    /// A4 paper aspect ratio (~1 : √2) used to compute page height from width.
    static let a4AspectRatio: CGFloat = 1.414

    /// Fixed page size for the canvas content area.  Uses the *landscape*
    /// screen width (the larger dimension) with an A4 aspect ratio so the page
    /// fills the screen in width regardless of orientation and provides vertical
    /// scrolling room like a real paper page.
    static let pageSize: CGSize = {
        let screen = UIScreen.main.bounds
        let w = max(screen.width, screen.height)
        return CGSize(width: w, height: ceil(w * a4AspectRatio))
    }()

    /// Multiplier applied to the standard page size in each dimension for
    /// infinite canvas content area (e.g. 4× = 16× total area).
    static let infiniteCanvasMultiplier: CGFloat = 4.0

    // MARK: - Colours

    /// Returns a ruling line color that is visible against the given background.
    /// On dark backgrounds the lines are white at low opacity; on light
    /// backgrounds they are black at low opacity.
    static func rulingLineColor(for background: UIColor) -> UIColor {
        let isDarkBackground: Bool = {
            var white: CGFloat = 0
            if background.getWhite(&white, alpha: nil) {
                return white < 0.5
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            if background.getRed(&red, green: &green, blue: &blue, alpha: nil) {
                let relativeLuminance =
                    (0.2126 * red) +
                    (0.7152 * green) +
                    (0.0722 * blue)
                return relativeLuminance < 0.5
            }

            return false
        }()

        return isDarkBackground
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.label.withAlphaComponent(0.10)
    }

    /// The background color shown outside the page boundaries (the "desk"
    /// surface).  Uses a neutral warm-gray that contrasts with the paper in
    /// both light and dark appearances, giving the canvas the look of a real
    /// page resting on a table.
    static let deskSurfaceColor: UIColor = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.13, alpha: 1)
            : UIColor(white: 0.86, alpha: 1)
    }

    // MARK: - Token Helpers

    /// Creates a stable token for PDF background identity comparisons.
    static func pdfBackgroundToken(pdfURL: URL?, pageIndex: Int, backgroundColor: UIColor) -> String {
        let url = pdfURL?.absoluteString ?? ""
        let color = stableColorToken(backgroundColor)
        return "\(url.count)#\(url)|\(pageIndex)|\(color.count)#\(color)"
    }

    /// Creates a page identity token for page binding.
    static func pageToken(noteID: UUID, pageIndex: Int) -> String {
        "\(noteID.uuidString)-\(pageIndex)"
    }

    private static func stableColorToken(_ color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return String(format: "%.5f-%.5f-%.5f-%.5f", red, green, blue, alpha)
        }
        var white: CGFloat = 0
        if color.getWhite(&white, alpha: &alpha) {
            return String(format: "w%.5f-a%.5f", white, alpha)
        }
        if let components = color.cgColor.components {
            let values = components.map { String(format: "%.5f", $0) }.joined(separator: "-")
            return "cg-\(values)"
        }
        return "unknown"
    }
}
