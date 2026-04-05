import UIKit

// MARK: - EraserCursorOverlay

/// A transparent, non-interactive overlay that renders an eraser-tip cursor ring
/// while an Apple Pencil is hovering above the screen with the eraser tool active.
///
/// The ring diameter matches the current `eraserWidth` so the user can see exactly
/// how large an area will be affected.  Pixel-mode sub-types show a solid coral
/// ring; vector-mode sub-types show a dashed violet ring to communicate "fuzzy"
/// stroke detection.
///
/// Place this view as a sibling **above** the PKCanvasView in Z-order, with the
/// same frame.  Set `isUserInteractionEnabled = false` so all touches fall through.
final class EraserCursorOverlay: UIView {

    // MARK: - Subviews

    private let ringLayer   = CAShapeLayer()
    private let centerMark  = CAShapeLayer()

    // MARK: - State

    private var isHovering  = false
    private var lastSubType: EraserSubType = .standard
    private var lastWidth:   CGFloat       = EraserSubType.standard.defaultWidth

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

        layer.addSublayer(ringLayer)
        layer.addSublayer(centerMark)

        // Ring layer — sized/styled dynamically in updateAppearance().
        ringLayer.fillColor  = UIColor.clear.cgColor
        ringLayer.lineWidth  = 1.5
        ringLayer.opacity    = 0

        // Center cross-hair mark.
        centerMark.fillColor    = UIColor.clear.cgColor
        centerMark.lineWidth    = 1
        centerMark.lineCap      = .round
        centerMark.opacity      = 0
    }

    // MARK: - Public API

    /// Update the cursor ring's position, size, and appearance.
    ///
    /// - Parameters:
    ///   - position:    Hover location in this view's coordinate space.
    ///                  Pass `nil` to hide the overlay.
    ///   - subType:     Active eraser sub-type (controls colour + dash pattern).
    ///   - eraserWidth: Tip width in points (controls ring diameter).
    func update(position: CGPoint?, subType: EraserSubType, eraserWidth: CGFloat) {
        // Update appearance if sub-type or width changed.
        if subType != lastSubType || eraserWidth != lastWidth {
            lastSubType = subType
            lastWidth   = eraserWidth
            updateAppearance()
        }

        if let point = position {
            showCursor(at: point)
        } else {
            hideCursor()
        }
    }

    // MARK: - Appearance

    private func updateAppearance() {
        let isVector = lastSubType.eraserMode == .vector

        // Colour: coral for pixel modes, violet for vector modes.
        let strokeColor = isVector
            ? UIColor.systemPurple.withAlphaComponent(0.85).cgColor
            : UIColor.systemOrange.withAlphaComponent(0.85).cgColor

        ringLayer.strokeColor   = strokeColor
        centerMark.strokeColor  = strokeColor

        // Dash pattern: solid for pixel, dashed for vector (fuzzy feel).
        ringLayer.lineDashPattern = isVector ? [4, 3] : nil

        // Redraw path for the new diameter.
        let diameter = max(lastWidth, 6)
        let halfD    = diameter / 2
        let ringPath = UIBezierPath(ovalIn: CGRect(x: -halfD, y: -halfD,
                                                   width: diameter, height: diameter))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.path = ringPath.cgPath

        // Tiny center cross-hair (4 pt total width, always the same size).
        let cross = CGMutablePath()
        cross.move(to: CGPoint(x: -3, y: 0)); cross.addLine(to: CGPoint(x: 3, y: 0))
        cross.move(to: CGPoint(x: 0, y: -3)); cross.addLine(to: CGPoint(x: 0, y: 3))
        centerMark.path = cross

        CATransaction.commit()
    }

    // MARK: - Visibility

    private func showCursor(at position: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.position   = position
        centerMark.position  = position
        CATransaction.commit()

        guard !isHovering else { return }
        isHovering = true
        UIView.animate(withDuration: 0.12) {
            self.ringLayer.opacity   = 1
            self.centerMark.opacity  = 0.7
        }
    }

    private func hideCursor() {
        guard isHovering else { return }
        isHovering = false
        UIView.animate(withDuration: 0.18) {
            self.ringLayer.opacity   = 0
            self.centerMark.opacity  = 0
        }
    }
}
