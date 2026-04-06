import UIKit

// MARK: - HoverToolInfo

/// A lightweight snapshot of the active drawing-tool state fed to the ghost-nib
/// overlay so it can render a tool-faithful cursor while the Apple Pencil hovers.
struct HoverToolInfo {
    /// The logical drawing tool the user has selected.
    let tool: DrawingTool
    /// The active ink colour.
    let color: UIColor
    /// Raw tool width as set by the user (tool-space points).
    let width: CGFloat
    /// Stroke opacity (0.05–1.0; 1.0 = fully opaque).
    let opacity: CGFloat
    /// Width multiplier from the tool's personality (1× for most, 3× for highlighter).
    let widthMultiplier: CGFloat
    /// Whether to draw the azimuth direction line (enabled for tilt/roll-aware tools).
    let showsAzimuthLine: Bool
    /// The eraser mode (bitmap / vector), relevant when `tool == .eraser`.
    let eraserMode: EraserMode

    /// Sensible defaults used before the coordinator provides real data.
    static let `default` = HoverToolInfo(
        tool: .pen,
        color: .systemBlue,
        width: 3.0,
        opacity: 1.0,
        widthMultiplier: 1.0,
        showsAzimuthLine: false,
        eraserMode: .bitmap
    )
}

// MARK: - PencilHoverOverlayView

/// A transparent, non-interactive overlay view that renders a "ghost nib" cursor
/// while an Apple Pencil is hovering above the screen (M2+ iPad Pro, iOS 16.1+).
///
/// The nib appearance adapts to the active drawing tool: colour, diameter, opacity,
/// and shape all reflect the user's current selection.  Call `configure(with:)`
/// whenever the tool state changes so the cursor stays faithful to the tool.
///
/// Place this view as a sibling **above** the PKCanvasView in Z-order, with the
/// same frame.  Set `isUserInteractionEnabled = false` so all touches fall through
/// to the canvas.
///
/// On devices or OS versions that do not support Apple Pencil hover the view
/// remains invisible and has zero cost.
final class PencilHoverOverlayView: UIView {

    // MARK: - Subviews

    private let nibView = UIView()
    private let azimuthLayer = CAShapeLayer()

    // MARK: - State

    private var isHovering = false
    private var toolInfo: HoverToolInfo = .default

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

        // Ghost-nib circle: a semi-transparent ring that follows the Pencil tip.
        nibView.isUserInteractionEnabled = false
        nibView.alpha = 0
        addSubview(nibView)

        // Azimuth line: shows the tilt direction of the Pencil for tilt-aware tools.
        azimuthLayer.fillColor = UIColor.clear.cgColor
        nibView.layer.addSublayer(azimuthLayer)

        // Apply initial appearance from default tool info.
        applyToolAppearance()
    }

    // MARK: - Public API

    /// Update the ghost nib to reflect a new drawing-tool state.
    ///
    /// Call this whenever the user switches tool, colour, or width — even during
    /// an active hover session.  Appearance changes take effect immediately.
    func configure(with info: HoverToolInfo) {
        toolInfo = info
        applyToolAppearance()
    }

    /// Update the ghost nib position and orientation.
    ///
    /// - Parameters:
    ///   - position: Pencil hover location in this view's coordinate space.
    ///               Pass `nil` to hide the overlay.
    ///   - altitude: Pencil altitude in radians (0 = flat, π/2 = perpendicular).
    ///   - azimuth:  Pencil azimuth in radians.
    func update(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        if let position = position {
            showNib(at: position, altitude: altitude, azimuth: azimuth)
        } else {
            hideNib()
        }
    }

    // MARK: - Appearance

    /// Resize the nib view and repaint colours / border to match `toolInfo`.
    private func applyToolAppearance() {
        let d = computedNibDiameter
        // Update size without moving the center (bounds change preserves center).
        nibView.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        nibView.layer.cornerRadius = d / 2

        switch toolInfo.tool {
        case .eraser:
            // Hollow grey ring: previews eraser reach without suggesting a colour.
            nibView.layer.borderColor  = UIColor.systemGray.withAlphaComponent(0.7).cgColor
            nibView.layer.borderWidth  = 1.5
            nibView.backgroundColor    = .clear
            azimuthLayer.isHidden      = true

        case .lasso, .shape, .sticker:
            // Neutral blue ring: these tools have no meaningful ink colour.
            nibView.layer.borderColor  = UIColor.systemBlue.withAlphaComponent(0.55).cgColor
            nibView.layer.borderWidth  = 1.0
            nibView.backgroundColor    = UIColor.systemBlue.withAlphaComponent(0.06)
            azimuthLayer.isHidden      = true

        case .highlighter:
            // Wide semi-transparent fill to suggest the marker's translucency.
            let fill = max(0.18, min(0.35, toolInfo.opacity * 0.4))
            nibView.layer.borderColor  = toolInfo.color.withAlphaComponent(0.65).cgColor
            nibView.layer.borderWidth  = 2.0
            nibView.backgroundColor    = toolInfo.color.withAlphaComponent(fill)
            azimuthLayer.isHidden      = true

        case .pen:
            // Crisp ink-coloured ring matching the pen's precise character.
            nibView.layer.borderColor  = toolInfo.color.withAlphaComponent(0.85).cgColor
            nibView.layer.borderWidth  = 1.5
            nibView.backgroundColor    = toolInfo.color.withAlphaComponent(max(0.06, toolInfo.opacity * 0.12))
            azimuthLayer.isHidden      = !toolInfo.showsAzimuthLine
            azimuthLayer.strokeColor   = toolInfo.color.withAlphaComponent(0.50).cgColor
            azimuthLayer.lineWidth     = 1.0

        case .pencil:
            // Slightly lower opacity to hint at the pencil's softer, textured feel.
            nibView.layer.borderColor  = toolInfo.color.withAlphaComponent(0.75).cgColor
            nibView.layer.borderWidth  = 1.5
            nibView.backgroundColor    = toolInfo.color.withAlphaComponent(max(0.05, toolInfo.opacity * 0.10))
            azimuthLayer.isHidden      = !toolInfo.showsAzimuthLine
            azimuthLayer.strokeColor   = toolInfo.color.withAlphaComponent(0.45).cgColor
            azimuthLayer.lineWidth     = 1.0

        case .fountainPen:
            // Bolder border and thicker azimuth line to hint at calligraphic character.
            nibView.layer.borderColor  = toolInfo.color.withAlphaComponent(0.90).cgColor
            nibView.layer.borderWidth  = 2.0
            nibView.backgroundColor    = toolInfo.color.withAlphaComponent(max(0.08, toolInfo.opacity * 0.14))
            azimuthLayer.isHidden      = !toolInfo.showsAzimuthLine
            azimuthLayer.strokeColor   = toolInfo.color.withAlphaComponent(0.55).cgColor
            azimuthLayer.lineWidth     = 1.5

        case .text:
            // Neutral cursor for text tool.
            nibView.layer.borderColor  = UIColor.systemBlue.withAlphaComponent(0.55).cgColor
            nibView.layer.borderWidth  = 1.0
            nibView.backgroundColor    = UIColor.systemBlue.withAlphaComponent(0.06)
            azimuthLayer.isHidden      = true
        }
    }

    /// Nib circle diameter derived from the active tool's width.
    private var computedNibDiameter: CGFloat {
        switch toolInfo.tool {
        case .eraser:
            return 26
        case .lasso, .sticker:
            return 14
        case .shape:
            return 16
        default:
            // Scale diameter from tool width, respecting the tool's width multiplier
            // (e.g. highlighter uses 3× so it previews as a wider nib).
            let actual = toolInfo.width * toolInfo.widthMultiplier
            return max(12, min(48, actual * 2.5 + 8))
        }
    }

    // MARK: - Show / Hide

    private func showNib(at position: CGPoint, altitude: CGFloat, azimuth: CGFloat) {
        // Centre the nib on the hover point.
        nibView.center = position

        // Apply the tilt-responsive transform so the contact patch shapes correctly.
        nibView.transform = tiltTransform(altitude: altitude, azimuth: azimuth)

        // Redraw the azimuth direction indicator line when visible.
        if !azimuthLayer.isHidden {
            drawAzimuthLine(azimuth: azimuth)
        }

        if !isHovering {
            isHovering = true
            UIView.animate(withDuration: 0.12) {
                self.nibView.alpha = 1
            }
        }
    }

    private func hideNib() {
        guard isHovering else { return }
        isHovering = false
        UIView.animate(withDuration: 0.18) {
            self.nibView.alpha = 0
        }
    }

    // MARK: - Tilt Transform

    /// Builds the affine transform that shapes the nib ellipse from pencil tilt.
    ///
    /// - When held perpendicular (altitude ≈ π/2) the nib is a perfect circle.
    /// - When tilted (altitude → 0) the nib compresses into an ellipse whose
    ///   major axis is aligned with the pencil's lean direction (azimuth).
    ///
    /// The compound transform is:
    ///   1. Rotate by `azimuth`  — align the local X axis with the lean direction.
    ///   2. Squish local Y by `scaleY`  — flatten the axis perpendicular to the lean.
    ///   3. Rotate back by `–azimuth`  — restore the original orientation.
    private func tiltTransform(altitude: CGFloat, azimuth: CGFloat) -> CGAffineTransform {
        // Tilt shading is only meaningful for round-nib inking tools.
        switch toolInfo.tool {
        case .highlighter, .eraser, .lasso, .shape, .sticker:
            return .identity
        default:
            break
        }

        let normalised = min(altitude / (.pi / 2), 1.0) // 0 (flat) → 1 (perpendicular)
        let scaleY     = 0.35 + normalised * 0.65       // 0.35 (flat) → 1.0 (perpendicular)

        // Nearly perpendicular — avoid precision noise in the rotation.
        guard normalised < 0.98 else { return .identity }

        let r1     = CGAffineTransform(rotationAngle: azimuth)
        let squish = CGAffineTransform(scaleX: 1.0, y: scaleY)
        let r2     = CGAffineTransform(rotationAngle: -azimuth)
        return r1.concatenating(squish).concatenating(r2)
    }

    // MARK: - Azimuth Line

    private func drawAzimuthLine(azimuth: CGFloat) {
        let d          = nibView.bounds.width
        let r          = d / 2
        let lineLength = r - 2
        let dx         = CGFloat(cos(azimuth)) * lineLength
        let dy         = CGFloat(sin(azimuth)) * lineLength

        let path = CGMutablePath()
        path.move(to: CGPoint(x: r - dx, y: r - dy))
        path.addLine(to: CGPoint(x: r + dx, y: r + dy))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        azimuthLayer.path  = path
        azimuthLayer.frame = nibView.bounds
        CATransaction.commit()
    }
}
