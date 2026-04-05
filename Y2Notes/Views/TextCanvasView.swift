import UIKit

// MARK: - Text Canvas View

/// UIView overlay that renders and handles interaction for text objects.
///
/// Sits above the widget layer in the NoteEditorView canvas stack.
/// When the text tool is active, tapping empty space creates a new text
/// object.  Tapping an existing text object selects it; double-tapping
/// opens it for inline editing via a `UITextView`.  Selected objects can
/// be moved by dragging and resized by dragging their corner handles.
///
/// All touches outside active text objects are passed through to the
/// layers below when the text tool is not active.
final class TextCanvasView: UIView, EffectIntensityReceiver {

    // MARK: - Properties

    /// The text objects currently placed on this page, sorted by zIndex.
    var textObjects: [TextObject] = [] {
        didSet { setNeedsLayout() }
    }

    /// The ID of the currently selected text object, or nil.
    var selectedTextObjectID: UUID? {
        didSet { updateSelectionVisuals() }
    }

    /// Whether the text tool is the active drawing tool.
    var isTextToolActive: Bool = false {
        didSet {
            isUserInteractionEnabled = isTextToolActive || selectedTextObjectID != nil
        }
    }

    /// Called when text objects are modified (moved, resized, content changed).
    var onTextObjectsChanged: (([TextObject]) -> Void)?

    /// Called when a text object is selected or deselected.
    var onSelectionChanged: ((UUID?) -> Void)?

    /// Called when a new text object should be created at the given page position.
    var onPlaceTextObject: ((CGPoint) -> Void)?

    /// Called when a single text object is transformed (moved/resized/rotated).
    var onTextObjectTransformed: ((TextObject) -> Void)?

    // MARK: - Private State

    private var textLayers: [UUID: CATextLayer] = [:]
    private var backgroundLayers: [UUID: CALayer] = [:]
    private var handleLayers: [CAShapeLayer] = []
    private var selectionBorderLayer: CAShapeLayer?

    private var dragStartPoint: CGPoint = .zero
    private var dragStartFrame: CGRect = .zero
    private var activeHandle: HandlePosition?
    private var isDragging = false
    private var rotationStartAngle: CGFloat = 0

    // Inline editing
    private var editingTextView: UITextView?
    private var editingObjectID: UUID?

    // Engines
    private let microEngine = MicroInteractionEngine()
    private let snapAlignEngine = SnapAlignEffectEngine()

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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // Single-tap should not fire when a double-tap is recognized
        tap.require(toFail: doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotate.delegate = self
        addGestureRecognizer(rotate)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        renderTextObjects()
    }

    // MARK: - Rendering

    private func renderTextObjects() {
        let currentIDs = Set(textObjects.map(\.id))

        // Remove stale layers
        for id in textLayers.keys where !currentIDs.contains(id) {
            textLayers[id]?.removeFromSuperlayer()
            textLayers.removeValue(forKey: id)
            backgroundLayers[id]?.removeFromSuperlayer()
            backgroundLayers.removeValue(forKey: id)
        }

        // Create / update layers for each object (sorted bottom to top)
        for obj in textObjects.sorted(by: { $0.zIndex < $1.zIndex }) {
            configureBackground(for: obj)
            configureTextLayer(for: obj)
        }

        updateSelectionVisuals()
    }

    private func configureBackground(for obj: TextObject) {
        let bgLayer: CALayer
        if let existing = backgroundLayers[obj.id] {
            bgLayer = existing
        } else {
            bgLayer = CALayer()
            layer.addSublayer(bgLayer)
            backgroundLayers[obj.id] = bgLayer
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        bgLayer.frame = obj.frame
        bgLayer.cornerRadius = 4
        bgLayer.opacity = Float(obj.opacity)

        if let bg = obj.backgroundColor {
            bgLayer.backgroundColor = bg.cgColor
        } else {
            bgLayer.backgroundColor = UIColor.clear.cgColor
        }

        // Apply rotation around object center
        if obj.rotation != 0 {
            let center = CGPoint(x: obj.frame.midX, y: obj.frame.midY)
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, center.x - obj.frame.origin.x, center.y - obj.frame.origin.y, 0)
            transform = CATransform3DRotate(transform, obj.rotation, 0, 0, 1)
            transform = CATransform3DTranslate(transform, -(center.x - obj.frame.origin.x), -(center.y - obj.frame.origin.y), 0)
            bgLayer.transform = transform
        } else {
            bgLayer.transform = CATransform3DIdentity
        }

        CATransaction.commit()
    }

    private func configureTextLayer(for obj: TextObject) {
        let textLayer: CATextLayer
        if let existing = textLayers[obj.id] {
            textLayer = existing
        } else {
            textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.isWrapped = true
            textLayer.truncationMode = .none
            layer.addSublayer(textLayer)
            textLayers[obj.id] = textLayer
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        textLayer.frame = obj.frame
        textLayer.string = obj.content.isEmpty ? "" : obj.content
        textLayer.fontSize = obj.fontSize
        textLayer.foregroundColor = obj.textColor.cgColor
        textLayer.alignmentMode = caAlignmentMode(for: obj.textAlignment)
        textLayer.opacity = Float(obj.opacity)

        // Apply rotation around object center
        if obj.rotation != 0 {
            let center = CGPoint(x: obj.frame.midX, y: obj.frame.midY)
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, center.x - obj.frame.origin.x, center.y - obj.frame.origin.y, 0)
            transform = CATransform3DRotate(transform, obj.rotation, 0, 0, 1)
            transform = CATransform3DTranslate(transform, -(center.x - obj.frame.origin.x), -(center.y - obj.frame.origin.y), 0)
            textLayer.transform = transform
        } else {
            textLayer.transform = CATransform3DIdentity
        }

        CATransaction.commit()
    }

    private func caAlignmentMode(for alignment: NSTextAlignment) -> CATextLayerAlignmentMode {
        switch alignment {
        case .center: return .center
        case .right:  return .right
        default:      return .left
        }
    }

    // MARK: - Selection Visuals

    private func updateSelectionVisuals() {
        selectionBorderLayer?.removeFromSuperlayer()
        selectionBorderLayer = nil
        for h in handleLayers { h.removeFromSuperlayer() }
        handleLayers.removeAll()

        guard let selectedID = selectedTextObjectID,
              let obj = textObjects.first(where: { $0.id == selectedID }) else { return }

        let border = CAShapeLayer()
        border.path = UIBezierPath(roundedRect: obj.frame, cornerRadius: 4).cgPath
        border.strokeColor = UIColor.systemBlue.cgColor
        border.lineWidth = 1.5
        border.fillColor = UIColor.systemBlue.withAlphaComponent(0.05).cgColor
        border.lineDashPattern = [4, 3]
        border.frame = bounds
        layer.addSublayer(border)
        selectionBorderLayer = border

        // Corner handles
        let handleSize = TextObjectConstants.handleSize
        for position in HandlePosition.corners {
            let handleLayer = CAShapeLayer()
            let center = handlePoint(for: position, in: obj.frame)
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

    private func textObjectAt(_ point: CGPoint) -> TextObject? {
        for obj in textObjects.sorted(by: { $0.zIndex > $1.zIndex }) {
            let expanded = obj.frame.insetBy(
                dx: -TextObjectConstants.hitTolerance,
                dy: -TextObjectConstants.hitTolerance
            )
            if expanded.contains(point) { return obj }
        }
        return nil
    }

    private func handleAt(_ point: CGPoint) -> HandlePosition? {
        guard let selectedID = selectedTextObjectID,
              let obj = textObjects.first(where: { $0.id == selectedID }) else { return nil }
        let tolerance: CGFloat = 20
        for position in HandlePosition.corners {
            let hp = handlePoint(for: position, in: obj.frame)
            if hypot(point.x - hp.x, point.y - hp.y) < tolerance {
                return position
            }
        }
        return nil
    }

    // MARK: - Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)

        // Commit any in-progress editing first
        commitEditing()

        if let obj = textObjectAt(point) {
            selectedTextObjectID = obj.id
            onSelectionChanged?(obj.id)
            if let layer = textLayers[obj.id] {
                microEngine.playSelectScale(on: layer)
            }
        } else {
            // Deselect
            if let prevID = selectedTextObjectID, let prev = textLayers[prevID] {
                microEngine.playDeselectScale(on: prev)
            }
            selectedTextObjectID = nil
            onSelectionChanged?(nil)

            // Place new text object when text tool is active
            if isTextToolActive {
                onPlaceTextObject?(point)
            }
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard let obj = textObjectAt(point), !obj.isLocked else { return }

        // Select if not already
        selectedTextObjectID = obj.id
        onSelectionChanged?(obj.id)

        beginEditing(obj)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            commitEditing()
            snapAlignEngine.prepareHaptics()

            if let handle = handleAt(point) {
                activeHandle = handle
                if let selectedID = selectedTextObjectID,
                   let obj = textObjects.first(where: { $0.id == selectedID }) {
                    dragStartPoint = point
                    dragStartFrame = obj.frame
                    isDragging = true
                }
                return
            }

            if let obj = textObjectAt(point), !obj.isLocked {
                selectedTextObjectID = obj.id
                onSelectionChanged?(obj.id)
                dragStartPoint = point
                dragStartFrame = obj.frame
                isDragging = true
                activeHandle = nil

                if let l = textLayers[obj.id] {
                    microEngine.playSelectScale(on: l)
                    microEngine.playSoftShadow(on: l, dragDirection: .zero)
                }
            }

        case .changed:
            guard isDragging,
                  let selectedID = selectedTextObjectID,
                  let idx = textObjects.firstIndex(where: { $0.id == selectedID }) else { return }

            let dx = point.x - dragStartPoint.x
            let dy = point.y - dragStartPoint.y

            if let handle = activeHandle {
                textObjects[idx].frame = resizedFrame(dragStartFrame, handle: handle, dx: dx, dy: dy)
            } else {
                var newFrame = dragStartFrame.offsetBy(dx: dx, dy: dy)

                // Snap alignment with other text objects
                let movedCenter = CGPoint(x: newFrame.midX, y: newFrame.midY)
                var snappedX = false
                var snappedY = false

                for (i, other) in textObjects.enumerated() where i != idx {
                    let otherCenter = CGPoint(x: other.frame.midX, y: other.frame.midY)

                    // Horizontal centre alignment
                    if !snappedX && abs(movedCenter.x - otherCenter.x) < TextObjectConstants.snapDistance {
                        newFrame.origin.x = otherCenter.x - newFrame.width / 2
                        snappedX = true
                        snapAlignEngine.playLineGuideFlash(
                            from: CGPoint(x: otherCenter.x, y: 0),
                            to: CGPoint(x: otherCenter.x, y: bounds.height),
                            in: layer
                        )
                    }

                    // Vertical centre alignment
                    if !snappedY && abs(movedCenter.y - otherCenter.y) < TextObjectConstants.snapDistance {
                        newFrame.origin.y = otherCenter.y - newFrame.height / 2
                        snappedY = true
                        snapAlignEngine.playLineGuideFlash(
                            from: CGPoint(x: 0, y: otherCenter.y),
                            to: CGPoint(x: bounds.width, y: otherCenter.y),
                            in: layer
                        )
                    }
                }

                textObjects[idx].frame = newFrame

                // Haptic feedback for perfect dual-axis alignment
                snapAlignEngine.updatePerfectAlignment(isAligned: snappedX && snappedY)

                if let l = textLayers[selectedID] {
                    let vel = gesture.velocity(in: self)
                    let mag = max(hypot(vel.x, vel.y), 1)
                    let dir = CGPoint(x: vel.x / mag, y: vel.y / mag)
                    microEngine.playSoftShadow(on: l, dragDirection: dir)
                }
            }

            renderTextObjects()

        case .ended, .cancelled:
            if isDragging {
                if activeHandle == nil,
                   let selectedID = selectedTextObjectID,
                   let idx = textObjects.firstIndex(where: { $0.id == selectedID }) {
                    let vel = gesture.velocity(in: self)
                    let decay: CGFloat = 0.12
                    let ix = vel.x * decay
                    let iy = vel.y * decay
                    if abs(ix) > 1 || abs(iy) > 1 {
                        textObjects[idx].frame.origin.x += ix
                        textObjects[idx].frame.origin.y += iy
                    }
                    if let l = textLayers[selectedID] {
                        microEngine.resetSoftShadow(on: l)
                        microEngine.playReleaseBounce(on: l)
                    }
                    renderTextObjects()
                    onTextObjectTransformed?(textObjects[idx])
                }
                isDragging = false
                activeHandle = nil
                onTextObjectsChanged?(textObjects)
            }

        default:
            break
        }
    }

    // MARK: - Rotation Gesture

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let selectedID = selectedTextObjectID,
              let idx = textObjects.firstIndex(where: { $0.id == selectedID }),
              !textObjects[idx].isLocked else { return }

        switch gesture.state {
        case .began:
            rotationStartAngle = textObjects[idx].rotation
        case .changed:
            textObjects[idx].rotation = rotationStartAngle + gesture.rotation
            renderTextObjects()
        case .ended, .cancelled:
            onTextObjectsChanged?(textObjects)
            onTextObjectTransformed?(textObjects[idx])
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
        case .topLeft:     x += dx; y += dy; w -= dx; h -= dy
        case .topRight:    y += dy; w += dx; h -= dy
        case .bottomLeft:  x += dx; w -= dx; h += dy
        case .bottomRight: w += dx; h += dy
        }

        let minDim = TextObjectConstants.minimumDimension
        if w < minDim { w = minDim; x = original.maxX - minDim }
        if h < minDim { h = minDim; y = original.maxY - minDim }

        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Inline Editing

    private func beginEditing(_ obj: TextObject) {
        guard textObjects.contains(where: { $0.id == obj.id }) else { return }

        // Hide the CATextLayer while editing
        textLayers[obj.id]?.isHidden = true

        let tv = UITextView(frame: obj.frame)
        tv.text = obj.content
        tv.font = UIFont.systemFont(ofSize: obj.fontSize)
        tv.textColor = obj.textColor
        tv.textAlignment = obj.textAlignment
        tv.backgroundColor = obj.backgroundColor ?? .clear
        tv.isScrollEnabled = false
        tv.layer.borderColor = UIColor.systemBlue.cgColor
        tv.layer.borderWidth = 1.5
        tv.layer.cornerRadius = 4
        tv.delegate = self

        addSubview(tv)
        tv.becomeFirstResponder()

        editingTextView = tv
        editingObjectID = obj.id
    }

    private func commitEditing() {
        guard let tv = editingTextView,
              let editingID = editingObjectID,
              let idx = textObjects.firstIndex(where: { $0.id == editingID }) else {
            editingTextView?.removeFromSuperview()
            editingTextView = nil
            editingObjectID = nil
            return
        }

        textObjects[idx].content = tv.text ?? ""
        textLayers[editingID]?.isHidden = false
        tv.resignFirstResponder()
        tv.removeFromSuperview()
        editingTextView = nil
        editingObjectID = nil
        renderTextObjects()
        onTextObjectsChanged?(textObjects)
    }

    // MARK: - Touch Pass-through

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled else { return false }
        // Always consume when editing
        if editingObjectID != nil { return true }
        // Consume all touches when text tool active (to place on tap)
        if isTextToolActive { return true }
        // When selected, consume to allow moving
        if selectedTextObjectID != nil { return true }
        // Otherwise only intercept touches on existing objects
        return textObjectAt(point) != nil
    }
}

// MARK: - UITextViewDelegate

extension TextCanvasView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard let editingID = editingObjectID,
              let idx = textObjects.firstIndex(where: { $0.id == editingID }) else { return }

        textObjects[idx].content = textView.text ?? ""

        // Grow the text view / frame to fit the content
        let fittingSize = textView.sizeThatFits(
            CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude)
        )
        let newHeight = max(fittingSize.height, TextObjectConstants.minimumDimension)
        textView.frame.size.height = newHeight
        textObjects[idx].frame.size.height = newHeight
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        commitEditing()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TextCanvasView: UIGestureRecognizerDelegate {
    /// Allow rotation to be recognized simultaneously with pan.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow rotation + pan simultaneously
        if gestureRecognizer is UIRotationGestureRecognizer || otherGestureRecognizer is UIRotationGestureRecognizer {
            return true
        }
        return false
    }
}
