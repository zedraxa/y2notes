import UIKit

// MARK: - HoverToolKind

/// The visual category of the active drawing tool.
/// Drives ghost-nib shape, colour, and border style in `PencilHoverOverlayView`.
enum HoverToolKind {
    case pen
    case pencil
    case highlighter
    case fountainPen
    case eraser
    case lasso
    case other
}

// MARK: - HoverToolInfo

/// A lightweight snapshot of the active tool's visual identity, passed to
/// `PencilHoverOverlayView.configure(with:)` on every hover event.
struct HoverToolInfo {
    /// Logical tool kind — drives nib shape, border style, and fill strategy.
    var kind: HoverToolKind
    /// Active ink colour (ignored for eraser / lasso which use neutral colours).
    var color: UIColor
    /// Width normalised to 0…1, mapping to ghost-nib diameter 12…48 pt.
    var normalizedWidth: CGFloat
    /// Stroke opacity in 0…1.  Applied as an additional alpha factor on the nib fill.
    var opacity: CGFloat
}

// MARK: - PencilHoverOverlayView

/// A transparent, non-interactive overlay view that renders a tool-aware "ghost
/// nib" cursor while an Apple Pencil is hovering above the screen
/// (M2+ iPad Pro, iOS 16.1+).
///
/// Place this view as a sibling **above** the PKCanvasView in Z-order, with the
/// same frame.  Set `isUserInteractionEnabled = false` so all touches fall through
/// to the canvas.
///
/// **Usage**
/// 1. Call `configure(with:)` whenever the active tool, colour, or width changes
///    — or on every hover event if the tool might change mid-session.
/// 2. Call `update(position:altitude:azimuth:)` on every hover event to move and
///    tilt the nib.
///
/// On devices or OS versions that do not support Apple Pencil hover the view
/// remains invisible and has zero cost.
final class PencilHoverOverlayView: UIView {

    // MARK: - Subviews / layers

    private let nibView      = UIView()
    private let azimuthLayer = CAShapeLayer()

    // MARK: - State

    private var isHovering   = false
    private var currentInfo  = HoverToolInfo(
        kind: .pen,
        color: .systemBlue,
        normalizedWidth: 0.1,
        opacity: 1.0
    )

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
        backgroundColor          = .clear
        clipsToBounds            = false

        nibView.isUserInteractionEnabled = false
        nibView.alpha = 0
        addSubview(nibView)

        azimuthLayer.fillColor  = UIColor.clear.cgColor
        azimuthLayer.lineWidth  = 1.0
        nibView.layer.addSublayer(azimuthLayer)

        applyToolAppearance(currentInfo)
    }

    // MARK: - Public API

    /// Update the ghost-nib appearance to match the active drawing tool.
    ///
    /// Inexpensive — safe to call on every hover event to keep the cursor in
    /// sync when the tool might change during a hover session.
    func configure(with info: HoverToolInfo) {
        currentInfo = info
        applyToolAppearance(info)
    }

    /// Update the ghost nib position and orientation.
    ///
    /// - Parameters:
    ///   - position: Pencil hover location in **this view's** coordinate space.
    ///               Pass `nil` to hide the overlay.
    ///   - altitude: Pencil altitude in radians (0 = flat, π/2 = perpendicular).
    ///   - azimuth:  Pencil azimuth in radians (tilt direction).
    func update(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        if let position {
            showNib(at: position, altitude: altitude, azimuth: azimuth)
        } else {
            hideNib()
        }
    }

    // MARK: - Appearance

    private func applyToolAppearance(_ info: HoverToolInfo) {
        let d = computedNibDiameter(for: info)

        switch info.kind {

        case .eraser:
            // Hollow ring — no fill, neutral border.
            nibView.bounds             = CGRect(x: 0, y: 0, width: d, height: d)
            nibView.backgroundColor    = .clear
            nibView.layer.borderColor  = UIColor.systemGray.withAlphaComponent(0.65).cgColor
            nibView.layer.borderWidth  = 2.0
            nibView.layer.cornerRadius = d / 2
            azimuthLayer.strokeColor   = UIColor.systemGray.withAlphaComponent(0.35).cgColor

        case .highlighter:
            // Chisel-tip: wider than tall, stadium-shaped, semi-transparent.
            let w = d * 1.6
            let h = max(d * 0.6, 8)
            nibView.bounds             = CGRect(x: 0, y: 0, width: w, height: h)
            nibView.backgroundColor    = info.color.withAlphaComponent(0.30 * info.opacity)
            nibView.layer.borderColor  = info.color.withAlphaComponent(0.55).cgColor
            nibView.layer.borderWidth  = 1.0
            nibView.layer.cornerRadius = h / 2
            azimuthLayer.strokeColor   = info.color.withAlphaComponent(0.40).cgColor

        case .lasso:
            // Thin teal ring — selection cursor.
            nibView.bounds             = CGRect(x: 0, y: 0, width: d, height: d)
            nibView.backgroundColor    = UIColor.systemTeal.withAlphaComponent(0.08)
            nibView.layer.borderColor  = UIColor.systemTeal.withAlphaComponent(0.60).cgColor
            nibView.layer.borderWidth  = 1.5
            nibView.layer.cornerRadius = d / 2
            azimuthLayer.strokeColor   = UIColor.systemTeal.withAlphaComponent(0.40).cgColor

        case .pen, .pencil, .fountainPen, .other:
            // Ink-coloured filled dot.
            nibView.bounds             = CGRect(x: 0, y: 0, width: d, height: d)
            nibView.backgroundColor    = info.color.withAlphaComponent(0.12 * info.opacity)
            nibView.layer.borderColor  = info.color.withAlphaComponent(0.80).cgColor
            nibView.layer.borderWidth  = 1.5
            nibView.layer.cornerRadius = d / 2
            azimuthLayer.strokeColor   = info.color.withAlphaComponent(0.45).cgColor
        }

        // Sync the azimuth layer frame to the (possibly updated) nib bounds.
        azimuthLayer.frame = nibView.bounds
    }

    /// Maps `normalizedWidth` (0…1) to a diameter in the range 12…48 pt.
    private func computedNibDiameter(for info: HoverToolInfo) -> CGFloat {
        12 + min(max(info.normalizedWidth, 0), 1) * 36
    }

    // MARK: - Show / hide

    private func showNib(at position: CGPoint, altitude: CGFloat, azimuth: CGFloat) {
        nibView.center = position

        // Build a tilt transform that combines azimuth rotation with altitude-based
        // Y-scale, producing a rotated ellipse that mimics the pencil contact patch:
        // • altitude ≈ π/2 (perpendicular) → circle (yScale = 1.0)
        // • altitude ≈ 0   (flat)           → narrow ellipse (yScale = 0.5),
        //   rotated so the narrow axis aligns with the tilt direction.
        let normalised = min(altitude / (.pi / 2), 1.0)
        let yScale     = 0.5 + normalised * 0.5
        nibView.transform = CGAffineTransform(rotationAngle: azimuth).scaledBy(x: 1.0, y: yScale)

        // Draw azimuth indicator along the local X-axis; the parent rotation above
        // will aim it in the correct direction automatically.
        drawAzimuthLine()

        if !isHovering {
            isHovering = true
            UIView.animate(withDuration: 0.12) { self.nibView.alpha = 1 }
        }
    }

    private func hideNib() {
        guard isHovering else { return }
        isHovering = false
        UIView.animate(withDuration: 0.18) { self.nibView.alpha = 0 }
    }

    private func drawAzimuthLine() {
        // The nibView is rotated by azimuth in showNib, so draw the indicator
        // along the local X-axis and let the transform aim it correctly.
        let b  = nibView.bounds
        let cx = b.midX
        let cy = b.midY
        let r  = min(b.width, b.height) / 2 - 2

        let path = CGMutablePath()
        path.move(to:    CGPoint(x: cx - r, y: cy))
        path.addLine(to: CGPoint(x: cx + r, y: cy))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        azimuthLayer.path  = path
        azimuthLayer.frame = nibView.bounds
        CATransaction.commit()
    }
}
