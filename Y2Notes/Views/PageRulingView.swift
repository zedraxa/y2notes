import UIKit

// MARK: - PageBackgroundView

/// A non-interactive `UIView` that renders the page background for a note canvas:
///
/// - Fills with the notebook's paper material tint colour.
/// - Draws the page type ruling (ruled lines, dot grid, square grid, Cornell
///   layout, hexagonal grid, or music staff) on top.
/// - Optionally renders a multi-octave noise grain for textured paper materials.
/// - Draws a subtle edge vignette shadow to give the page physical depth.
///
/// This view is inserted **behind** `PKCanvasView` inside the canvas container
/// so that PencilKit strokes sit on top of the ruling. The canvas itself is set
/// to a `.clear` background so the ruling shows through.
///
/// Performance notes:
/// - `draw(_:)` is called once during layout; `setNeedsDisplay()` is triggered
///   only when properties change (background color, page type, or grain intensity).
/// - Grain is rendered via two cached `CGImage` stamps (64 px and 128 px) tiled
///   at different scales for a multi-octave texture feel.
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

    /// Noise grain intensity in the range [0, 1].
    /// `0.0` disables the grain overlay entirely.
    /// Typical material values: 0.045 (recycled) … 0.075 (textured).
    var grainIntensity: Double = 0.0 {
        didSet {
            if grainIntensity != oldValue {
                grainImageSmall = nil
                grainImageLarge = nil
                setNeedsDisplay()
            }
        }
    }

    // MARK: - Geometry constants

    private let ruledSpacing:      CGFloat = 28   // points between ruled lines
    private let gridSpacing:       CGFloat = 24   // points between grid lines
    private let dotRadius:         CGFloat = 1.5  // radius of dot-grid dots
    private let dotSpacing:        CGFloat = 24   // points between dot-grid dots
    private let staffLineSpacing:  CGFloat = 7    // points between lines within a music staff
    private let staffGroupGap:     CGFloat = 44   // points between bottom of one staff and top of next
    private let hexRadius:         CGFloat = 18   // circumradius of hexagonal cells

    // MARK: - Grain cache

    /// Small (64×64) noise tile for the primary grain octave.
    private var grainImageSmall: CGImage?
    /// Larger (128×128) noise tile for the secondary grain octave.
    private var grainImageLarge: CGImage?
    /// Catch-all cache for any other stamp sizes (keyed by side length).
    private var grainImageCache: [Int: CGImage] = [:]

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

        // 3. Overlay grain if requested.
        if grainIntensity > 0 {
            drawGrain(in: ctx, rect: rect)
        }

        // 4. Subtle edge vignette to give the page physical depth.
        drawPageEdgeShadow(in: ctx, rect: rect)
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

    // MARK: - Cornell ruling

    /// Renders the classic Cornell note-taking layout:
    /// - A vertical margin/cue-column line at ~28 % from the left.
    /// - A horizontal header line near the top.
    /// - A horizontal summary line near the bottom.
    /// - Light horizontal ruling lines in the main note-taking area.
    private func drawCornellRuling(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()

        let marginX:  CGFloat = round(rect.width * 0.28)
        let headerY:  CGFloat = ruledSpacing * 2           // ~56 pt from top
        let summaryY: CGFloat = rect.maxY - ruledSpacing * 3 // ~84 pt from bottom

        // Structure lines (slightly heavier than ruling lines).
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.75)

        ctx.move(to: CGPoint(x: marginX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: marginX, y: rect.maxY))

        ctx.move(to: CGPoint(x: rect.minX, y: headerY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: headerY))

        ctx.move(to: CGPoint(x: rect.minX, y: summaryY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: summaryY))

        ctx.strokePath()

        // Light horizontal ruling in the note-taking body.
        ctx.setLineWidth(0.5)
        var y = headerY + ruledSpacing
        while y < summaryY - 1 {
            ctx.move(to: CGPoint(x: marginX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += ruledSpacing
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Hexagonal grid

    /// Draws a pointy-top isometric hex grid using `hexRadius` as the circumradius.
    private func drawHexGrid(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(lineColor.withAlphaComponent(lineColor.cgColor.alpha * 0.9).cgColor)
        ctx.setLineWidth(0.5)

        let r = hexRadius
        let colStep = r * sqrt(3.0)   // horizontal distance between hex centres
        let rowStep = r * 1.5         // vertical distance between hex centres

        let cols = Int(ceil(rect.width  / colStep)) + 2
        let rows = Int(ceil(rect.height / rowStep)) + 2

        for row in -1 ..< rows {
            for col in -1 ..< cols {
                // Odd rows are offset by half a column step.
                let offsetX: CGFloat = (row & 1) != 0 ? colStep * 0.5 : 0
                let cx = rect.minX + CGFloat(col) * colStep + offsetX
                let cy = rect.minY + CGFloat(row) * rowStep
                appendHexPath(to: ctx, cx: cx, cy: cy, r: r)
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Appends a closed pointy-top hexagon path centred at (cx, cy).
    private func appendHexPath(to ctx: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        // Pointy-top: first vertex is directly above the centre (90°), then every 60°.
        let startAngle: CGFloat = .pi / 2
        let step:       CGFloat = .pi / 3
        let x0 = cx + r * cos(startAngle)
        let y0 = cy - r * sin(startAngle) // UIKit y-axis is flipped
        ctx.move(to: CGPoint(x: x0, y: y0))
        for i in 1 ..< 6 {
            let angle = startAngle + CGFloat(i) * step
            ctx.addLine(to: CGPoint(x: cx + r * cos(angle), y: cy - r * sin(angle)))
        }
        ctx.closePath()
    }

    // MARK: - Music staff

    /// Draws groups of five evenly spaced horizontal lines, separated by a
    /// larger inter-staff gap, mimicking standard music notation paper.
    private func drawMusicStaff(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(0.6)

        let staffHeight = staffLineSpacing * 4  // 4 gaps → 5 lines per staff
        let groupPitch  = staffHeight + staffGroupGap

        // First staff starts half a gap from the top for a small margin.
        var topY: CGFloat = staffGroupGap * 0.5
        while topY <= rect.maxY + groupPitch {
            for lineIdx in 0 ..< 5 {
                let y = topY + CGFloat(lineIdx) * staffLineSpacing
                guard y <= rect.maxY else { break }
                ctx.move(to: CGPoint(x: rect.minX + 16, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX - 16, y: y))
            }
            topY += groupPitch
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Page edge vignette

    /// Draws a very faint inward-facing gradient shadow on each edge to give the
    /// page a subtle sense of physical depth and weight.
    private func drawPageEdgeShadow(in ctx: CGContext, rect: CGRect) {
        let inset: CGFloat  = 24
        let alpha: CGFloat  = 0.055
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let shadow = UIColor.black.withAlphaComponent(alpha).cgColor
        let clear  = UIColor.clear.cgColor
        guard let grad = CGGradient(
            colorsSpace: colorSpace,
            colors: [shadow, clear] as CFArray,
            locations: [0, 1]
        ) else { return }

        // Top strip
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: inset))
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: rect.minY),
            end:   CGPoint(x: 0, y: rect.minY + inset), options: [])
        ctx.restoreGState()

        // Bottom strip
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.minX, y: rect.maxY - inset, width: rect.width, height: inset))
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: rect.maxY),
            end:   CGPoint(x: 0, y: rect.maxY - inset), options: [])
        ctx.restoreGState()

        // Left strip
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.minX, y: rect.minY, width: inset, height: rect.height))
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: rect.minX,         y: 0),
            end:   CGPoint(x: rect.minX + inset, y: 0), options: [])
        ctx.restoreGState()

        // Right strip
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.maxX - inset, y: rect.minY, width: inset, height: rect.height))
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: rect.maxX,         y: 0),
            end:   CGPoint(x: rect.maxX - inset, y: 0), options: [])
        ctx.restoreGState()
    }

    // MARK: - Grain overlay

    /// Tiles two grain octaves (small 64 px + large 128 px) at `grainIntensity`
    /// and `grainIntensity * 0.5` respectively for a multi-scale paper tooth feel.
    private func drawGrain(in ctx: CGContext, rect: CGRect) {
        let small = grainStamp(side: 64,  seed: 0xDEAD_BEEF)
        let large = grainStamp(side: 128, seed: 0xC0FFEE42)

        // Primary octave (64 px).
        let smallSize: CGFloat = 64
        ctx.saveGState()
        ctx.setAlpha(CGFloat(grainIntensity))
        tile(image: small, stampSize: smallSize, in: ctx, rect: rect)
        ctx.restoreGState()

        // Secondary octave (128 px) at half intensity.
        let largeSize: CGFloat = 128
        ctx.saveGState()
        ctx.setAlpha(CGFloat(grainIntensity) * 0.5)
        tile(image: large, stampSize: largeSize, in: ctx, rect: rect)
        ctx.restoreGState()
    }

    private func tile(image: CGImage, stampSize: CGFloat, in ctx: CGContext, rect: CGRect) {
        let cols = Int(ceil(rect.width  / stampSize)) + 1
        let rows = Int(ceil(rect.height / stampSize)) + 1
        for row in 0 ..< rows {
            for col in 0 ..< cols {
                let tileRect = CGRect(
                    x: rect.minX + CGFloat(col) * stampSize,
                    y: rect.minY + CGFloat(row) * stampSize,
                    width: stampSize, height: stampSize
                )
                ctx.draw(image, in: tileRect)
            }
        }
    }

    /// Returns (and caches) a monochrome noise tile of the given `side` length.
    /// `seed` controls the xorshift PRNG so different sizes produce independent patterns.
    private func grainStamp(side: Int, seed initialSeed: UInt32) -> CGImage {
        // Fast path: dedicated properties for the two standard sizes.
        if side == 64,  let cached = grainImageSmall { return cached }
        if side == 128, let cached = grainImageLarge  { return cached }
        // General path: dictionary cache for any other size.
        if let cached = grainImageCache[side] { return cached }

        var pixels = [UInt8](repeating: 0, count: side * side)
        var s: UInt32 = initialSeed
        for i in pixels.indices {
            s ^= s << 13; s ^= s >> 17; s ^= s << 5
            pixels[i] = UInt8(s & 0xFF)
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let provider   = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        if side == 64  { grainImageSmall = image }
        if side == 128 { grainImageLarge = image }
        grainImageCache[side] = image
        return image
    }
}

