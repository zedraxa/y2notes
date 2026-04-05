import UIKit

// MARK: - Shape Canvas View

/// UIView overlay that renders and handles interaction for shape objects.
///
/// Sits above the sticker layer and below the PKDrawing layer in the
/// NoteEditorView stack.  When the active tool is `.shape` or a shape
/// is selected, this view becomes interactive; otherwise it passes
/// through all touches.
///
/// Responsibilities:
/// - Renders shape objects as CAShapeLayer sublayers
/// - Hit-tests taps for selection
/// - Handles pan/resize gestures for manipulation
/// - Passes through non-shape touches to layers below
final class ShapeCanvasView: UIView, EffectIntensityReceiver {

    // MARK: - Properties

    /// The shapes currently placed on this page, sorted by zIndex.
    var shapes: [ShapeInstance] = [] {
        didSet { setNeedsLayout() }
    }

    /// The ID of the currently selected shape, or nil.
    var selectedShapeID: UUID? {
        didSet { updateSelection() }
    }

    /// Whether the shape tool is the active drawing tool.
    var isShapeToolActive: Bool = false {
        didSet { isUserInteractionEnabled = isShapeToolActive || selectedShapeID != nil }
    }

    /// Callback fired when shapes are modified (moved, resized, etc).
    var onShapesChanged: (([ShapeInstance]) -> Void)?

    /// Callback fired when a shape is selected or deselected.
    var onSelectionChanged: ((UUID?) -> Void)?

    // MARK: - Private State

    private var shapeLayers: [UUID: CAShapeLayer] = [:]
    private var handleLayers: [CAShapeLayer] = []
    private var selectionBorderLayer: CAShapeLayer?

    private var dragStartPoint: CGPoint = .zero
    private var dragStartFrame: CGRect = .zero
    private var activeHandle: HandlePosition?
    private var isDragging = false
    private let snapAlignEngine = SnapAlignEffectEngine()
    private let microEngine = MicroInteractionEngine()

    /// Current adaptive effect intensity.  Set by the editor coordinator.
    var effectIntensity: EffectIntensity = .full {
        didSet {
            microEngine.effectIntensity = effectIntensity
            snapAlignEngine.effectIntensity = effectIntensity
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        renderShapes()
    }

    // MARK: - Rendering

    private func renderShapes() {
        // Remove stale layers
        let currentIDs = Set(shapes.map(\.id))
        for (id, layer) in shapeLayers where !currentIDs.contains(id) {
            layer.removeFromSuperlayer()
            shapeLayers.removeValue(forKey: id)
        }

        // Create/update layers
        for shape in shapes.sorted(by: { $0.zIndex < $1.zIndex }) {
            let shapeLayer: CAShapeLayer
            if let existing = shapeLayers[shape.id] {
                shapeLayer = existing
            } else {
                shapeLayer = CAShapeLayer()
                layer.addSublayer(shapeLayer)
                shapeLayers[shape.id] = shapeLayer
            }

            configureLayer(shapeLayer, for: shape)
        }

        updateSelection()
    }

    private func configureLayer(_ shapeLayer: CAShapeLayer, for shape: ShapeInstance) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        shapeLayer.path = makePath(for: shape).cgPath
        shapeLayer.strokeColor = shape.style.strokeColor.cgColor
        shapeLayer.lineWidth = shape.style.strokeWidth
        shapeLayer.fillColor = shape.style.fillColor?.cgColor ?? UIColor.clear.cgColor
        shapeLayer.opacity = Float(shape.style.opacity)
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round

        // Apply rotation around shape center
        if shape.rotation != 0 {
            let center = CGPoint(
                x: shape.frame.midX,
                y: shape.frame.midY
            )
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, center.x, center.y, 0)
            transform = CATransform3DRotate(transform, shape.rotation, 0, 0, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            shapeLayer.transform = transform
        } else {
            shapeLayer.transform = CATransform3DIdentity
        }

        shapeLayer.frame = bounds

        CATransaction.commit()
    }

    private func makePath(for shape: ShapeInstance) -> UIBezierPath {
        let rect = shape.frame
        switch shape.shapeType {
        case .line:
            let start = resolveEndpoint(shape.startNorm, in: rect, default: CGPoint(x: rect.minX, y: rect.minY))
            let end = resolveEndpoint(shape.endNorm, in: rect, default: CGPoint(x: rect.maxX, y: rect.maxY))
            let path = UIBezierPath()
            path.move(to: start)
            path.addLine(to: end)
            return path

        case .rectangle:
            return UIBezierPath(roundedRect: rect, cornerRadius: 0)

        case .circle:
            return UIBezierPath(ovalIn: rect)

        case .arrow:
            let start = resolveEndpoint(shape.startNorm, in: rect, default: CGPoint(x: rect.minX, y: rect.midY))
            let end = resolveEndpoint(shape.endNorm, in: rect, default: CGPoint(x: rect.maxX, y: rect.midY))
            let path = UIBezierPath()
            path.move(to: start)
            path.addLine(to: end)

            // Arrowhead
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLen = min(16, hypot(end.x - start.x, end.y - start.y) * 0.25)
            let left = CGPoint(
                x: end.x - headLen * cos(angle - .pi / 6),
                y: end.y - headLen * sin(angle - .pi / 6)
            )
            let right = CGPoint(
                x: end.x - headLen * cos(angle + .pi / 6),
                y: end.y - headLen * sin(angle + .pi / 6)
            )
            path.move(to: end)
            path.addLine(to: left)
            path.move(to: end)
            path.addLine(to: right)
            return path
        }
    }

    private func resolveEndpoint(_ norm: CGPoint?, in rect: CGRect, default defaultPt: CGPoint) -> CGPoint {
        guard let n = norm else { return defaultPt }
        return CGPoint(x: rect.minX + n.x * rect.width, y: rect.minY + n.y * rect.height)
    }

    // MARK: - Selection Visuals

    private func updateSelection() {
        // Remove old selection visuals
        selectionBorderLayer?.removeFromSuperlayer()
        selectionBorderLayer = nil
        for h in handleLayers { h.removeFromSuperlayer() }
        handleLayers.removeAll()

        guard let selectedID = selectedShapeID,
              let shape = shapes.first(where: { $0.id == selectedID }) else { return }

        let border = CAShapeLayer()
        border.path = UIBezierPath(rect: shape.frame).cgPath
        border.strokeColor = UIColor.systemBlue.cgColor
        border.lineWidth = 1.5
        border.fillColor = UIColor.systemBlue.withAlphaComponent(0.06).cgColor
        border.lineDashPattern = [4, 3]
        border.frame = bounds

        if shape.rotation != 0 {
            let center = CGPoint(x: shape.frame.midX, y: shape.frame.midY)
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, center.x, center.y, 0)
            transform = CATransform3DRotate(transform, shape.rotation, 0, 0, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            border.transform = transform
        }

        layer.addSublayer(border)
        selectionBorderLayer = border

        // Add corner handles
        let handleSize = ShapeConstants.handleSize
        for position in HandlePosition.corners {
            let handleLayer = CAShapeLayer()
            let center = handlePoint(for: position, in: shape.frame)
            let rect = CGRect(
                x: center.x - handleSize / 2,
                y: center.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            handleLayer.path = UIBezierPath(ovalIn: rect).cgPath
            handleLayer.fillColor = UIColor.systemBlue.cgColor
            handleLayer.strokeColor = UIColor.white.cgColor
            handleLayer.lineWidth = 1.5
            handleLayer.frame = bounds
            layer.addSublayer(handleLayer)
            handleLayers.append(handleLayer)
        }
    }

    // MARK: - Handle Positions

    private func handlePoint(for position: HandlePosition, in rect: CGRect) -> CGPoint {
        switch position {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    // MARK: - Hit Testing

    private func shapeAt(_ point: CGPoint) -> ShapeInstance? {
        // Test in reverse z-order (top shapes first)
        for shape in shapes.sorted(by: { $0.zIndex > $1.zIndex }) {
            let tolerance = ShapeConstants.lineHitTolerance
            switch shape.shapeType {
            case .line, .arrow:
                let start = resolveEndpoint(
                    shape.startNorm, in: shape.frame,
                    default: CGPoint(x: shape.frame.minX, y: shape.frame.minY)
                )
                let end = resolveEndpoint(
                    shape.endNorm, in: shape.frame,
                    default: CGPoint(x: shape.frame.maxX, y: shape.frame.maxY)
                )
                let dist = distanceFromPointToLine(point, lineStart: start, lineEnd: end)
                if dist < tolerance { return shape }

            case .rectangle, .circle:
                let expanded = shape.frame.insetBy(dx: -tolerance, dy: -tolerance)
                if expanded.contains(point) { return shape }
            }
        }
        return nil
    }

    private func distanceFromPointToLine(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(point.x - lineStart.x, point.y - lineStart.y) }

        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSq))
        let projX = lineStart.x + t * dx
        let projY = lineStart.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }

    private func handleAt(_ point: CGPoint) -> HandlePosition? {
        guard let selectedID = selectedShapeID,
              let shape = shapes.first(where: { $0.id == selectedID }) else { return nil }

        let tolerance: CGFloat = 20
        for position in HandlePosition.corners {
            let hp = handlePoint(for: position, in: shape.frame)
            if hypot(point.x - hp.x, point.y - hp.y) < tolerance {
                return position
            }
        }
        return nil
    }

    // MARK: - Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let shape = shapeAt(point) {
            // Deselect previous shape's layer effects
            if let prevID = selectedShapeID, prevID != shape.id,
               let prevLayer = shapeLayers[prevID] {
                microEngine.playDeselectScale(on: prevLayer)
            }
            selectedShapeID = shape.id
            onSelectionChanged?(shape.id)

            // Physics: scale up + glow on select
            if let shapeLayer = shapeLayers[shape.id] {
                microEngine.playSelectScale(on: shapeLayer)
                microEngine.playSelectionGlow(on: shapeLayer)
            }
        } else {
            // Physics: scale down previous selection
            if let prevID = selectedShapeID, let prevLayer = shapeLayers[prevID] {
                microEngine.playDeselectScale(on: prevLayer)
            }
            selectedShapeID = nil
            onSelectionChanged?(nil)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            snapAlignEngine.prepareHaptics()

            // Check if dragging a handle
            if let handle = handleAt(point) {
                activeHandle = handle
                if let selectedID = selectedShapeID,
                   let shape = shapes.first(where: { $0.id == selectedID }) {
                    dragStartPoint = point
                    dragStartFrame = shape.frame
                    isDragging = true
                }
                return
            }

            // Check if dragging a shape
            if let shape = shapeAt(point), !shape.isLocked {
                selectedShapeID = shape.id
                onSelectionChanged?(shape.id)
                dragStartPoint = point
                dragStartFrame = shape.frame
                isDragging = true
                activeHandle = nil

                // Physics: scale up + shadow on drag start
                if let shapeLayer = shapeLayers[shape.id] {
                    microEngine.playSelectScale(on: shapeLayer)
                    microEngine.playSoftShadow(on: shapeLayer, dragDirection: .zero)
                }
            }

        case .changed:
            guard isDragging, let selectedID = selectedShapeID,
                  let idx = shapes.firstIndex(where: { $0.id == selectedID }) else { return }

            if let handle = activeHandle {
                // Resize via handle drag
                let dx = point.x - dragStartPoint.x
                let dy = point.y - dragStartPoint.y
                shapes[idx].frame = resizedFrame(
                    dragStartFrame, handle: handle, dx: dx, dy: dy
                )
            } else {
                // Move shape
                let dx = point.x - dragStartPoint.x
                let dy = point.y - dragStartPoint.y
                var newFrame = dragStartFrame.offsetBy(dx: dx, dy: dy)

                // Check alignment with other shapes
                let movedCenter = CGPoint(x: newFrame.midX, y: newFrame.midY)
                var snappedX = false
                var snappedY = false

                for (i, other) in shapes.enumerated() where i != idx {
                    let otherCenter = CGPoint(x: other.frame.midX, y: other.frame.midY)

                    // Horizontal centre alignment
                    if !snappedX && abs(movedCenter.x - otherCenter.x) < ShapeConstants.snapDistance {
                        newFrame.origin.x = otherCenter.x - newFrame.width / 2
                        snappedX = true
                        // Flash vertical guide line through aligned centres
                        snapAlignEngine.playLineGuideFlash(
                            from: CGPoint(x: otherCenter.x, y: 0),
                            to: CGPoint(x: otherCenter.x, y: bounds.height),
                            in: layer
                        )
                    }

                    // Vertical centre alignment
                    if !snappedY && abs(movedCenter.y - otherCenter.y) < ShapeConstants.snapDistance {
                        newFrame.origin.y = otherCenter.y - newFrame.height / 2
                        snappedY = true
                        // Flash horizontal guide line through aligned centres
                        snapAlignEngine.playLineGuideFlash(
                            from: CGPoint(x: 0, y: otherCenter.y),
                            to: CGPoint(x: bounds.width, y: otherCenter.y),
                            in: layer
                        )
                    }
                }

                shapes[idx].frame = newFrame

                // Haptic feedback for perfect dual-axis alignment
                snapAlignEngine.updatePerfectAlignment(isAligned: snappedX && snappedY)

                // Physics: update shadow direction
                if let shapeLayer = shapeLayers[selectedID] {
                    let vel = gesture.velocity(in: self)
                    let mag = max(hypot(vel.x, vel.y), 1.0)
                    let dir = CGPoint(x: vel.x / mag, y: vel.y / mag)
                    microEngine.playSoftShadow(on: shapeLayer, dragDirection: dir)
                }
            }
            renderShapes()

        case .ended, .cancelled:
            if isDragging {
                // Physics: inertia + release bounce on the shape layer
                if activeHandle == nil, let selectedID = selectedShapeID,
                   let idx = shapes.firstIndex(where: { $0.id == selectedID }) {
                    let vel = gesture.velocity(in: self)
                    let decayFactor: CGFloat = 0.12
                    let inertiaX = vel.x * decayFactor
                    let inertiaY = vel.y * decayFactor
                    if abs(inertiaX) > 1 || abs(inertiaY) > 1 {
                        shapes[idx].frame.origin.x += inertiaX
                        shapes[idx].frame.origin.y += inertiaY
                    }
                    if let shapeLayer = shapeLayers[selectedID] {
                        microEngine.resetSoftShadow(on: shapeLayer)
                        microEngine.playReleaseBounce(on: shapeLayer)
                    }
                    renderShapes()
                }
                isDragging = false
                activeHandle = nil
                onShapesChanged?(shapes)
            }

        default:
            break
        }
    }

    private func resizedFrame(_ original: CGRect, handle: HandlePosition, dx: CGFloat, dy: CGFloat) -> CGRect {
        var x = original.origin.x
        var y = original.origin.y
        var w = original.width
        var h = original.height

        switch handle {
        case .topLeft:
            x += dx; y += dy; w -= dx; h -= dy
        case .topRight:
            y += dy; w += dx; h -= dy
        case .bottomLeft:
            x += dx; w -= dx; h += dy
        case .bottomRight:
            w += dx; h += dy
        }

        // Enforce minimum dimension
        let minDim = ShapeConstants.minimumDimension
        if w < minDim { w = minDim; x = original.maxX - minDim }
        if h < minDim { h = minDim; y = original.maxY - minDim }

        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Touch pass-through

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled else { return false }
        // If shape tool is active, consume all touches for creation
        if isShapeToolActive && selectedShapeID == nil { return false }
        // If we have a selection, consume touches near the shape
        if selectedShapeID != nil { return true }
        // Otherwise only consume if touching a shape
        return shapeAt(point) != nil
    }
}

// MARK: - Handle Position

enum HandlePosition: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    static var corners: [HandlePosition] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
}
