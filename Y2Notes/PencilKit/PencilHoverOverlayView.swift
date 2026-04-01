import UIKit

// MARK: - PencilHoverOverlayView

/// A transparent, non-interactive overlay view that renders a "ghost nib" cursor
/// while an Apple Pencil is hovering above the screen (M2+ iPad Pro, iOS 16.1+).
///
/// Place this view as a sibling **above** the PKCanvasView in Z-order, with the
/// same frame.  Set `isUserInteractionEnabled = false` so all touches fall through
/// to the canvas.
///
/// On devices or OS versions that do not support Apple Pencil hover the view
/// remains invisible and has zero cost.
final class PencilHoverOverlayView: UIView {

    // MARK: - Configuration

    /// Diameter of the ghost nib circle in points.
    private let nibDiameter: CGFloat = 18

    // MARK: - Subviews

    private let nibView = UIView()
    private let azimuthLayer = CAShapeLayer()

    // MARK: - State

    private var isHovering = false

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

        // Ghost-nib circle: a small semi-transparent ring that follows the Pencil.
        nibView.frame = CGRect(x: 0, y: 0, width: nibDiameter, height: nibDiameter)
        nibView.layer.cornerRadius = nibDiameter / 2
        nibView.layer.borderWidth  = 1.5
        nibView.layer.borderColor  = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
        nibView.backgroundColor    = UIColor.systemBlue.withAlphaComponent(0.08)
        nibView.isUserInteractionEnabled = false
        nibView.alpha = 0
        addSubview(nibView)

        // Azimuth line: shows the tilt direction of the Pencil.
        azimuthLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
        azimuthLayer.lineWidth   = 1
        azimuthLayer.fillColor   = UIColor.clear.cgColor
        nibView.layer.addSublayer(azimuthLayer)
    }

    // MARK: - Public API

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

    // MARK: - Private

    private func showNib(at position: CGPoint, altitude: CGFloat, azimuth: CGFloat) {
        // Centre the nib view on the hover position.
        nibView.center = position

        // Scale the nib to reflect the Pencil's tilt: when nearly flat (altitude ≈ 0)
        // the contact patch is an ellipse; when perpendicular the nib appears as a point.
        // altitude range: 0 (flat) → π/2 (perpendicular).
        let normalised = min(altitude / (.pi / 2), 1.0)
        let scale = 0.5 + normalised * 0.5  // 0.5 (flat) → 1.0 (perpendicular)
        nibView.transform = CGAffineTransform(scaleX: 1.0, y: scale)

        // Draw azimuth indicator line inside the nib circle.
        drawAzimuthLine(azimuth: azimuth)

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

    private func drawAzimuthLine(azimuth: CGFloat) {
        let r    = nibDiameter / 2
        let cx   = r
        let cy   = r
        let lineLength = r - 2
        let dx   = CGFloat(cos(azimuth)) * lineLength
        let dy   = CGFloat(sin(azimuth)) * lineLength

        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - dx, y: cy - dy))
        path.addLine(to: CGPoint(x: cx + dx, y: cy + dy))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        azimuthLayer.path   = path
        azimuthLayer.frame  = nibView.bounds
        CATransaction.commit()
    }
}
