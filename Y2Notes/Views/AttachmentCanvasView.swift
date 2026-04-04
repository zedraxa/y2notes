import UIKit
import os

private let canvasLogger = Logger(subsystem: "com.y2notes", category: "AttachmentCanvas")

/// A UIView overlay that renders attachment thumbnails using Core Graphics and
/// handles finger-based hit-test, selection, move, and resize gestures.
///
/// Inserted between `StickerCanvasView` and `ShapeCanvasView` in the overlay stack.
/// Pencil touches always pass through to `PKCanvasView` for drawing.
final class AttachmentCanvasView: UIView {

    // MARK: - Public State

    /// Attachments for the current page, sorted by zIndex for rendering.
    var attachments: [AttachmentObject] = [] {
        didSet { if !renderingPaused { setNeedsDisplay() } }
    }

    /// ID of the currently selected attachment (renders handles + allows move/resize).
    var selectedAttachmentID: UUID? {
        didSet { setNeedsDisplay() }
    }

    /// Note ID used to look up thumbnails from `AttachmentStore`.
    var noteID: UUID = UUID()

    /// Current zoom scale of the parent canvas, used for full-res upgrade decisions.
    var zoomScale: CGFloat = 1.0 {
        didSet { handleZoomScaleChange() }
    }

    /// When true, rendering and async loads are paused (set during active pencil strokes).
    var renderingPaused: Bool = false

    // MARK: - Callbacks

    /// Called when a tap selects or deselects an attachment.
    var onSelectionChanged: ((UUID?) -> Void)?

    /// Called when an attachment's frame changes (move or resize).
    var onAttachmentTransformed: ((AttachmentObject) -> Void)?

    /// Called when attachments array is mutated (for persistence).
    var onAttachmentsChanged: (([AttachmentObject]) -> Void)?

    // MARK: - Private State

    /// Image provider — backed by `AttachmentStore.shared`.
    private let store = AttachmentStore.shared

    /// Tracks which handle is being dragged during resize (nil = body move).
    private var activeHandle: HandleCorner?

    /// State for pan gesture.
    private var panStart: CGPoint = .zero
    private var initialFrame: AttachmentFrame?
    private let snapAlignEngine = SnapAlignEffectEngine()
    private let microEngine = MicroInteractionEngine()
    private let interactionLayer = CALayer()

    /// Pending thumbnail loads to avoid duplicate dispatches.
    private var pendingLoads: Set<UUID> = []

    // MARK: - Handle Corners

    private enum HandleCorner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
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

        // Interaction overlay for physics effects (shadow / scale)
        microEngine.configureInteractionLayer(interactionLayer)
        layer.addSublayer(interactionLayer)
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let sorted = attachments.sorted(by: { $0.zIndex < $1.zIndex })
        for attachment in sorted {
            drawAttachment(attachment, in: ctx)
        }
    }

    private func drawAttachment(_ attachment: AttachmentObject, in ctx: CGContext) {
        let cardRect = attachment.frame.boundingRect

        // Card background
        let path = UIBezierPath(
            roundedRect: cardRect,
            cornerRadius: AttachmentConstants.cardCornerRadius
        )
        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.clip()

        // Try to draw the thumbnail image
        if let image = store.thumbnail(for: attachment.id, noteID: noteID) {
            // Check if full-res is available and zoom warrants it
            if zoomScale > AttachmentConstants.fullResZoomThreshold,
               let fullRes = store.fullResImage(for: attachment.id) {
                fullRes.draw(in: cardRect)
            } else {
                image.draw(in: cardRect)
            }
        } else {
            // Placeholder: light gray fill with paperclip icon
            ctx.setFillColor(UIColor.systemGray6.cgColor)
            ctx.fill(cardRect)
            drawPlaceholderIcon(in: cardRect, ctx: ctx, type: attachment.type)

            // Trigger async load if not already pending
            if !pendingLoads.contains(attachment.id) && !renderingPaused {
                pendingLoads.insert(attachment.id)
                store.loadThumbnailAsync(for: attachment.id, noteID: noteID) { [weak self] _ in
                    self?.pendingLoads.remove(attachment.id)
                    if self?.renderingPaused == false {
                        self?.setNeedsDisplay()
                    }
                }
            }
        }

        ctx.restoreGState()

        // Card border (subtle)
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.separator.cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Label below the image area (for PDFs / links)
        if !attachment.label.isEmpty {
            drawLabel(attachment.label, below: cardRect, in: ctx)
        }

        // Selection visuals
        if attachment.id == selectedAttachmentID {
            drawSelectionBorder(around: cardRect, in: ctx)
            drawHandles(around: cardRect, in: ctx)
        }
    }

    private func drawPlaceholderIcon(in rect: CGRect, ctx: CGContext, type: AttachmentType) {
        let iconName: String
        switch type {
        case .image: iconName = "photo"
        case .pdf: iconName = "doc.richtext"
        case .link: iconName = "link"
        }
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .light)
        guard let icon = UIImage(systemName: iconName, withConfiguration: config) else { return }
        let iconSize = icon.size
        let iconRect = CGRect(
            x: rect.midX - iconSize.width / 2,
            y: rect.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        ctx.saveGState()
        let tintColor = UIColor.systemGray3
        icon.withTintColor(tintColor).draw(in: iconRect)
        ctx.restoreGState()
    }

    private func drawLabel(_ label: String, below rect: CGRect, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let str = label as NSString
        let textSize = str.size(withAttributes: attrs)
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.maxY + 4,
            width: textSize.width,
            height: textSize.height
        )
        str.draw(in: textRect, withAttributes: attrs)
    }

    private func drawSelectionBorder(around rect: CGRect, in ctx: CGContext) {
        let path = UIBezierPath(
            roundedRect: rect.insetBy(dx: -1, dy: -1),
            cornerRadius: AttachmentConstants.cardCornerRadius + 1
        )
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.tintColor.withAlphaComponent(AttachmentConstants.selectionBorderOpacity).cgColor)
        ctx.setLineWidth(AttachmentConstants.selectionBorderWidth)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawHandles(around rect: CGRect, in ctx: CGContext) {
        let r = AttachmentConstants.handleRadius
        let corners = handlePositions(for: rect)
        for point in corners.values {
            ctx.saveGState()
            ctx.setFillColor(UIColor.tintColor.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: point.x - r, y: point.y - r,
                width: r * 2, height: r * 2
            ))
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(
                x: point.x - r, y: point.y - r,
                width: r * 2, height: r * 2
            ))
            ctx.restoreGState()
        }
    }

    private func handlePositions(for rect: CGRect) -> [HandleCorner: CGPoint] {
        [
            .topLeft: CGPoint(x: rect.minX, y: rect.minY),
            .topRight: CGPoint(x: rect.maxX, y: rect.minY),
            .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY),
            .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    // MARK: - Touch Pass-Through

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled else { return false }
        // When an attachment is selected, always claim touches
        // (allows move/resize + tap-to-deselect)
        if selectedAttachmentID != nil { return true }
        // Otherwise only claim if point hits an attachment
        return attachmentAt(point: point) != nil
    }

    // MARK: - Hit Testing

    /// Finds the topmost attachment (highest zIndex) at the given point.
    private func attachmentAt(point: CGPoint) -> AttachmentObject? {
        attachments
            .sorted(by: { $0.zIndex > $1.zIndex }) // top-first
            .first { $0.frame.boundingRect.contains(point) }
    }

    /// Finds which handle corner is near the point, if any.
    private func handleAt(point: CGPoint, for attachment: AttachmentObject) -> HandleCorner? {
        let tolerance = AttachmentConstants.handleTolerance
        let corners = handlePositions(for: attachment.frame.boundingRect)
        for (corner, pos) in corners {
            let dx = point.x - pos.x
            let dy = point.y - pos.y
            if dx * dx + dy * dy <= tolerance * tolerance {
                return corner
            }
        }
        return nil
    }

    // MARK: - Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let tapped = attachmentAt(point: point) {
            if selectedAttachmentID != nil && selectedAttachmentID != tapped.id {
                microEngine.hideInteractionLayer(interactionLayer)
            }
            selectedAttachmentID = tapped.id
            onSelectionChanged?(tapped.id)

            // Physics: scale up + glow on select
            let rect = tapped.frame.boundingRect
            microEngine.showInteractionLayer(interactionLayer, for: rect)
            microEngine.playSelectScale(on: interactionLayer)
            microEngine.playSelectionGlow(on: interactionLayer)
        } else {
            if selectedAttachmentID != nil {
                microEngine.playDeselectScale(on: interactionLayer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.microEngine.hideInteractionLayer(self?.interactionLayer ?? CALayer())
                }
            }
            selectedAttachmentID = nil
            onSelectionChanged?(nil)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let id = selectedAttachmentID,
              let idx = attachments.firstIndex(where: { $0.id == id }),
              !attachments[idx].isLocked else { return }

        switch gesture.state {
        case .began:
            panStart = gesture.location(in: self)
            initialFrame = attachments[idx].frame
            activeHandle = handleAt(point: panStart, for: attachments[idx])
            snapAlignEngine.prepareHaptics()

            // Physics: soft shadow on drag start
            microEngine.playSoftShadow(on: interactionLayer, dragDirection: .zero)

        case .changed:
            guard let initial = initialFrame else { return }
            let current = gesture.location(in: self)
            let dx = current.x - panStart.x
            let dy = current.y - panStart.y

            if let handle = activeHandle {
                // Resize – proportional, preserving aspect ratio
                let ar = attachments[idx].aspectRatio
                let rect = initial.boundingRect
                var newRect = rect

                switch handle {
                case .bottomRight:
                    newRect.size.width = max(rect.width + dx, AttachmentConstants.minimumDimension)
                    newRect.size.height = newRect.size.width / max(ar, 0.1)
                case .bottomLeft:
                    let newW = max(rect.width - dx, AttachmentConstants.minimumDimension)
                    newRect.origin.x = rect.maxX - newW
                    newRect.size.width = newW
                    newRect.size.height = newW / max(ar, 0.1)
                case .topRight:
                    let newW = max(rect.width + dx, AttachmentConstants.minimumDimension)
                    newRect.size.width = newW
                    let newH = newW / max(ar, 0.1)
                    newRect.origin.y = rect.maxY - newH
                    newRect.size.height = newH
                case .topLeft:
                    let newW = max(rect.width - dx, AttachmentConstants.minimumDimension)
                    newRect.origin.x = rect.maxX - newW
                    newRect.size.width = newW
                    let newH = newW / max(ar, 0.1)
                    newRect.origin.y = rect.maxY - newH
                    newRect.size.height = newH
                }

                attachments[idx].frame.position = CGPoint(
                    x: newRect.midX,
                    y: newRect.midY
                )
                attachments[idx].frame.size = newRect.size
            } else {
                // Move
                var newPos = CGPoint(
                    x: initial.position.x + dx,
                    y: initial.position.y + dy
                )

                // Snap to center guides
                let pageCenter = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
                var snappedX = false
                var snappedY = false
                if abs(newPos.x - pageCenter.x) < AttachmentConstants.snapDistance {
                    newPos.x = pageCenter.x
                    snappedX = true
                }
                if abs(newPos.y - pageCenter.y) < AttachmentConstants.snapDistance {
                    newPos.y = pageCenter.y
                    snappedY = true
                }

                // Snap & align visual/haptic feedback
                snapAlignEngine.playSnapFeedback(
                    on: layer, snappedX: snappedX, snappedY: snappedY
                )

                attachments[idx].frame.position = newPos

                // Physics: update shadow direction + track overlay
                let vel = gesture.velocity(in: self)
                let mag = max(hypot(vel.x, vel.y), 1.0)
                let dir = CGPoint(x: vel.x / mag, y: vel.y / mag)
                microEngine.playSoftShadow(on: interactionLayer, dragDirection: dir)
            }
            setNeedsDisplay()

            // Track overlay position
            let rect = attachments[idx].frame.boundingRect
            microEngine.showInteractionLayer(interactionLayer, for: rect)

        case .ended, .cancelled:
            // Physics: inertia + release bounce
            if activeHandle == nil {
                let vel = gesture.velocity(in: self)
                let decayFactor: CGFloat = 0.12
                let inertiaX = vel.x * decayFactor
                let inertiaY = vel.y * decayFactor
                if abs(inertiaX) > 1 || abs(inertiaY) > 1 {
                    attachments[idx].frame.position.x += inertiaX
                    attachments[idx].frame.position.y += inertiaY
                }
            }
            microEngine.resetSoftShadow(on: interactionLayer)
            microEngine.playReleaseBounce(on: interactionLayer)
            setNeedsDisplay()

            let rect = attachments[idx].frame.boundingRect
            microEngine.showInteractionLayer(interactionLayer, for: rect)

            activeHandle = nil
            initialFrame = nil
            onAttachmentTransformed?(attachments[idx])

        default:
            break
        }
    }

    // MARK: - Zoom Handling

    private func handleZoomScaleChange() {
        guard !renderingPaused else { return }

        if zoomScale > AttachmentConstants.fullResZoomThreshold {
            // Load full-res for visible attachments
            for attachment in attachments where attachment.type != .link {
                if store.fullResImage(for: attachment.id) == nil {
                    store.loadFullResAsync(
                        for: attachment.id,
                        noteID: noteID,
                        ext: attachment.fileExtension
                    ) { [weak self] _ in
                        self?.setNeedsDisplay()
                    }
                }
            }
        } else if zoomScale < AttachmentConstants.fullResEvictionZoom {
            // Evict full-res to save memory
            store.evictFullResCache()
            setNeedsDisplay()
        }
    }

    // MARK: - Page Updates

    /// Called on page change — clears full-res cache and triggers thumbnail loads.
    func updateAttachments(for pageAttachments: [AttachmentObject], noteID: UUID) {
        self.noteID = noteID
        self.attachments = pageAttachments
        store.evictFullResCache()
        pendingLoads.removeAll()
        setNeedsDisplay()
    }
}
