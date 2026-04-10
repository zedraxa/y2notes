import UIKit

// MARK: - PageBackgroundView

/// A non-interactive `UIView` that renders the page background for a note canvas:
///
/// - Fills with the page background colour.
/// - Draws the page type ruling (ruled lines, dot grid, square grid, Cornell,
///   hexagonal grid, or music staves) on top.
/// - Always draws a subtle edge-vignette shadow to suggest physical page depth.
///
/// This view is inserted **behind** `PKCanvasView` inside the canvas container
/// so that PencilKit strokes sit on top of the ruling. The canvas itself is set
/// to a `.clear` background so the ruling shows through.
///
/// Performance notes:
/// - `draw(_:)` is called once during layout; `setNeedsDisplay()` is triggered
///   only when properties change (background color or page type).
/// - All drawing uses `CGContext` primitives — no CALayer animations or
///   UIKit-hierarchy overhead.
final class PageBackgroundView: UIView {

    // MARK: - Configuration

    /// Background fill colour (usually blended from theme + paper material tint).
    var pageColor: UIColor = .white {
        didSet { if pageColor != oldValue { setNeedsDisplay() } }
    }

    /// The ruling style drawn on the page.
    var pageType: PageType = .blank {
        didSet { if pageType != oldValue { setNeedsDisplay() } }
    }

    /// Colour used for ruling lines and dots.
    var lineColor: UIColor = UIColor.label.withAlphaComponent(0.10) {
        didSet { if lineColor != oldValue { setNeedsDisplay() } }
    }

    // MARK: - Geometry constants

    private let ruledSpacing:       CGFloat = 28    // points between ruled lines
    private let gridSpacing:        CGFloat = 24    // points between grid lines
    private let dotRadius:          CGFloat = 1.5   // radius of dot-grid dots
    private let dotSpacing:         CGFloat = 24    // points between dot-grid dots
    /// Blank space at the very top of the page before the first ruling or dot row.
    /// Mirrors the header margin found on real college-ruled notebooks (~56 pt ≈ 20 mm).
    private let topMargin:          CGFloat = 56
    /// Horizontal offset of the left margin line from the page edge, matching
    /// the standard single-margin position used in physical ruled notebooks.
    /// The value (80 pt ≈ 28 mm) is fixed because the page width is always the
    /// device's landscape dimension (~1024–1366 pt), making a proportional
    /// ~7 % offset equivalent to roughly 28 mm on every supported device.
    private let leftMarginOffset:   CGFloat = 80
    private let cornellCueX:        CGFloat = 224   // Cornell cue-column separator x
    private let cornellHeaderY:     CGFloat = 56    // Cornell header separator y
    private let cornellSummaryFrac: CGFloat = 0.82  // Cornell summary line as fraction of height
    private let hexRadius:          CGFloat = 22    // hexagon circumradius (pointy-top)
    private let staffLineSpacing:   CGFloat = 8     // points between adjacent staff lines
    private let staffGroupGap:      CGFloat = 32    // gap between staff groups
    private let staffLinesCount:    Int     = 5     // lines per staff group

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // 1. Fill background with page colour.
        ctx.setFillColor(pageColor.cgColor)
        ctx.fill(rect)

        // 2. Draw ruling.
        switch pageType {
        case .blank:
            break
        case .ruled:
            drawRuledLines(in: ctx, rect: rect)
        case .dot:
            drawDotGrid(in: ctx, rect: rect)
        case .grid:
            drawSquareGrid(in: ctx, rect: rect)
        case .cornell:
            drawCornellRuling(in: ctx, rect: rect)
        case .hexagonal:
            drawHexGrid(in: ctx, rect: rect)
        case .music:
            drawMusicStaff(in: ctx, rect: rect)
        }

        // 3. Draw a very subtle border so the page edge is perceptible on
        //    the desk surface, especially when zoomed out.
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.label.withAlphaComponent(0.07).cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(rect.insetBy(dx: 0.25, dy: 0.25))
        ctx.restoreGState()
    }

    // MARK: - Ruled lines

    private func drawRuledLines(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.5)

        // Start at the top-margin offset so there is a blank header area
        // matching the look of real college-ruled paper.
        var y = topMargin
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += ruledSpacing
        }
        ctx.strokePath()

        // Left margin line — the traditional pink/red vertical line that
        // marks the writing margin on physical ruled notebooks.
        let marginX = rect.minX + leftMarginOffset
        if marginX < rect.maxX {
            ctx.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.22).cgColor)
            ctx.setLineWidth(0.75)
            ctx.move(to: CGPoint(x: marginX, y: rect.minY))
            ctx.addLine(to: CGPoint(x: marginX, y: rect.maxY))
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    // MARK: - Dot grid

    private func drawDotGrid(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setFillColor(lineColor.cgColor)

        // Start below the top margin so dot rows align with where text would
        // sit on ruled paper — giving a consistent feel across page types.
        var y = topMargin
        while y <= rect.maxY {
            var x = dotSpacing
            while x <= rect.maxX {
                ctx.fillEllipse(in: CGRect(
                    x: x - dotRadius, y: y - dotRadius,
                    width: dotRadius * 2, height: dotRadius * 2
                ))
                x += dotSpacing
            }
            y += dotSpacing
        }
        ctx.restoreGState()
    }

    // MARK: - Square grid

    private func drawSquareGrid(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        // Grid lines at slightly reduced opacity so both axes don't look heavy.
        let gridColor = lineColor.withAlphaComponent(lineColor.cgColor.alpha * 0.7)
        ctx.setStrokeColor(gridColor.cgColor)
        ctx.setLineWidth(0.5)

        var y = gridSpacing
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += gridSpacing
        }
        var x = gridSpacing
        while x <= rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += gridSpacing
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Cornell ruling

    /// Renders a Cornell-style note-taking layout:
    ///
    /// - Regular **horizontal ruled lines** spanning the full page body.
    /// - A horizontal **header** line near the top (title / date area).
    /// - A vertical **cue-column** separator at `cornellCueX` from the left.
    /// - A horizontal **summary** line near the bottom.
    ///
    /// Separator lines use a subtle accent colour to distinguish them from the
    /// body ruling without being distracting.
    private func drawCornellRuling(in ctx: CGContext, rect: CGRect) {
        let summaryY = rect.height * cornellSummaryFrac

        // Body ruled lines
        ctx.saveGState()
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.5)
        var y = cornellHeaderY + ruledSpacing
        while y < summaryY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += ruledSpacing
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Accent separator lines (header, cue column, summary)
        let accent = accentLineColor(alpha: 0.22)
        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(0.75)

        ctx.move(to: CGPoint(x: rect.minX, y: cornellHeaderY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: cornellHeaderY))

        ctx.move(to: CGPoint(x: cornellCueX, y: cornellHeaderY))
        ctx.addLine(to: CGPoint(x: cornellCueX, y: summaryY))

        ctx.move(to: CGPoint(x: rect.minX, y: summaryY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: summaryY))

        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Hexagonal grid

    /// Renders a pointy-top hexagonal grid tiling the full page.
    ///
    /// Tiling geometry for circumradius `r`:
    ///   - Horizontal centre-to-centre: r√3
    ///   - Vertical centre-to-centre:   r × 1.5  (offset every other column)
    private func drawHexGrid(in ctx: CGContext, rect: CGRect) {
        let r = hexRadius
        let w = r * sqrt(3.0)

        let gridColor = lineColor.withAlphaComponent(lineColor.cgColor.alpha * 0.80)
        ctx.saveGState()
        ctx.setStrokeColor(gridColor.cgColor)
        ctx.setLineWidth(0.5)

        let cols = Int(ceil(rect.width  / w)) + 2
        let rows = Int(ceil(rect.height / (r * 1.5))) + 2

        for col in -1..<cols {
            let cx = rect.minX + CGFloat(col) * w + (w * 0.5)
            let offset: CGFloat = (col % 2 == 0) ? 0 : r
            for row in -1..<rows {
                let cy = rect.minY + CGFloat(row) * r * 1.5 + offset

                ctx.move(to: hexVertex(cx: cx, cy: cy, r: r, index: 0))
                for i in 1...5 {
                    ctx.addLine(to: hexVertex(cx: cx, cy: cy, r: r, index: i))
                }
                ctx.closePath()
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Returns the i-th vertex of a pointy-top hexagon centred at (cx, cy).
    private func hexVertex(cx: CGFloat, cy: CGFloat, r: CGFloat, index: Int) -> CGPoint {
        let angleDeg = 60.0 * Double(index) - 30.0
        let angleRad = angleDeg * .pi / 180.0
        return CGPoint(
            x: cx + r * CGFloat(cos(angleRad)),
            y: cy + r * CGFloat(sin(angleRad))
        )
    }

    // MARK: - Music staff

    /// Renders repeating five-line music staves spanning the full page width.
    ///
    /// Each staff group is `staffLineSpacing × (staffLinesCount − 1)` points
    /// tall, separated by `staffGroupGap` points of breathing room.
    private func drawMusicStaff(in ctx: CGContext, rect: CGRect) {
        let staffGroupHeight = CGFloat(staffLinesCount - 1) * staffLineSpacing
        let periodHeight = staffGroupHeight + staffGroupGap


        ctx.saveGState()
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.75)

        var groupTop: CGFloat = staffGroupGap * 0.5
        while groupTop < rect.maxY {
            for i in 0..<staffLinesCount {
                let y = groupTop + CGFloat(i) * staffLineSpacing
                if y > rect.maxY { break }
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            groupTop += periodHeight
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Accent colour helper

    /// Returns the colour used for accent ruling elements (margin lines, Cornell
    /// separators) at the requested `alpha`.
    private func accentLineColor(alpha: CGFloat) -> UIColor {
        var white: CGFloat = 0
        pageColor.getWhite(&white, alpha: nil)
        return white < 0.5
            ? UIColor.systemRed.withAlphaComponent(alpha * 0.85)
            : UIColor.systemRed.withAlphaComponent(alpha)
    }
}
