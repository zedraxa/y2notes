import UIKit
import os

private let canvasLogger = Logger(subsystem: "com.y2notes", category: "WidgetCanvas")

// MARK: - StickyNoteColor UIKit mapping

private extension StickyNoteColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor(red: 1.00, green: 0.96, blue: 0.60, alpha: 1)
        case .pink:   return UIColor(red: 1.00, green: 0.80, blue: 0.85, alpha: 1)
        case .blue:   return UIColor(red: 0.75, green: 0.88, blue: 1.00, alpha: 1)
        case .green:  return UIColor(red: 0.78, green: 0.95, blue: 0.78, alpha: 1)
        case .purple: return UIColor(red: 0.88, green: 0.78, blue: 0.98, alpha: 1)
        }
    }
}

/// A UIView overlay that renders widget cards using Core Graphics and handles
/// finger-based hit-test, selection, move, and resize gestures.
final class WidgetCanvasView: UIView, EffectIntensityReceiver {

    // MARK: - Public State

    var widgets: [NoteWidget] = [] {
        didSet {
            if !renderingPaused { setNeedsDisplay() }
            detectCompletionTransitions()
        }
    }
    var selectedWidgetID: UUID? { didSet { setNeedsDisplay() } }
    var renderingPaused: Bool = false

    // MARK: - Callbacks

    var onSelectionChanged: ((UUID?) -> Void)?
    var onWidgetTransformed: ((NoteWidget) -> Void)?
    var onWidgetsChanged: (([NoteWidget]) -> Void)?

    /// Fired when a checklist widget transitions to all-items-checked.
    /// Parameters: (widget ID, widget centre point in canvas coordinates).
    var onChecklistCompleted: ((UUID, CGPoint) -> Void)?
    /// Fired when a progress-tracker widget reaches its goal (current ≥ total).
    /// Parameters: (widget ID, widget centre point in canvas coordinates).
    var onTimerCompleted: ((UUID, CGPoint) -> Void)?

    /// Tracks which checklist widgets were already complete on the last
    /// update, so we only fire the callback on the *transition* to complete.
    private var previouslyCompletedChecklists: Set<UUID> = []
    /// Same for progress trackers.
    private var previouslyCompletedTrackers: Set<UUID> = []

    // MARK: - Private State

    private var activeHandle: HandleCorner?
    private var panStart: CGPoint = .zero
    private var initialFrame: WidgetFrame?
    private let snapAlignEngine = SnapAlignEffectEngine()
    private let microEngine = MicroInteractionEngine()
    private let interactionLayer = CALayer()

    /// Current adaptive effect intensity.  Set by the editor coordinator.
    var effectIntensity: EffectIntensity = .full {
        didSet {
            microEngine.effectIntensity = effectIntensity
            snapAlignEngine.effectIntensity = effectIntensity
        }
    }

    private enum HandleCorner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    // MARK: - Init

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
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
        let sorted = widgets.sorted(by: { $0.zIndex < $1.zIndex })
        for widget in sorted { drawWidget(widget, in: ctx) }
    }

    private func drawWidget(_ widget: NoteWidget, in ctx: CGContext) {
        let cardRect = widget.frame.boundingRect
        let bgColor: UIColor
        if case .stickyNote(_, let color) = widget.payload {
            bgColor = color.uiColor.withAlphaComponent(0.92)
        } else if widget.kind == .referenceCard {
            bgColor = UIColor.systemGray6.withAlphaComponent(0.9)
        } else {
            bgColor = UIColor.systemBackground.withAlphaComponent(0.85)
        }
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: WidgetConstants.cardCornerRadius)

        // Card fill
        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Subtle border
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.separator.withAlphaComponent(WidgetConstants.borderOpacity).cgColor)
        ctx.setLineWidth(WidgetConstants.borderWidth)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Clip body content to card bounds
        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.clip()
        switch widget.payload {
        case .checklist(let title, let items):
            drawChecklist(title: title, items: items, in: cardRect, ctx: ctx)
        case .quickTable(let title, let columns, let rows, let cells):
            drawQuickTable(title: title, columns: columns, rows: rows, cells: cells, in: cardRect, ctx: ctx)
        case .calloutBox(let title, let body, let style):
            drawCalloutBox(title: title, body: body, style: style, in: cardRect, ctx: ctx)
        case .referenceCard(let title, let body):
            drawReferenceCard(title: title, body: body, in: cardRect, ctx: ctx)
        case .stickyNote(let body, _):
            drawStickyNote(body: body, in: cardRect, ctx: ctx)
        case .flashcard(let front, let back, let isFlipped):
            drawFlashcard(front: front, back: back, isFlipped: isFlipped,
                          isSelected: widget.id == selectedWidgetID, in: cardRect, ctx: ctx)
        case .progressTracker(let title, let current, let total):
            drawProgressTracker(title: title, current: current, total: total, in: cardRect, ctx: ctx)
        }
        ctx.restoreGState()

        // Anchor-pin indicator for locked widgets
        if widget.isLocked {
            drawAnchorPin(at: CGPoint(x: cardRect.maxX - 10, y: cardRect.minY + 10), in: ctx)
        }

        if widget.id == selectedWidgetID {
            drawSelectionBorder(around: cardRect, in: ctx)
            drawHandles(around: cardRect, in: ctx)
        }
    }

    // MARK: - Widget Body Drawing

    private func drawChecklist(title: String, items: [ChecklistItem], in rect: CGRect, ctx: CGContext) {
        let pad = WidgetConstants.containerPadding
        var y = rect.minY + pad
        if !title.isEmpty {
            y = drawTitle(title, x: rect.minX + pad, y: y, width: rect.width - pad * 2, ctx: ctx)
        }
        let cbSize = WidgetConstants.checkboxSize
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: WidgetConstants.bodyFontSize),
            .foregroundColor: UIColor.label
        ]
        for item in items {
            guard y + cbSize <= rect.maxY - pad else { break }
            let cbRect = CGRect(x: rect.minX + pad, y: y, width: cbSize, height: cbSize).insetBy(dx: 2, dy: 2)
            if item.isChecked {
                ctx.setFillColor(UIColor.tintColor.cgColor)
                ctx.fill(cbRect)
            } else {
                ctx.setStrokeColor(UIColor.secondaryLabel.cgColor)
                ctx.setLineWidth(1.5)
                ctx.stroke(cbRect)
            }
            let textX = rect.minX + pad + cbSize + 6
            (item.text as NSString).draw(
                in: CGRect(x: textX, y: y, width: rect.maxX - textX - pad, height: cbSize),
                withAttributes: textAttrs
            )
            y += cbSize + 4
        }
    }

    private func drawQuickTable(title: String, columns: Int, rows: Int, cells: [TableCell],
                                in rect: CGRect, ctx: CGContext) {
        let pad = WidgetConstants.containerPadding
        var y = rect.minY + pad
        if !title.isEmpty {
            y = drawTitle(title, x: rect.minX + pad, y: y, width: rect.width - pad * 2, ctx: ctx)
        }
        guard columns > 0, rows > 0 else { return }
        let tableW = rect.width - pad * 2
        let tableH = rect.maxY - y - pad
        let colW = tableW / CGFloat(columns)
        let rowH = tableH / CGFloat(rows)
        let tableX = rect.minX + pad

        // Grid lines
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.separator.cgColor)
        ctx.setLineWidth(0.5)
        for r in 0...rows {
            let ly = y + CGFloat(r) * rowH
            ctx.move(to: CGPoint(x: tableX, y: ly))
            ctx.addLine(to: CGPoint(x: tableX + tableW, y: ly))
        }
        for c in 0...columns {
            let lx = tableX + CGFloat(c) * colW
            ctx.move(to: CGPoint(x: lx, y: y))
            ctx.addLine(to: CGPoint(x: lx, y: y + tableH))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Cell text (centred)
        let cellAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: WidgetConstants.bodyFontSize),
            .foregroundColor: UIColor.label
        ]
        let cp = WidgetConstants.cellPadding
        for r in 0..<rows {
            for c in 0..<columns {
                let idx = r * columns + c
                guard idx < cells.count, !cells[idx].text.isEmpty else { continue }
                let text = cells[idx].text
                let cellRect = CGRect(x: tableX + CGFloat(c) * colW + cp,
                                      y: y + CGFloat(r) * rowH + cp,
                                      width: colW - cp * 2, height: rowH - cp * 2)
                let sz = (text as NSString).size(withAttributes: cellAttrs)
                (text as NSString).draw(
                    in: CGRect(x: cellRect.midX - sz.width / 2, y: cellRect.midY - sz.height / 2,
                               width: sz.width, height: sz.height),
                    withAttributes: cellAttrs
                )
            }
        }
    }

    private func drawCalloutBox(title: String, body: String, style: CalloutStyle,
                                in rect: CGRect, ctx: CGContext) {
        let pad = WidgetConstants.containerPadding
        let accentColor: UIColor
        switch style {
        case .note:      accentColor = UIColor.systemBlue.withAlphaComponent(0.5)
        case .important: accentColor = UIColor.systemOrange.withAlphaComponent(0.5)
        case .tip:       accentColor = UIColor.systemGreen.withAlphaComponent(0.5)
        case .warning:   accentColor = UIColor.systemRed.withAlphaComponent(0.5)
        }
        ctx.setFillColor(accentColor.cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: 4, height: rect.height))

        let contentX = rect.minX + 4 + pad
        let contentW = rect.width - 4 - pad * 2
        var y = rect.minY + pad
        if !title.isEmpty { y = drawTitle(title, x: contentX, y: y, width: contentW, ctx: ctx) }
        if !body.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: WidgetConstants.bodyFontSize),
                .foregroundColor: UIColor.label
            ]
            (body as NSString).draw(
                in: CGRect(x: contentX, y: y, width: contentW, height: rect.maxY - y - pad),
                withAttributes: attrs
            )
        }
    }

    private func drawReferenceCard(title: String, body: String, in rect: CGRect, ctx: CGContext) {
        let pad = WidgetConstants.containerPadding
        var y = rect.minY + pad
        if !title.isEmpty { y = drawTitle(title, x: rect.minX + pad, y: y, width: rect.width - pad * 2, ctx: ctx) }
        if !body.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: WidgetConstants.bodyFontSize),
                .foregroundColor: UIColor.label
            ]
            (body as NSString).draw(
                in: CGRect(x: rect.minX + pad, y: y, width: rect.width - pad * 2, height: rect.maxY - y - pad),
                withAttributes: attrs
            )
        }
    }

    private func drawStickyNote(body: String, in rect: CGRect, ctx: CGContext) {
        let pad = WidgetConstants.containerPadding
        // Folded corner indicator (bottom-right triangle)
        let foldSize: CGFloat = 16
        let foldPath = UIBezierPath()
        foldPath.move(to: CGPoint(x: rect.maxX - foldSize, y: rect.maxY))
        foldPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - foldSize))
        foldPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        foldPath.close()
        ctx.saveGState()
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.12).cgColor)
        ctx.addPath(foldPath.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        if !body.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: WidgetConstants.bodyFontSize),
                .foregroundColor: UIColor.label
            ]
            (body as NSString).draw(
                in: CGRect(
                    x: rect.minX + pad,
                    y: rect.minY + pad,
                    width: rect.width - pad * 2,
                    height: rect.height - pad * 2 - foldSize
                ),
                withAttributes: attrs
            )
        }
    }

    private func drawFlashcard(front: String, back: String, isFlipped: Bool,
                               isSelected: Bool, in rect: CGRect, ctx: CGContext) {
        let pad = WidgetConstants.containerPadding
        let labelText = isFlipped ? "BACK" : "FRONT"
        let contentText = isFlipped ? back : front

        // Side label badge (top-right)
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let badgeSize = (labelText as NSString).size(withAttributes: badgeAttrs)
        (labelText as NSString).draw(
            at: CGPoint(
                x: rect.maxX - badgeSize.width - pad,
                y: rect.minY + pad
            ),
            withAttributes: badgeAttrs
        )

        // Divider line below badge row
        let dividerY = rect.minY + pad + badgeSize.height + 4
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.separator.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: rect.minX + pad, y: dividerY))
        ctx.addLine(to: CGPoint(x: rect.maxX - pad, y: dividerY))
        ctx.strokePath()
        ctx.restoreGState()

        // Content text
        let contentAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: WidgetConstants.bodyFontSize),
            .foregroundColor: UIColor.label
        ]
        let contentY = dividerY + 6
        if !contentText.isEmpty {
            (contentText as NSString).draw(
                in: CGRect(
                    x: rect.minX + pad,
                    y: contentY,
                    width: rect.width - pad * 2,
                    height: rect.maxY - contentY - pad
                ),
                withAttributes: contentAttrs
            )
        }

        // Flip hint (bottom-centre) when this flashcard is selected
        if isSelected {
            let hintText = "Double-tap to flip"
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            let hintSize = (hintText as NSString).size(withAttributes: hintAttrs)
            (hintText as NSString).draw(
                at: CGPoint(
                    x: rect.midX - hintSize.width / 2,
                    y: rect.maxY - pad - hintSize.height
                ),
                withAttributes: hintAttrs
            )
        }
    }

    private func drawProgressTracker(title: String, current: Int, total: Int,
                                     in rect: CGRect, ctx: CGContext) {
        let pad = WidgetConstants.containerPadding
        var y = rect.minY + pad
        if !title.isEmpty {
            y = drawTitle(title, x: rect.minX + pad, y: y, width: rect.width - pad * 2, ctx: ctx)
        }

        // Progress bar track
        let barHeight: CGFloat = 14
        let barX = rect.minX + pad
        let barW = rect.width - pad * 2
        let barRect = CGRect(x: barX, y: y, width: barW, height: barHeight)
        let barPath = UIBezierPath(roundedRect: barRect, cornerRadius: barHeight / 2)

        ctx.saveGState()
        ctx.setFillColor(UIColor.systemFill.cgColor)
        ctx.addPath(barPath.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Progress fill
        let clampedTotal = max(total, 1)
        let fraction = min(CGFloat(current) / CGFloat(clampedTotal), 1.0)
        if fraction > 0 {
            let fillW = max(barW * fraction, barHeight)
            let fillRect = CGRect(x: barX, y: y, width: fillW, height: barHeight)
            let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: barHeight / 2)
            ctx.saveGState()
            ctx.setFillColor(UIColor.tintColor.withAlphaComponent(0.8).cgColor)
            ctx.addPath(fillPath.cgPath)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Percentage label
        let pct = Int(fraction * 100)
        let pctText = "\(current)/\(total)  (\(pct)%)"
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.secondaryLabel
        ]
        (pctText as NSString).draw(
            at: CGPoint(x: barX, y: y + barHeight + 4),
            withAttributes: pctAttrs
        )
    }

    /// Draws a small anchor-pin circle to indicate the widget is locked to the paper.
    private func drawAnchorPin(at centre: CGPoint, in ctx: CGContext) {
        let r: CGFloat = 5
        let pinRect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.setFillColor(UIColor.systemRed.withAlphaComponent(0.75).cgColor)
        ctx.fillEllipse(in: pinRect)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: pinRect)
        // Centre dot
        let dotR: CGFloat = 1.5
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: centre.x - dotR, y: centre.y - dotR,
            width: dotR * 2, height: dotR * 2
        ))
        ctx.restoreGState()
    }

    /// Draws a bold title and returns the Y position after the title.
    @discardableResult
    private func drawTitle(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, ctx: CGContext) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: WidgetConstants.titleFontSize, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (title as NSString).draw(
            in: CGRect(x: x, y: y, width: width, height: WidgetConstants.titleFontSize + 4),
            withAttributes: attrs
        )
        return y + WidgetConstants.titleFontSize + 8
    }

    // MARK: - Selection Drawing

    private func drawSelectionBorder(around rect: CGRect, in ctx: CGContext) {
        let path = UIBezierPath(
            roundedRect: rect.insetBy(dx: -1, dy: -1),
            cornerRadius: WidgetConstants.cardCornerRadius + 1
        )
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.tintColor.withAlphaComponent(WidgetConstants.selectionBorderOpacity).cgColor)
        ctx.setLineWidth(WidgetConstants.selectionBorderWidth)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawHandles(around rect: CGRect, in ctx: CGContext) {
        let r = WidgetConstants.handleRadius
        for point in handlePositions(for: rect).values {
            ctx.saveGState()
            ctx.setFillColor(UIColor.tintColor.cgColor)
            let handleRect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
            ctx.fillEllipse(in: handleRect)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: handleRect)
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
        if selectedWidgetID != nil { return true }
        return widgetAt(point: point) != nil
    }

    // MARK: - Hit Testing

    private func widgetAt(point: CGPoint) -> NoteWidget? {
        widgets
            .sorted(by: { $0.zIndex > $1.zIndex })
            .first { $0.frame.boundingRect.contains(point) }
    }

    private func handleAt(point: CGPoint, for widget: NoteWidget) -> HandleCorner? {
        let tolerance = WidgetConstants.handleTolerance
        let corners = handlePositions(for: widget.frame.boundingRect)
        for (corner, pos) in corners {
            let dx = point.x - pos.x
            let dy = point.y - pos.y
            if dx * dx + dy * dy <= tolerance * tolerance { return corner }
        }
        return nil
    }

    // MARK: - Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let tapped = widgetAt(point: point) {
            if selectedWidgetID != nil && selectedWidgetID != tapped.id {
                microEngine.hideInteractionLayer(interactionLayer)
            }
            selectedWidgetID = tapped.id
            onSelectionChanged?(tapped.id)

            // Physics: scale up + glow on select
            let rect = tapped.frame.boundingRect
            microEngine.showInteractionLayer(interactionLayer, for: rect)
            microEngine.playSelectScale(on: interactionLayer)
            microEngine.playSelectionGlow(on: interactionLayer)
        } else {
            if selectedWidgetID != nil {
                microEngine.playDeselectScale(on: interactionLayer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.microEngine.hideInteractionLayer(self?.interactionLayer ?? CALayer())
                }
            }
            selectedWidgetID = nil
            onSelectionChanged?(nil)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard let tapped = widgetAt(point: point),
              tapped.id == selectedWidgetID,
              let idx = widgets.firstIndex(where: { $0.id == tapped.id }),
              case .flashcard(let front, let back, let isFlipped) = tapped.payload else { return }
        widgets[idx].payload = .flashcard(front: front, back: back, isFlipped: !isFlipped)
        setNeedsDisplay()
        onWidgetsChanged?(widgets)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let id = selectedWidgetID,
              let idx = widgets.firstIndex(where: { $0.id == id }),
              !widgets[idx].isLocked else { return }

        switch gesture.state {
        case .began:
            panStart = gesture.location(in: self)
            initialFrame = widgets[idx].frame
            activeHandle = handleAt(point: panStart, for: widgets[idx])
            snapAlignEngine.prepareHaptics()

            // Physics: soft shadow on drag start
            microEngine.playSoftShadow(on: interactionLayer, dragDirection: .zero)

        case .changed:
            guard let initial = initialFrame else { return }
            let current = gesture.location(in: self)
            let dx = current.x - panStart.x
            let dy = current.y - panStart.y

            if let handle = activeHandle {
                let rect = initial.boundingRect
                var newRect = rect
                switch handle {
                case .bottomRight:
                    newRect.size.width = max(rect.width + dx, WidgetConstants.minimumWidth)
                    newRect.size.height = max(rect.height + dy, WidgetConstants.minimumHeight)
                case .bottomLeft:
                    let newW = max(rect.width - dx, WidgetConstants.minimumWidth)
                    newRect.origin.x = rect.maxX - newW
                    newRect.size.width = newW
                    newRect.size.height = max(rect.height + dy, WidgetConstants.minimumHeight)
                case .topRight:
                    newRect.size.width = max(rect.width + dx, WidgetConstants.minimumWidth)
                    let newH = max(rect.height - dy, WidgetConstants.minimumHeight)
                    newRect.origin.y = rect.maxY - newH
                    newRect.size.height = newH
                case .topLeft:
                    let newW = max(rect.width - dx, WidgetConstants.minimumWidth)
                    newRect.origin.x = rect.maxX - newW
                    newRect.size.width = newW
                    let newH = max(rect.height - dy, WidgetConstants.minimumHeight)
                    newRect.origin.y = rect.maxY - newH
                    newRect.size.height = newH
                }
                widgets[idx].frame.position = CGPoint(x: newRect.midX, y: newRect.midY)
                widgets[idx].frame.size = newRect.size
            } else {
                var newPos = CGPoint(x: initial.position.x + dx, y: initial.position.y + dy)

                // Snap guides: page center + left/right/top margins anchored to page bounds
                let snapDist = WidgetConstants.snapDistance
                let w = bounds.width
                let h = bounds.height
                let xGuides: [CGFloat] = [
                    w / 2,
                    w * WidgetConstants.leftMarginFraction,
                    w * WidgetConstants.rightMarginFraction
                ]
                let yGuides: [CGFloat] = [
                    h / 2,
                    h * WidgetConstants.topMarginFraction
                ]

                var snappedX = false
                var snappedY = false
                for guide in xGuides {
                    if abs(newPos.x - guide) < snapDist { newPos.x = guide; snappedX = true; break }
                }
                for guide in yGuides {
                    if abs(newPos.y - guide) < snapDist { newPos.y = guide; snappedY = true; break }
                }

                // Snap & align visual/haptic feedback
                snapAlignEngine.playSnapFeedback(
                    on: layer, snappedX: snappedX, snappedY: snappedY
                )
                widgets[idx].frame.position = newPos

                // Physics: update shadow direction
                let vel = gesture.velocity(in: self)
                let mag = max(hypot(vel.x, vel.y), 1.0)
                let dir = CGPoint(x: vel.x / mag, y: vel.y / mag)
                microEngine.playSoftShadow(on: interactionLayer, dragDirection: dir)
            }
            setNeedsDisplay()

            // Track overlay position
            let rect = widgets[idx].frame.boundingRect
            microEngine.showInteractionLayer(interactionLayer, for: rect)

        case .ended, .cancelled:
            // Physics: inertia + release bounce
            if activeHandle == nil {
                let vel = gesture.velocity(in: self)
                let decayFactor: CGFloat = 0.12
                let inertiaX = vel.x * decayFactor
                let inertiaY = vel.y * decayFactor
                if abs(inertiaX) > 1 || abs(inertiaY) > 1 {
                    widgets[idx].frame.position.x += inertiaX
                    widgets[idx].frame.position.y += inertiaY
                }
            }
            microEngine.resetSoftShadow(on: interactionLayer)
            microEngine.playReleaseBounce(on: interactionLayer)
            setNeedsDisplay()

            let rect = widgets[idx].frame.boundingRect
            microEngine.showInteractionLayer(interactionLayer, for: rect)

            activeHandle = nil
            initialFrame = nil
            onWidgetTransformed?(widgets[idx])

        default:
            break
        }
    }

    // MARK: - Page Updates

    func updateWidgets(for pageWidgets: [NoteWidget]) {
        self.widgets = pageWidgets
        setNeedsDisplay()
    }

    // MARK: - Completion Detection

    /// Detects checklist/progress-tracker completion transitions and fires
    /// the appropriate callbacks.  Only fires on the *first* observation of
    /// a widget becoming complete (not on every update while it stays complete).
    private func detectCompletionTransitions() {
        var nowCompleteChecklists = Set<UUID>()
        var nowCompleteTrackers = Set<UUID>()

        for widget in widgets {
            let center = widget.frame.position

            switch widget.payload {
            case .checklist(_, let items):
                if !items.isEmpty && items.allSatisfy({ $0.isChecked }) {
                    nowCompleteChecklists.insert(widget.id)
                    if !previouslyCompletedChecklists.contains(widget.id) {
                        onChecklistCompleted?(widget.id, center)
                    }
                }
            case .progressTracker(_, let current, let total):
                if total > 0 && current >= total {
                    nowCompleteTrackers.insert(widget.id)
                    if !previouslyCompletedTrackers.contains(widget.id) {
                        onTimerCompleted?(widget.id, center)
                    }
                }
            default:
                break
            }
        }

        previouslyCompletedChecklists = nowCompleteChecklists
        previouslyCompletedTrackers = nowCompleteTrackers
    }
}
