import UIKit

// MARK: - HoverToolInfo

/// Lightweight snapshot of the active tool state for hover cursor rendering.
/// Passed to `PencilHoverOverlayView.configure(with:)` whenever the tool,
/// colour, or width changes.
struct HoverToolInfo: Equatable {
    /// The logical tool type for cursor shape selection.
    let tool: HoverToolKind
    /// Active ink colour (used to tint the cursor).
    let color: UIColor
    /// Tool width in points (used to scale the cursor).
    let width: CGFloat

    static func == (lhs: HoverToolInfo, rhs: HoverToolInfo) -> Bool {
        lhs.tool == rhs.tool
            && lhs.width == rhs.width
            && lhs.colorHash == rhs.colorHash
    }

    private var colorHash: Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Int(r * 255) << 24 | Int(g * 255) << 16 | Int(b * 255) << 8 | Int(a * 255)
    }
}

/// Simplified tool kind for hover cursor rendering.
enum HoverToolKind: Equatable {
    case pen
    case pencil
    case highlighter
    case fountainPen
    case eraser(width: CGFloat)
    case lasso
    case other
}

// MARK: - PencilHoverOverlayView

/// A transparent, non-interactive overlay view that renders a tool-aware "ghost nib"
/// cursor while an Apple Pencil is hovering above the screen (M2+ iPad Pro, iOS 16.1+).
///
/// The cursor shape, colour, and size adapt to the currently active tool:
/// - **Pen**: Small filled circle in ink colour, scaled to tool width.
/// - **Pencil**: Circle with cross-hatch grain texture, altitude-responsive scaling.
/// - **Highlighter**: Wide semi-transparent rectangle, rotated by azimuth angle.
/// - **Fountain Pen**: Angled calligraphic nib that responds to azimuth & barrel roll.
/// - **Eraser**: Dashed ring showing the eraser footprint at current width.
/// - **Lasso**: Crosshair cursor.
///
/// Place this view as a sibling **above** the PKCanvasView in Z-order, with the
/// same frame.  Set `isUserInteractionEnabled = false` so all touches fall through
/// to the canvas.
///
/// On devices or OS versions that do not support Apple Pencil hover the view
/// remains invisible and has zero cost.
final class PencilHoverOverlayView: UIView {

    // MARK: - Configuration Constants

    private enum Config {
        /// Minimum cursor diameter regardless of tool width.
        static let minCursorSize: CGFloat = 10
        /// Maximum cursor diameter to prevent absurdly large cursors.
        static let maxCursorSize: CGFloat = 80
        /// Multiplier applied to tool width → cursor diameter.
        static let widthToSizeScale: CGFloat = 2.5
        /// Border width for the cursor ring.
        static let borderWidth: CGFloat = 1.5
        /// Highlighter aspect ratio (width / height).
        static let highlighterAspect: CGFloat = 3.0
        /// Eraser dash pattern.
        static let eraserDashPattern: [NSNumber] = [4, 3]
        /// Crosshair arm length for lasso.
        static let crosshairArm: CGFloat = 8
        /// Fade-in duration.
        static let fadeInDuration: TimeInterval = 0.12
        /// Fade-out duration.
        static let fadeOutDuration: TimeInterval = 0.18
        /// Fallback diameter when no tool info is configured.
        static let fallbackDiameter: CGFloat = 18
    }

    // MARK: - Subviews / Layers

    /// Main cursor container. All tool-specific sublayers are children of this view.
    private let nibView = UIView()

    /// Shape layer for the cursor outline / fill.
    private let cursorLayer = CAShapeLayer()

    /// Azimuth indicator line (visible for pen/pencil/fountain pen).
    private let azimuthLayer = CAShapeLayer()

    /// Cross-hatch grain overlay (pencil tool only).
    private let grainLayer = CAShapeLayer()

    // MARK: - State

    private var isHovering = false
    private var currentTool: HoverToolInfo?
    private var lastRollAngle: CGFloat = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds   = false

        nibView.isUserInteractionEnabled = false
        nibView.alpha = 0
        addSubview(nibView)

        // Cursor shape layer (main outline + fill).
        cursorLayer.lineWidth   = Config.borderWidth
        cursorLayer.fillColor   = UIColor.clear.cgColor
        cursorLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
        nibView.layer.addSublayer(cursorLayer)

        // Azimuth line inside the cursor.
        azimuthLayer.lineWidth   = 1
        azimuthLayer.fillColor   = UIColor.clear.cgColor
        azimuthLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
        nibView.layer.addSublayer(azimuthLayer)

        // Grain texture for pencil (hidden by default).
        grainLayer.lineWidth   = 0.5
        grainLayer.strokeColor = UIColor.gray.withAlphaComponent(0.3).cgColor
        grainLayer.fillColor   = UIColor.clear.cgColor
        grainLayer.isHidden    = true
        nibView.layer.addSublayer(grainLayer)
    }

    // MARK: - Public API: Tool Configuration

    /// Configure the hover cursor appearance for the given tool.
    /// Call whenever the active tool, colour, or width changes.
    func configure(with info: HoverToolInfo) {
        guard info != currentTool else { return }
        currentTool = info
        rebuildCursorAppearance(info: info)
    }

    /// Update the ghost nib position and orientation.
    ///
    /// - Parameters:
    ///   - position: Pencil hover location in this view's coordinate space.
    ///               Pass `nil` to hide the overlay.
    ///   - altitude: Pencil altitude in radians (0 = flat, π/2 = perpendicular).
    ///   - azimuth:  Pencil azimuth in radians.
    ///   - rollAngle: Barrel-roll angle in radians (Pencil Pro only). `nil` when
    ///                barrel roll is not active or not supported.
    func update(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat, rollAngle: CGFloat? = nil) {
        if let roll = rollAngle { lastRollAngle = roll }
        if let position = position {
            showNib(at: position, altitude: altitude, azimuth: azimuth, rollAngle: rollAngle ?? lastRollAngle)
        } else {
            hideNib()
        }
    }

    // MARK: - Appearance Rebuild

    /// Rebuilds cursor shape/colour for the current tool. Called once on tool change.
    private func rebuildCursorAppearance(info: HoverToolInfo) {
        let tintColor = info.color.withAlphaComponent(0.8)
        let fillColor = info.color.withAlphaComponent(0.08)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Reset sublayer state.
        grainLayer.isHidden = true
        cursorLayer.lineDashPattern = nil
        azimuthLayer.isHidden = false

        switch info.tool {
        case .pen:
            let size = cursorSize(for: info.width)
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            nibView.frame = rect
            cursorLayer.frame = rect
            cursorLayer.path = UIBezierPath(ovalIn: rect).cgPath
            cursorLayer.strokeColor = tintColor.cgColor
            cursorLayer.fillColor   = fillColor.cgColor
            cursorLayer.lineWidth   = Config.borderWidth
            azimuthLayer.strokeColor = tintColor.withAlphaComponent(0.5).cgColor

        case .pencil:
            let size = cursorSize(for: info.width)
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            nibView.frame = rect
            cursorLayer.frame = rect
            cursorLayer.path = UIBezierPath(ovalIn: rect).cgPath
            cursorLayer.strokeColor = tintColor.cgColor
            cursorLayer.fillColor   = fillColor.cgColor
            cursorLayer.lineWidth   = Config.borderWidth
            azimuthLayer.strokeColor = tintColor.withAlphaComponent(0.5).cgColor
            // Show grain cross-hatch overlay.
            grainLayer.isHidden = false
            grainLayer.frame = rect
            grainLayer.path  = pencilGrainPath(in: rect)
            grainLayer.strokeColor = info.color.withAlphaComponent(0.2).cgColor

        case .highlighter:
            // Wide, flat rectangle — height proportional to tool width, width = 3×.
            let h = cursorSize(for: info.width) * 0.6
            let w = h * Config.highlighterAspect
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            nibView.frame = rect
            cursorLayer.frame = rect
            let radius = min(h, w) * 0.2
            cursorLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
            cursorLayer.strokeColor = tintColor.cgColor
            cursorLayer.fillColor   = info.color.withAlphaComponent(0.15).cgColor
            cursorLayer.lineWidth   = 1.0
            azimuthLayer.isHidden = true  // No azimuth line for highlighter.

        case .fountainPen:
            // Calligraphic nib shape: ellipse stretched along azimuth.
            let size = cursorSize(for: info.width)
            let w = size * 1.6
            let h = size * 0.5
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            nibView.frame = rect
            cursorLayer.frame = rect
            cursorLayer.path = UIBezierPath(ovalIn: rect).cgPath
            cursorLayer.strokeColor = tintColor.cgColor
            cursorLayer.fillColor   = fillColor.cgColor
            cursorLayer.lineWidth   = Config.borderWidth
            azimuthLayer.strokeColor = tintColor.withAlphaComponent(0.5).cgColor

        case .eraser(let eraserWidth):
            // Dashed circle showing the eraser footprint.
            let size = max(eraserWidth * 2.0, Config.minCursorSize)
            let clampedSize = min(size, Config.maxCursorSize)
            let rect = CGRect(x: 0, y: 0, width: clampedSize, height: clampedSize)
            nibView.frame = rect
            cursorLayer.frame = rect
            cursorLayer.path = UIBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).cgPath
            cursorLayer.strokeColor = UIColor.label.withAlphaComponent(0.5).cgColor
            cursorLayer.fillColor   = UIColor.systemBackground.withAlphaComponent(0.15).cgColor
            cursorLayer.lineWidth   = 1.5
            cursorLayer.lineDashPattern = Config.eraserDashPattern
            azimuthLayer.isHidden = true

        case .lasso:
            // Crosshair cursor.
            let size = Config.crosshairArm * 2 + 4
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            nibView.frame = rect
            cursorLayer.frame = rect
            cursorLayer.path = crosshairPath(in: rect)
            cursorLayer.strokeColor = UIColor.label.withAlphaComponent(0.6).cgColor
            cursorLayer.fillColor   = UIColor.clear.cgColor
            cursorLayer.lineWidth   = 1.0
            azimuthLayer.isHidden = true

        case .other:
            // Fallback: generic blue circle.
            let size = Config.fallbackDiameter
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            nibView.frame = rect
            cursorLayer.frame = rect
            cursorLayer.path = UIBezierPath(ovalIn: rect).cgPath
            cursorLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
            cursorLayer.fillColor   = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
            cursorLayer.lineWidth   = Config.borderWidth
            azimuthLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
        }

        CATransaction.commit()
    }

    // MARK: - Show / Hide

    private func showNib(at position: CGPoint, altitude: CGFloat, azimuth: CGFloat, rollAngle: CGFloat) {
        // Centre the nib view on the hover position.
        nibView.center = position

        // Altitude-responsive transform.
        let normalised = min(altitude / (.pi / 2), 1.0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch currentTool?.tool {
        case .pen:
            // Pen: subtle altitude scaling (nearly perpendicular → full circle).
            let scale = 0.7 + normalised * 0.3
            nibView.transform = CGAffineTransform(scaleX: scale, y: scale)
            drawAzimuthLine(azimuth: azimuth)

        case .pencil:
            // Pencil: pronounced altitude effect (simulates tilt shading preview).
            // When flat, the cursor becomes an elongated ellipse in the azimuth direction.
            let scaleY = 0.35 + normalised * 0.65
            let rotation = CGAffineTransform(rotationAngle: azimuth)
            let scaling = CGAffineTransform(scaleX: 1.0, y: scaleY)
            nibView.transform = scaling.concatenating(rotation)
            // Azimuth line rotates with the transform, so skip manual drawing.
            azimuthLayer.isHidden = true

        case .highlighter:
            // Highlighter: rotate the flat rectangle along azimuth.
            nibView.transform = CGAffineTransform(rotationAngle: azimuth)

        case .fountainPen:
            // Fountain pen: combine azimuth rotation with barrel-roll angle.
            // Barrel roll rotates the calligraphic nib orientation.
            let combinedAngle = azimuth + rollAngle * 0.5
            nibView.transform = CGAffineTransform(rotationAngle: combinedAngle)
            // Altitude affects nib "pressure" — when flat, nib appears wider.
            let pressureScale = 0.6 + normalised * 0.4
            nibView.transform = nibView.transform.scaledBy(x: 1.0, y: pressureScale)

        case .eraser:
            // Eraser: altitude affects footprint size (tilt → larger area).
            let eraserScale = 0.7 + (1.0 - normalised) * 0.5
            nibView.transform = CGAffineTransform(scaleX: eraserScale, y: eraserScale)

        case .lasso:
            nibView.transform = .identity

        case .other, .none:
            let scale = 0.5 + normalised * 0.5
            nibView.transform = CGAffineTransform(scaleX: 1.0, y: scale)
            drawAzimuthLine(azimuth: azimuth)
        }

        CATransaction.commit()

        if !isHovering {
            isHovering = true
            UIView.animate(withDuration: Config.fadeInDuration) {
                self.nibView.alpha = 1
            }
        }
    }

    private func hideNib() {
        guard isHovering else { return }
        isHovering = false
        UIView.animate(withDuration: Config.fadeOutDuration) {
            self.nibView.alpha = 0
        }
    }

    // MARK: - Drawing Helpers

    private func drawAzimuthLine(azimuth: CGFloat) {
        let bounds = nibView.bounds
        let cx = bounds.midX
        let cy = bounds.midY
        let lineLength = min(bounds.width, bounds.height) / 2 - 2
        let dx = cos(azimuth) * lineLength
        let dy = sin(azimuth) * lineLength

        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - dx, y: cy - dy))
        path.addLine(to: CGPoint(x: cx + dx, y: cy + dy))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        azimuthLayer.path  = path
        azimuthLayer.frame = nibView.bounds
        CATransaction.commit()
    }

    /// Generates a cross-hatch grain pattern within `rect` (pencil tool).
    private func pencilGrainPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let spacing: CGFloat = 3.5
        var x = rect.minX
        // Diagonal lines from top-left to bottom-right.
        while x < rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x - rect.height, y: rect.maxY))
            x += spacing
        }
        return path
    }

    /// Generates a crosshair path for the lasso cursor.
    private func crosshairPath(in rect: CGRect) -> CGPath {
        let cx = rect.midX
        let cy = rect.midY
        let arm = Config.crosshairArm
        let gap: CGFloat = 2

        let path = CGMutablePath()
        // Horizontal arms.
        path.move(to: CGPoint(x: cx - arm, y: cy))
        path.addLine(to: CGPoint(x: cx - gap, y: cy))
        path.move(to: CGPoint(x: cx + gap, y: cy))
        path.addLine(to: CGPoint(x: cx + arm, y: cy))
        // Vertical arms.
        path.move(to: CGPoint(x: cx, y: cy - arm))
        path.addLine(to: CGPoint(x: cx, y: cy - gap))
        path.move(to: CGPoint(x: cx, y: cy + gap))
        path.addLine(to: CGPoint(x: cx, y: cy + arm))
        return path
    }

    /// Maps a tool width in points to a cursor diameter.
    private func cursorSize(for width: CGFloat) -> CGFloat {
        let raw = width * Config.widthToSizeScale
        return min(max(raw, Config.minCursorSize), Config.maxCursorSize)
    }
}
