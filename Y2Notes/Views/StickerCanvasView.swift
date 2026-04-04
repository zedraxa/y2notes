import UIKit

/// UIView overlay that renders placed stickers on a notebook page and handles
/// hit-testing, selection, and transform gestures (pan / pinch / rotate).
///
/// Inserted into the CanvasView layer stack between PKCanvasView and
/// ShapeOverlayView.  When the drawing tool is NOT `.sticker` / `.lasso`,
/// touch interaction is disabled so events pass through to the canvas below.
final class StickerCanvasView: UIView {

    // MARK: - State

    /// The stickers for the current page, sorted by zIndex.
    var stickers: [StickerInstance] = [] {
        didSet { setNeedsDisplay() }
    }

    /// ID of the currently selected sticker (renders handles).
    var selectedStickerID: UUID? {
        didSet { setNeedsDisplay() }
    }

    /// Callback when a sticker is selected by tap.
    var onStickerSelected: ((UUID?) -> Void)?

    /// Callback when a sticker's transform changes (position / scale / rotation).
    var onStickerTransformed: ((StickerInstance) -> Void)?

    /// Callback when a sticker is deleted via context interaction.
    var onStickerDeleted: ((UUID) -> Void)?

    /// Image provider — typically calls `StickerStore.image(for:)`.
    var imageProvider: ((String) -> UIImage?)?

    // MARK: - Private

    private var panStart: CGPoint = .zero
    private var initialPosition: CGPoint = .zero
    private var initialScale: CGFloat = 1.0
    private var initialRotation: CGFloat = 0
    private let snapAlignEngine = SnapAlignEffectEngine()
    private let microEngine = MicroInteractionEngine()
    private let interactionLayer = CALayer()

    /// Current adaptive effect intensity.  Set by the editor coordinator
    /// whenever `AdaptiveEffectsEngine.intensity` changes.
    var effectIntensity: EffectIntensity = .full {
        didSet {
            microEngine.effectIntensity = effectIntensity
            snapAlignEngine.effectIntensity = effectIntensity
        }
    }

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
        contentMode = .redraw

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        addGestureRecognizer(rotate)

        // Allow simultaneous pinch + rotate
        pinch.delegate = self
        rotate.delegate = self

        // Interaction overlay for physics effects (shadow / scale)
        microEngine.configureInteractionLayer(interactionLayer)
        layer.addSublayer(interactionLayer)
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let sorted = stickers.sorted(by: { $0.zIndex < $1.zIndex })
        for sticker in sorted {
            drawSticker(sticker, in: ctx)
        }
    }

    private func drawSticker(_ sticker: StickerInstance, in ctx: CGContext) {
        guard let image = imageProvider?(sticker.stickerID) else {
            drawPlaceholder(sticker, in: ctx)
            return
        }

        let size = CGSize(
            width: image.size.width * sticker.scale,
            height: image.size.height * sticker.scale
        )
        let origin = CGPoint(
            x: sticker.position.x - size.width / 2,
            y: sticker.position.y - size.height / 2
        )

        ctx.saveGState()
        ctx.translateBy(x: sticker.position.x, y: sticker.position.y)
        ctx.rotate(by: sticker.rotation)
        ctx.translateBy(x: -sticker.position.x, y: -sticker.position.y)

        // Contact shadow
        let isSelected = sticker.id == selectedStickerID
        let shadowBlur: CGFloat = isSelected ? 4 : 2
        let shadowOffset = CGSize(width: 0, height: isSelected ? 3 : 1)
        let shadowOpacity: CGFloat = isSelected ? 0.15 : 0.10
        ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: UIColor.black.withAlphaComponent(shadowOpacity).cgColor)

        ctx.setAlpha(sticker.opacity)
        image.draw(in: CGRect(origin: origin, size: size))

        ctx.restoreGState()

        // Selection handles
        if isSelected {
            drawHandles(for: sticker, size: size, in: ctx)
        }
    }

    private func drawPlaceholder(_ sticker: StickerInstance, in ctx: CGContext) {
        let placeholderSize: CGFloat = 48 * sticker.scale
        let rect = CGRect(
            x: sticker.position.x - placeholderSize / 2,
            y: sticker.position.y - placeholderSize / 2,
            width: placeholderSize,
            height: placeholderSize
        )

        ctx.saveGState()
        ctx.translateBy(x: sticker.position.x, y: sticker.position.y)
        ctx.rotate(by: sticker.rotation)
        ctx.translateBy(x: -sticker.position.x, y: -sticker.position.y)

        ctx.setAlpha(sticker.opacity * 0.3)
        ctx.setFillColor(UIColor.systemGray4.cgColor)
        ctx.fillEllipse(in: rect)

        ctx.restoreGState()

        if sticker.id == selectedStickerID {
            drawHandles(for: sticker, size: CGSize(width: placeholderSize, height: placeholderSize), in: ctx)
        }
    }

    private func drawHandles(for sticker: StickerInstance, size: CGSize, in ctx: CGContext) {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let center = sticker.position

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: sticker.rotation)

        // Selection rectangle
        let selRect = CGRect(x: -halfW, y: -halfH, width: size.width, height: size.height)
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(selRect)

        // Blue tint overlay
        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.06).cgColor)
        ctx.fill(selRect)

        // Corner handles (4 corners)
        let handleRadius: CGFloat = 5
        let corners: [CGPoint] = [
            CGPoint(x: -halfW, y: -halfH),
            CGPoint(x: halfW, y: -halfH),
            CGPoint(x: -halfW, y: halfH),
            CGPoint(x: halfW, y: halfH),
        ]
        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleRadius,
                y: corner.y - handleRadius,
                width: handleRadius * 2,
                height: handleRadius * 2
            )
            ctx.setFillColor(UIColor.systemBlue.cgColor)
            ctx.fillEllipse(in: handleRect)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: handleRect)
        }

        // Rotation handle — above top center
        let rotationHandleY: CGFloat = -halfH - 24
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: 0, y: -halfH))
        ctx.addLine(to: CGPoint(x: 0, y: rotationHandleY))
        ctx.strokePath()

        let rotRect = CGRect(x: -6, y: rotationHandleY - 6, width: 12, height: 12)
        ctx.setFillColor(UIColor.systemBlue.cgColor)
        ctx.fillEllipse(in: rotRect)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: rotRect)

        ctx.restoreGState()
    }

    // MARK: - Hit Testing

    /// Returns the sticker at the given point, or nil.
    func stickerAt(point: CGPoint) -> StickerInstance? {
        // Iterate in reverse z-order (topmost first)
        let sorted = stickers.sorted(by: { $0.zIndex > $1.zIndex })
        for sticker in sorted {
            let hitSize: CGFloat = 48 * sticker.scale
            let hitRect = CGRect(
                x: sticker.position.x - hitSize / 2,
                y: sticker.position.y - hitSize / 2,
                width: hitSize,
                height: hitSize
            )
            // Expand hit area by 10pt for easier selection
            if hitRect.insetBy(dx: -10, dy: -10).contains(point) {
                return sticker
            }
        }
        return nil
    }

    // MARK: - Gesture Handlers

    /// Computes a sticker's visual bounding rect (using image size or default).
    private func stickerBoundingRect(_ sticker: StickerInstance) -> CGRect {
        let baseSize: CGSize
        if let image = imageProvider?(sticker.stickerID) {
            baseSize = CGSize(width: image.size.width * sticker.scale,
                              height: image.size.height * sticker.scale)
        } else {
            let s: CGFloat = 48 * sticker.scale
            baseSize = CGSize(width: s, height: s)
        }
        return CGRect(x: sticker.position.x - baseSize.width / 2,
                      y: sticker.position.y - baseSize.height / 2,
                      width: baseSize.width, height: baseSize.height)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let tapped = stickerAt(point: point) {
            // Deselect previous if switching
            if selectedStickerID != nil && selectedStickerID != tapped.id {
                microEngine.hideInteractionLayer(interactionLayer)
            }
            selectedStickerID = tapped.id
            onStickerSelected?(tapped.id)

            // Physics: scale up + glow on select
            let rect = stickerBoundingRect(tapped)
            microEngine.showInteractionLayer(interactionLayer, for: rect)
            microEngine.playSelectScale(on: interactionLayer)
            microEngine.playSelectionGlow(on: interactionLayer)
        } else {
            // Physics: scale down on deselect
            if selectedStickerID != nil {
                microEngine.playDeselectScale(on: interactionLayer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.microEngine.hideInteractionLayer(self?.interactionLayer ?? CALayer())
                }
            }
            selectedStickerID = nil
            onStickerSelected?(nil)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let id = selectedStickerID,
              let idx = stickers.firstIndex(where: { $0.id == id }),
              !stickers[idx].isLocked else { return }

        switch gesture.state {
        case .began:
            panStart = gesture.location(in: self)
            initialPosition = stickers[idx].position
            snapAlignEngine.prepareHaptics()

            // Physics: soft shadow + keep overlay tracking
            microEngine.playSoftShadow(on: interactionLayer, dragDirection: .zero)
        case .changed:
            let current = gesture.location(in: self)
            let dx = current.x - panStart.x
            let dy = current.y - panStart.y
            var newPos = CGPoint(x: initialPosition.x + dx, y: initialPosition.y + dy)

            // Center snap guides
            let pageCenter = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            var snappedX = false
            var snappedY = false
            if abs(newPos.x - pageCenter.x) < StickerConstants.snapDistance {
                newPos.x = pageCenter.x
                snappedX = true
            }
            if abs(newPos.y - pageCenter.y) < StickerConstants.snapDistance {
                newPos.y = pageCenter.y
                snappedY = true
            }

            // Snap & align visual/haptic feedback
            snapAlignEngine.playSnapFeedback(
                on: layer, snappedX: snappedX, snappedY: snappedY
            )

            stickers[idx].position = newPos
            setNeedsDisplay()

            // Physics: update shadow direction + track overlay
            let vel = gesture.velocity(in: self)
            let mag = max(hypot(vel.x, vel.y), 1.0)
            let dir = CGPoint(x: vel.x / mag, y: vel.y / mag)
            microEngine.playSoftShadow(on: interactionLayer, dragDirection: dir)
            let rect = stickerBoundingRect(stickers[idx])
            microEngine.showInteractionLayer(interactionLayer, for: rect)

        case .ended, .cancelled:
            // Physics: inertia nudge + release bounce
            let vel = gesture.velocity(in: self)
            let decayFactor: CGFloat = 0.12
            let inertiaX = vel.x * decayFactor
            let inertiaY = vel.y * decayFactor
            if abs(inertiaX) > 1 || abs(inertiaY) > 1 {
                stickers[idx].position.x += inertiaX
                stickers[idx].position.y += inertiaY
            }
            microEngine.resetSoftShadow(on: interactionLayer)
            microEngine.playReleaseBounce(on: interactionLayer)
            setNeedsDisplay()

            // Re-position overlay after inertia
            let rect = stickerBoundingRect(stickers[idx])
            microEngine.showInteractionLayer(interactionLayer, for: rect)

            onStickerTransformed?(stickers[idx])
        default: break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let id = selectedStickerID,
              let idx = stickers.firstIndex(where: { $0.id == id }),
              !stickers[idx].isLocked else { return }

        switch gesture.state {
        case .began:
            initialScale = stickers[idx].scale
        case .changed:
            let newScale = initialScale * gesture.scale
            stickers[idx].scale = min(max(newScale, StickerConstants.minScale), StickerConstants.maxScale)
            setNeedsDisplay()
        case .ended, .cancelled:
            onStickerTransformed?(stickers[idx])
        default: break
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let id = selectedStickerID,
              let idx = stickers.firstIndex(where: { $0.id == id }),
              !stickers[idx].isLocked else { return }

        switch gesture.state {
        case .began:
            initialRotation = stickers[idx].rotation
        case .changed:
            var newRotation = initialRotation + gesture.rotation
            // Rotation snap (0°, 45°, 90°, 180°, etc.)
            let snapAngles: [CGFloat] = [0, .pi/4, .pi/2, 3 * .pi/4, .pi, -.pi/4, -.pi/2, -3 * .pi/4]
            for snap in snapAngles {
                if abs(newRotation - snap) < StickerConstants.rotationSnapZone {
                    newRotation = snap
                    break
                }
            }
            stickers[idx].rotation = newRotation
            setNeedsDisplay()
        case .ended, .cancelled:
            onStickerTransformed?(stickers[idx])
        default: break
        }
    }

    // MARK: - Touch Pass-through

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // When interaction is disabled, pass through all touches
        guard isUserInteractionEnabled else { return false }
        // Only claim touches that land on a sticker (or while one is selected)
        if selectedStickerID != nil { return true }
        return stickerAt(point: point) != nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension StickerCanvasView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow pinch + rotation simultaneously
        let isPinchOrRotate = gestureRecognizer is UIPinchGestureRecognizer || gestureRecognizer is UIRotationGestureRecognizer
        let otherIsPinchOrRotate = otherGestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIRotationGestureRecognizer
        return isPinchOrRotate && otherIsPinchOrRotate
    }
}
