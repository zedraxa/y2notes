import UIKit

// MARK: - TextCanvasView

/// Transparent overlay that renders `TextObject` instances on the page and
/// handles tap-to-place, tap-to-select, drag, pinch-to-scale, and rotation
/// gestures. Sits above the shape canvas in the UIView hierarchy.
///
/// Follows the same delegation pattern as `ShapeCanvasView` and
/// `WidgetCanvasView`: all state changes bubble up via callbacks.
final class TextCanvasView: UIView {

    // MARK: - State

    /// The text objects for the current page. Setting this triggers a redraw.
    var textObjects: [TextObject] = [] {
        didSet { setNeedsDisplay() }
    }

    /// The ID of the currently selected object, or nil when nothing is selected.
    var selectedTextID: UUID? {
        didSet { setNeedsDisplay() }
    }

    /// When true, tapping empty canvas space places a new text object.
    var isTextToolActive: Bool = false

    // MARK: - Callbacks

    /// Called whenever objects are created, moved, resized, or rotated.
    var onObjectsChanged: (([TextObject]) -> Void)?
    /// Called when the user selects or deselects an object.
    var onSelectionChanged: ((UUID?) -> Void)?
    /// Called when a double-tap requests inline text editing.
    var onEditRequested: ((UUID) -> Void)?

    // MARK: - Drag / Transform state

    private var draggedID: UUID?
    private var dragStartObjectFrame: CGRect = .zero
    private var dragStartLocation: CGPoint = .zero
    private var isDragging = false

    private var pinchStartSize: CGSize = .zero
    private var rotateStartAngle: CGFloat = 0

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
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        addGestureRecognizer(pinch)
        addGestureRecognizer(rotate)
        pinch.delegate  = self
        rotate.delegate = self
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let sorted = textObjects.sorted { $0.zIndex < $1.zIndex }
        for obj in sorted {
            drawObject(obj, in: ctx)
        }
    }

    private func drawObject(_ obj: TextObject, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAlpha(obj.opacity)

        // Translate to centre for rotation.
        let cx = obj.frame.midX
        let cy = obj.frame.midY
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: obj.rotation)
        let hw = obj.frame.width  / 2
        let hh = obj.frame.height / 2
        ctx.translateBy(x: -hw, y: -hh)

        let localRect = CGRect(origin: .zero, size: obj.frame.size)

        // Shadow
        if obj.shadowOpacity > 0 {
            ctx.setShadow(
                offset: CGSize(width: 1, height: 2),
                blur: obj.shadowRadius,
                color: UIColor.black.withAlphaComponent(CGFloat(obj.shadowOpacity)).cgColor
            )
        }

        // Background fill
        if let bg = obj.backgroundColor {
            bg.setFill()
            UIBezierPath(roundedRect: localRect, cornerRadius: obj.borderRadius).fill()
        }

        // Reset shadow before border / text (avoids double-shadowing)
        ctx.setShadow(offset: .zero, blur: 0)

        // Border
        if obj.borderWidth > 0, let bc = obj.borderColor {
            bc.setStroke()
            let borderRect = localRect.insetBy(dx: obj.borderWidth / 2, dy: obj.borderWidth / 2)
            let bp = UIBezierPath(roundedRect: borderRect, cornerRadius: obj.borderRadius)
            bp.lineWidth = obj.borderWidth
            bp.stroke()
        }

        // Text
        let inset: CGFloat = 6
        obj.attributedString().draw(in: localRect.insetBy(dx: inset, dy: inset))

        // Selection ring
        if obj.id == selectedTextID {
            UIColor.systemBlue.withAlphaComponent(0.65).setStroke()
            let selPath = UIBezierPath(
                roundedRect: localRect.insetBy(dx: -2, dy: -2),
                cornerRadius: obj.borderRadius + 2
            )
            selPath.lineWidth = 1.5
            selPath.setLineDash([4, 3], count: 2, phase: 0)
            selPath.stroke()
        }

        ctx.restoreGState()
    }

    // MARK: - Hit Testing

    private func hitObject(at point: CGPoint) -> TextObject? {
        // Test in reverse z-order so top objects are hit first.
        let sorted = textObjects.sorted { $0.zIndex > $1.zIndex }
        for obj in sorted {
            if objectContains(obj, point: point) { return obj }
        }
        return nil
    }

    /// Rotates `point` into the object's local coordinate space and checks bounds.
    private func objectContains(_ obj: TextObject, point: CGPoint) -> Bool {
        let cx = obj.frame.midX
        let cy = obj.frame.midY
        let cosA = Foundation.cos(-obj.rotation)
        let sinA = Foundation.sin(-obj.rotation)
        let dx = point.x - cx
        let dy = point.y - cy
        let lx = dx * cosA - dy * sinA + obj.frame.width  / 2
        let ly = dx * sinA + dy * cosA + obj.frame.height / 2
        return CGRect(origin: .zero, size: obj.frame.size).contains(CGPoint(x: lx, y: ly))
    }

    // MARK: - Tap Gesture

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let pt = g.location(in: self)
        if let hit = hitObject(at: pt) {
            guard !hit.isLocked else { return }
            selectedTextID = hit.id
            onSelectionChanged?(hit.id)
        } else if isTextToolActive {
            placeNewObject(at: pt)
        } else {
            selectedTextID = nil
            onSelectionChanged?(nil)
        }
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        let pt = g.location(in: self)
        if let hit = hitObject(at: pt), !hit.isLocked {
            selectedTextID = hit.id
            onSelectionChanged?(hit.id)
            onEditRequested?(hit.id)
        }
    }

    private func placeNewObject(at pt: CGPoint) {
        let size = CGSize(width: 200, height: 60)
        let origin = CGPoint(x: pt.x - size.width / 2, y: pt.y - size.height / 2)
        let newObj = TextObject(
            frame: CGRect(origin: origin, size: size),
            zIndex: (textObjects.map(\.zIndex).max() ?? -1) + 1
        )
        textObjects.append(newObj)
        selectedTextID = newObj.id
        onObjectsChanged?(textObjects)
        onSelectionChanged?(newObj.id)
        onEditRequested?(newObj.id)
    }

    // MARK: - Pan Gesture (move)

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let pt = g.location(in: self)
        switch g.state {
        case .began:
            if let hit = hitObject(at: pt), !hit.isLocked {
                draggedID = hit.id
                dragStartObjectFrame = hit.frame
                dragStartLocation = pt
                isDragging = true
            }
        case .changed:
            guard isDragging,
                  let id = draggedID,
                  let idx = textObjects.firstIndex(where: { $0.id == id }) else { return }
            let delta = CGPoint(x: pt.x - dragStartLocation.x, y: pt.y - dragStartLocation.y)
            textObjects[idx].frame.origin = CGPoint(
                x: dragStartObjectFrame.origin.x + delta.x,
                y: dragStartObjectFrame.origin.y + delta.y
            )
            setNeedsDisplay()
        case .ended, .cancelled:
            if isDragging { onObjectsChanged?(textObjects) }
            isDragging = false
            draggedID  = nil
        default:
            break
        }
    }

    // MARK: - Pinch Gesture (resize)

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let id = selectedTextID,
              let idx = textObjects.firstIndex(where: { $0.id == id }),
              !textObjects[idx].isLocked else { return }
        switch g.state {
        case .began:
            pinchStartSize = textObjects[idx].frame.size
        case .changed:
            let newW = max(60, pinchStartSize.width  * g.scale)
            let newH = max(40, pinchStartSize.height * g.scale)
            let cx = textObjects[idx].frame.midX
            let cy = textObjects[idx].frame.midY
            textObjects[idx].frame = CGRect(x: cx - newW / 2, y: cy - newH / 2,
                                            width: newW, height: newH)
            setNeedsDisplay()
        case .ended:
            onObjectsChanged?(textObjects)
        default:
            break
        }
    }

    // MARK: - Rotation Gesture

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        guard let id = selectedTextID,
              let idx = textObjects.firstIndex(where: { $0.id == id }),
              !textObjects[idx].isLocked else { return }
        switch g.state {
        case .began:
            rotateStartAngle = textObjects[idx].rotation
        case .changed:
            textObjects[idx].rotation = rotateStartAngle + g.rotation
            setNeedsDisplay()
        case .ended:
            onObjectsChanged?(textObjects)
        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate (simultaneous pinch + rotate)

extension TextCanvasView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer)
        || (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
    }
}
