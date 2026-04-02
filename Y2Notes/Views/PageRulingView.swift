import UIKit

// MARK: - PageBackgroundView

/// A non-interactive `UIView` that renders the page background for a note canvas:
///
/// - Fills with the notebook's paper material tint colour.
/// - Draws the page type ruling (ruled lines, dot grid, or square grid) on top.
/// - Optionally renders a very faint noise grain for textured paper materials.
///
/// This view is inserted **behind** `PKCanvasView` inside the canvas container
/// so that PencilKit strokes sit on top of the ruling. The canvas itself is set
/// to a `.clear` background so the ruling shows through.
///
/// Performance notes:
/// - `draw(_:)` is called once during layout; `setNeedsDisplay()` is triggered
///   only when properties change (background color, page type, or grain flag).
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

    /// When `true`, a very faint noise grain is overlaid to suggest paper tooth.
    var showGrain: Bool = false {
        didSet { if showGrain != oldValue { grainImage = nil; setNeedsDisplay() } }
    }

    // MARK: - Geometry constants

    private let ruledSpacing: CGFloat  = 28   // points between ruled lines
    private let gridSpacing:  CGFloat  = 24   // points between grid lines
    private let dotRadius:    CGFloat  = 1.5  // radius of dot-grid dots
    private let dotSpacing:   CGFloat  = 24   // points between dot-grid dots

    // MARK: - Grain cache

    /// Small (64×64) noise image tiled across the surface.  Cached and
    /// invalidated only when `showGrain` changes.
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
        }

        // 3. Overlay grain if requested.
        if showGrain {
            drawGrain(in: ctx, rect: rect)
        }
    }

    // MARK: - Ruled lines

    private func drawRuledLines(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.5)

        // Start below the first line-spacing offset so there is a small top margin.
        var y = ruledSpacing
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += ruledSpacing
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Dot grid

    private func drawDotGrid(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setFillColor(lineColor.cgColor)

        var y = dotSpacing
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

    // MARK: - Grain overlay

    private func drawGrain(in ctx: CGContext, rect: CGRect) {
        let stamp = grainStamp()
        let stampSize: CGFloat = 64
        ctx.saveGState()
        ctx.setAlpha(0.04)     // very faint — just suggests texture
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

    /// Returns (and caches) a 64×64 monochrome noise image used as the grain tile.
    private func grainStamp() -> CGImage {
        if let cached = grainImage { return cached }

        let side = 64
        let bytesPerRow = side
        var pixels = [UInt8](repeating: 0, count: side * side)
        // Fill with pseudo-random noise using a fast xorshift PRNG so the
        // stamp is deterministic (same grain every launch).
        var seed: UInt32 = 0xDEAD_BEEF
        for i in pixels.indices {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            pixels[i] = UInt8(seed & 0xFF)
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        grainImage = image
        return image
    }
}
