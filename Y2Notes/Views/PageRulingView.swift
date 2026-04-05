import UIKit

// MARK: - PageBackgroundView

/// A non-interactive `UIView` that renders the page background for a note canvas:
///
/// - Fills with the notebook's paper material tint colour.
/// - Draws the page type ruling (ruled lines, dot grid, square grid, Cornell
///   layout, or music staves) on top.
/// - Optionally renders a noise grain overlay whose intensity varies by paper
///   material, suggesting paper tooth without impacting drawing performance.
///
/// This view is inserted **behind** `PKCanvasView` inside the canvas container
/// so that PencilKit strokes sit on top of the ruling. The canvas itself is set
/// to a `.clear` background so the ruling shows through.
///
/// Performance notes:
/// - `draw(_:)` is called once during layout; `setNeedsDisplay()` is triggered
///   only when properties change (background color, page type, or grain value).
/// - Grain is rendered via a cached `CGImage` tiled from a small noise stamp.
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

    /// Grain overlay alpha. 0 = no grain, higher = more visible paper tooth.
    /// Backed by `PaperMaterial.grainIntensity`.
    var grainIntensity: Double = 0 {
        didSet {
            if grainIntensity != oldValue {
                grainImage = nil
                setNeedsDisplay()
            }
        }
    }

    // MARK: - Geometry constants

    private let ruledSpacing: CGFloat   = 28   // points between ruled lines
    private let gridSpacing:  CGFloat   = 24   // points between grid lines
    private let dotRadius:    CGFloat   = 1.5  // radius of dot-grid dots
    private let dotSpacing:   CGFloat   = 24   // points between dot-grid dots
    /// Blank space at the very top of the page before the first ruling or dot row.
    /// Mirrors the header margin found on real college-ruled notebooks (~56 pt ≈ 20 mm).
    private let topMargin:    CGFloat   = 56
    /// Horizontal offset of the left margin line from the page edge, matching
    /// the standard single-margin position used in physical ruled notebooks.
    /// The value (80 pt ≈ 28 mm) is fixed because the page width is always the
    /// device's landscape dimension (~1024–1366 pt), making a proportional
    /// ~7 % offset equivalent to roughly 28 mm on every supported device.
    private let leftMarginOffset: CGFloat = 80

    // Cornell layout constants
    private let cornellCueWidth: CGFloat    = 72   // left cue column width
    private let cornellSummaryHeight: CGFloat = 64  // bottom summary band height

    // Music staff constants
    private let staffLineCount: Int     = 5
    private let staffLineSpacing: CGFloat = 8
    private let staffGroupSpacing: CGFloat = 48  // space between staff groups

    // MARK: - Grain cache

    /// Small (64×64) noise image tiled across the surface.  Cached and
    /// invalidated only when `grainIntensity` changes.
    private var grainImage: CGImage?

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
        case .music:
            drawMusicStaves(in: ctx, rect: rect)
        }

        // 3. Overlay grain if requested.
        if grainIntensity > 0 {
            drawGrain(in: ctx, rect: rect)
        }

        // 4. Draw a very subtle border so the page edge is perceptible on
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
        // Grid lines are drawn at half the opacity of ruled lines to avoid
        // looking too heavy when both axes are present.
        let gridColor = lineColor.withAlphaComponent(lineColor.cgColor.alpha * 0.7)
        ctx.setStrokeColor(gridColor.cgColor)
        ctx.setLineWidth(0.5)

        // Horizontal lines
        var y = gridSpacing
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += gridSpacing
        }
        // Vertical lines
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

    /// Draws a Cornell notes layout: vertical cue column on the left,
    /// horizontal summary band at the bottom, and ruled lines in the main area.
    private func drawCornellRuling(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        let dividerColor = lineColor.withAlphaComponent(lineColor.cgColor.alpha * 1.5)

        // Cue column divider (thick vertical line)
        ctx.setStrokeColor(dividerColor.cgColor)
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: cornellCueWidth, y: 0))
        ctx.addLine(to: CGPoint(x: cornellCueWidth, y: rect.maxY - cornellSummaryHeight))
        ctx.strokePath()

        // Summary band divider (thick horizontal line)
        ctx.move(to: CGPoint(x: 0, y: rect.maxY - cornellSummaryHeight))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornellSummaryHeight))
        ctx.strokePath()

        // Ruled lines in the main note-taking area (right of cue, above summary)
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.5)
        var y = ruledSpacing
        while y < rect.maxY - cornellSummaryHeight {
            ctx.move(to: CGPoint(x: cornellCueWidth + 8, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += ruledSpacing
        }
        ctx.strokePath()

        ctx.restoreGState()
    }

    // MARK: - Music staves

    /// Draws repeating five-line staff groups for music notation.
    private func drawMusicStaves(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.5)

        let staffHeight = CGFloat(staffLineCount - 1) * staffLineSpacing
        var groupTop = staffGroupSpacing

        while groupTop + staffHeight <= rect.maxY {
            for i in 0..<staffLineCount {
                let y = groupTop + CGFloat(i) * staffLineSpacing
                ctx.move(to: CGPoint(x: 16, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX - 16, y: y))
            }
            groupTop += staffHeight + staffGroupSpacing
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Grain overlay

    private func drawGrain(in ctx: CGContext, rect: CGRect) {
        let stamp = grainStamp()
        let stampSize: CGFloat = 128
        ctx.saveGState()
        ctx.setAlpha(CGFloat(grainIntensity))
        let cols = Int(ceil(rect.width  / stampSize)) + 1
        let rows = Int(ceil(rect.height / stampSize)) + 1
        for row in 0..<rows {
            for col in 0..<cols {
                let tileRect = CGRect(
                    x: rect.minX + CGFloat(col) * stampSize,
                    y: rect.minY + CGFloat(row) * stampSize,
                    width: stampSize, height: stampSize
                )
                ctx.draw(stamp, in: tileRect)
            }
        }
        ctx.restoreGState()
    }

    /// Returns (and caches) a 128×128 monochrome Perlin noise image used as the grain tile.
    /// Uses fractal Brownian motion for organic paper texture, replacing the simple
    /// xorshift PRNG with algorithmically richer procedural noise.
    private func grainStamp() -> CGImage {
        if let cached = grainImage { return cached }

        // Delegate to the custom Perlin noise tile generator.
        // Smooth material gives subtle, uniform grain appropriate for note paper.
        let image = NoiseTextureGenerator.generateTile(
            width: 128,
            height: 128,
            material: .smooth,
            scale: 0.045,
            seed: 0xDEAD_BEEF
        )!
        grainImage = image
        return image
    }
}
