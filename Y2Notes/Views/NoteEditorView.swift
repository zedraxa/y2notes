import SwiftUI
import PencilKit
import OSLog

// MARK: - Performance instrumentation

/// Human-readable editor lifecycle messages — visible in Console.app.
private let editorLogger = Logger(subsystem: "com.y2notes.app", category: "editor")

/// Instruments-visible signposts for canvas setup, drawing changes, and save flushes.
private let editorSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "editor.perf")

// MARK: - NoteEditorView

/// Full-screen note editor: editable title + drawing toolbar + PencilKit canvas.
struct NoteEditorView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var toolStore: DrawingToolStore
    @Environment(\.undoManager) private var undoManager
    let note: Note

    @State private var titleText: String
    @State private var canUndo = false
    @State private var canRedo = false
    /// Controls the transient "saved" checkmark badge (hidden 2 s after saved).
    @State private var showSavedBadge = false
    /// Timestamp of the most recent "saved" event — used to debounce the auto-hide timer.
    @State private var badgeShownAt: Date?

    /// When true only Apple Pencil input draws; finger touches pan/zoom the canvas.
    /// When false any touch input draws. Persisted across sessions via AppStorage.
    @AppStorage("y2notes.pencilOnlyDrawing") private var pencilOnlyDrawing = false

    /// Toggling this value signals the canvas to animate back to 1× zoom.
    @State private var zoomResetTrigger = false

    init(note: Note) {
        self.note = note
        _titleText = State(initialValue: note.title)
    }

    // MARK: - Effective theme

    private var effectiveTheme: AppTheme {
        note.themeOverride ?? themeStore.selectedTheme
    }

    private var effectiveDefinition: ThemeDefinition {
        effectiveTheme.definition
    }

    var body: some View {
        VStack(spacing: 0) {
            titleField
            if effectiveDefinition.canvasIsDark {
                contrastBanner
            }
            Divider()
            DrawingToolbarView(toolStore: toolStore)
            CanvasView(
                noteID: note.id,
                drawingData: note.drawingData,
                backgroundColor: effectiveDefinition.canvasBackground,
                defaultInkColor: effectiveDefinition.contrastingInkColor,
                currentTool: toolStore.pkTool,
                isShapeToolActive: toolStore.activeTool == .shape,
                activeShapeType: toolStore.activeShapeType,
                shapeColor: toolStore.activeColor,
                shapeWidth: toolStore.activeWidth,
                drawingPolicy: pencilOnlyDrawing ? .pencilOnly : .anyInput,
                zoomResetTrigger: zoomResetTrigger,
                onDrawingChanged: { data in
                    noteStore.updateDrawing(for: note.id, data: data)
                },
                onSaveRequested: {
                    noteStore.save()
                },
                onUndoStateChanged: { canUndoVal, canRedoVal in
                    canUndo = canUndoVal
                    canRedo = canRedoVal
                }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                saveStateIndicator
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                noteThemeMenu

                // Finger / Pencil drawing policy toggle.
                // When pencil-only mode is active the icon is a filled pencil tip;
                // tapping it re-enables finger drawing (shows hand+pencil icon).
                Button {
                    pencilOnlyDrawing.toggle()
                } label: {
                    Image(systemName: pencilOnlyDrawing ? "pencil.tip" : "hand.and.pencil")
                }
                // Labels describe the *action* the button performs, not the current state.
                .accessibilityLabel(
                    pencilOnlyDrawing ? "Enable finger drawing" : "Enable Pencil-only drawing"
                )

                // Zoom reset — animates the canvas back to 1× scale.
                Button {
                    zoomResetTrigger.toggle()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Reset zoom to 100%")

                Button {
                    undoManager?.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .accessibilityLabel("Undo")

                Button {
                    undoManager?.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
                .accessibilityLabel("Redo")
            }
        }
        .onAppear {
            refreshUndoRedoState()
        }
        // Notification-based fallback to keep undo/redo state in sync even when the
        // canvas delegate fires before the onUndoStateChanged callback is invoked.
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in
            refreshUndoRedoState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in
            refreshUndoRedoState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in
            refreshUndoRedoState()
        }
        .onReceive(noteStore.$saveState) { state in
            if state == .saved {
                showSavedBadge = true
                let now = Date()
                badgeShownAt = now
                // Each rapid save updates `badgeShownAt`; only the last scheduled
                // callback will actually hide the badge, avoiding premature dismissal.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if badgeShownAt == now {
                        showSavedBadge = false
                    }
                }
            }
        }
        .onDisappear {
            noteStore.save()
        }
    }

    // MARK: - Per-note theme menu

    private var noteThemeMenu: some View {
        Menu {
            Button {
                noteStore.updateThemeOverride(for: note.id, theme: nil)
            } label: {
                if note.themeOverride == nil {
                    Label("App Theme", systemImage: "checkmark")
                } else {
                    Text("App Theme")
                }
            }
            Divider()
            ForEach(AppTheme.allCases) { theme in
                Button {
                    noteStore.updateThemeOverride(for: note.id, theme: theme)
                } label: {
                    if note.themeOverride == theme {
                        Label(theme.displayName, systemImage: "checkmark")
                    } else {
                        Label(theme.displayName, systemImage: theme.systemImage)
                    }
                }
                .disabled(theme.isPremium)
            }
        } label: {
            Image(systemName: note.themeOverride == nil ? "paintbrush" : "paintbrush.fill")
                .accessibilityLabel("Note theme")
        }
    }

    // MARK: - Contrast banner

    private var contrastBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.fill")
                .font(.caption2)
            Text("Dark canvas — use a light ink colour for best contrast")
                .font(.caption2)
        }
        .foregroundStyle(Color(uiColor: effectiveDefinition.secondaryText))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: effectiveDefinition.canvasBackground).opacity(0.8))
    }

    // MARK: - Helpers

    /// Compact toolbar indicator that reflects the current disk-write state.
    /// - Spinning icon while saving (transitions quickly; mostly visible on slow storage).
    /// - Checkmark shown for 2 s after a successful save.
    /// - Warning triangle shown (persistently) when a save error has occurred.
    @ViewBuilder
    private var saveStateIndicator: some View {
        switch noteStore.saveState {
        case .saving:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityLabel("Saving")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .accessibilityLabel("Save error")
        case .saved where showSavedBadge:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityLabel("Saved")
        default:
            EmptyView()
        }
    }

    private func refreshUndoRedoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    private var titleField: some View {
        TextField("Note title", text: $titleText)
            .font(.title2.bold())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onChange(of: titleText) { newValue in
                noteStore.updateTitle(for: note.id, title: newValue)
            }
    }
}

// MARK: - PencilKit canvas bridge

/// UIViewRepresentable that wraps a PKCanvasView inside a plain UIView container.
/// The container also hosts a ShapeOverlayView that intercepts gestures when the
/// shape tool is active so shapes can be committed as PKStrokes.
///
/// Features
/// - Tool driven by `DrawingToolStore` via `currentTool` (no floating PKToolPicker).
/// - Finger vs Pencil drawing policy: controlled by `drawingPolicy`.
/// - Zoom/pan: pinch-to-zoom from 0.25× to 5×; zoom-reset via `zoomResetTrigger`.
/// - Shape overlay: dashed preview + PKStroke commit when shape tool is active.
/// - Performance: `OSSignposter` intervals for canvas setup; events for drawing changes
///   and save flushes — all visible in Instruments → os_signpost.
/// - Undo/redo state: reports (canUndo, canRedo) from the canvas's own undo manager
///   after every drawing change via `onUndoStateChanged`.
///
/// **Apple Pencil features (all degrade gracefully)**
/// - Double-tap (Pencil 2nd gen+, iOS 12.1+): dispatches the user's preferred action.
/// - Squeeze (Pencil Pro, iOS 17.5+): dispatches the user's preferred squeeze action.
/// - Ghost nib / hover preview (M2+ iPad Pro, iOS 16.1+): draws an overlay cursor.
/// - Barrel-roll fountain pen (Pencil Pro, iOS 17.5+): modulates fountain-pen width.
/// - Contextual palette: compact floating palette anchored near the Pencil tip.

private struct CanvasView: UIViewRepresentable {
    let noteID: UUID
    let drawingData: Data
    let backgroundColor: UIColor
    let defaultInkColor: UIColor
    let currentTool: PKTool
    let isShapeToolActive: Bool
    let activeShapeType: ShapeType
    let shapeColor: UIColor
    let shapeWidth: Double
    /// Controls whether finger touches draw or pan/zoom the canvas.
    let drawingPolicy: PKCanvasViewDrawingPolicy
    /// Flip this value to trigger an animated reset to 1× zoom scale.
    let zoomResetTrigger: Bool
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void
    /// Called after each stroke with updated (canUndo, canRedo) from the canvas undo manager.
    let onUndoStateChanged: ((Bool, Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
    }

    func makeUIView(context: Context) -> UIView {
        let setupState = editorSignposter.beginInterval("CanvasSetup")
        editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - begin")

        let container = UIView()
        container.backgroundColor = backgroundColor
        container.clipsToBounds = true

        // ── PencilKit canvas ─────────────────────────────────────────────────
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = drawingPolicy
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = backgroundColor
        canvas.tool = currentTool

        // Zoom/pan: PKCanvasView inherits UIScrollView zoom support.
        // 0.25× minimum lets users step back for a full-page view.
        // 5×   maximum provides fine-detail writing precision.
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.bouncesZoom = true

        // Restore previously saved drawing, if any.
        if !drawingData.isEmpty, let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }

        container.addSubview(canvas)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.canvas = canvas
        canvas.isUserInteractionEnabled = !isShapeToolActive

        // ── Shape overlay ────────────────────────────────────────────────────
        let overlay = ShapeOverlayView(
            shapeType: activeShapeType,
            strokeColor: shapeColor,
            strokeWidth: CGFloat(shapeWidth)
        ) { stroke in
            // PKDrawing.strokes is a read-only sequence; appending requires building
            // a new PKDrawing from the full stroke list — this is the standard
            // PencilKit pattern since PKDrawing is an immutable value type.
            canvas.drawing = PKDrawing(strokes: Array(canvas.drawing.strokes) + [stroke])
        }
        overlay.isHidden = !isShapeToolActive

        container.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.shapeOverlay = overlay

        // ── Hover overlay (non-interactive, floats above the canvas) ─────────
        let hoverOverlay = PencilHoverOverlayView(frame: .zero)
        hoverOverlay.translatesAutoresizingMaskIntoConstraints = false
        hoverOverlay.isUserInteractionEnabled = false
        canvas.addSubview(hoverOverlay)
        NSLayoutConstraint.activate([
            hoverOverlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: canvas.topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        context.coordinator.hoverOverlay = hoverOverlay

        // ── Apple Pencil interaction coordinator ─────────────────────────────
        let pencilCoordinator = PencilInteractionCoordinator()
        pencilCoordinator.delegate = context.coordinator
        pencilCoordinator.attach(to: canvas)
        context.coordinator.pencilCoordinator = pencilCoordinator
        context.coordinator.canvasRef = canvas

        // Seed coordinator state so the first updateUIView call does not misfire.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder so Apple Pencil is ready immediately.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            editorSignposter.endInterval("CanvasSetup", setupState)
            editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - complete")
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        // Sync background colour when the theme changes.
        if canvas.backgroundColor != backgroundColor {
            canvas.backgroundColor = backgroundColor
            uiView.backgroundColor = backgroundColor
        }

        // Sync drawing policy when the user toggles the finger/pencil preference.
        if canvas.drawingPolicy != drawingPolicy {
            canvas.drawingPolicy = drawingPolicy
        }

        // Update the active tool from DrawingToolStore.
        canvas.tool = currentTool
        canvas.isUserInteractionEnabled = !isShapeToolActive

        // Sync shape overlay properties.
        if let overlay = context.coordinator.shapeOverlay {
            overlay.isHidden    = !isShapeToolActive
            overlay.shapeType   = activeShapeType
            overlay.strokeColor = shapeColor
            overlay.strokeWidth = CGFloat(shapeWidth)
        }

        // Zoom reset: animate to 1× when the trigger value flips.
        if context.coordinator.lastZoomResetTrigger != zoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            // Dispatch to avoid mutating scroll state mid-layout-pass.
            DispatchQueue.main.async {
                canvas.setZoomScale(1.0, animated: true)
                editorLogger.debug("[\(noteID, privacy: .public)] zoom reset to 1×")
            }
        }

        // Keep the undo state callback current (closures capture SwiftUI state by value).
        context.coordinator.onUndoStateChanged = onUndoStateChanged
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (Data) -> Void
        let onSaveRequested: () -> Void
        weak var canvas: PKCanvasView?
        weak var shapeOverlay: ShapeOverlayView?
        /// Updated by updateUIView to always hold the freshest closure.
        var onUndoStateChanged: ((Bool, Bool) -> Void)?
        /// Tracks the last zoom-reset trigger seen so we only react to flips.
        var lastZoomResetTrigger: Bool = false
        private var debounceTimer: Timer?

        // Apple Pencil support
        var pencilCoordinator: PencilInteractionCoordinator?
        var hoverOverlay: PencilHoverOverlayView?
        weak var canvasRef: PKCanvasView?

        /// The last active inking tool before switching to the eraser.
        /// Used to restore the tool when the user double-taps "switch to previous".
        private var previousInkingTool: PKTool?

        init(onDrawingChanged: @escaping (Data) -> Void, onSaveRequested: @escaping () -> Void) {
            self.onDrawingChanged = onDrawingChanged
            self.onSaveRequested  = onSaveRequested
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            editorSignposter.emitEvent("DrawingChanged")

            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

            // Report undo/redo availability directly from the canvas's undo manager.
            // PKCanvasView inherits UIResponder.undoManager which traverses the responder
            // chain — the same manager PencilKit registers stroke actions against.
            let um = canvasView.undoManager
            onUndoStateChanged?(um?.canUndo ?? false, um?.canRedo ?? false)

            // Debounce disk writes: flush 0.8 s after the last stroke.
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                editorSignposter.emitEvent("DrawingSaved")
                self?.onSaveRequested()
            }
        }
    }
}

// MARK: - PencilActionDelegate

extension CanvasView.Coordinator: PencilActionDelegate {

    // MARK: Tool switching

    func pencilDidRequestSwitchToEraser() {
        guard let canvas = canvasRef else { return }
        if !(canvas.tool is PKEraserTool) {
            // Remember current inking tool before switching to eraser.
            previousInkingTool = canvas.tool
        }
        canvas.tool = PKEraserTool(.vector)
    }

    func pencilDidRequestSwitchToPreviousTool() {
        guard let canvas = canvasRef else { return }
        if let previous = previousInkingTool {
            canvas.tool = previous
            previousInkingTool = nil
        } else {
            // No previous tool recorded — toggle from eraser to default pen.
            canvas.tool = PKInkingTool(.pen, color: .label, width: 2)
        }
    }

    // MARK: Contextual palette

    func pencilDidRequestContextualPalette(at anchorPoint: CGPoint) {
        guard let canvas = canvasRef,
              let window = canvas.window else { return }
        // Convert from canvas coordinates to window coordinates.
        let windowPoint = canvas.convert(anchorPoint, to: window)
        ContextualPencilPaletteView.show(
            at: windowPoint,
            in: window,
            canvas: canvas
        )
    }

    // MARK: Undo / redo

    func pencilDidRequestUndo() {
        canvasRef?.undoManager?.undo()
    }

    func pencilDidRequestRedo() {
        canvasRef?.undoManager?.redo()
    }

    // MARK: Hover preview

    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        hoverOverlay?.update(position: position, altitude: altitude, azimuth: azimuth)
    }

    // MARK: Barrel-roll fountain pen (Apple Pencil Pro, iOS 17.5+)

    func pencilBarrelRollChanged(angle: CGFloat) {
        guard #available(iOS 17.5, *), let canvas = canvasRef else { return }
        guard let inkTool = canvas.tool as? PKInkingTool,
              inkTool.inkType == .fountainPen else { return }

        // Map barrel-roll angle to a width variation that mimics a calligraphic nib:
        // • Roll  0 (neutral)       → base width
        // • Roll ±π/2 (edge-on)     → ~30 % of base width (thin stroke)
        // • Roll  π  (flipped)      → base width again (symmetrical)
        let rollFactor   = (cos(angle) + 1) / 2            // 0.0 … 1.0
        let baseWidth    = inkTool.width
        let minWidth     = max(baseWidth * 0.3, 1.0)
        let maxWidth     = baseWidth * 1.8
        let targetWidth  = minWidth + rollFactor * (maxWidth - minWidth)
        let clampedWidth = min(max(targetWidth, 1), 20)    // sane bounds

        // Only update when the change is visually meaningful to avoid
        // rebuilding PKInkingTool on every micro-movement.
        if abs(clampedWidth - baseWidth) > 0.4 {
            canvas.tool = PKInkingTool(.fountainPen, color: inkTool.color, width: clampedWidth)
        }
    }
}

// MARK: - Shape Overlay View

/// Transparent UIView overlay that captures pan gestures when the shape tool is
/// active. Displays a dashed CAShapeLayer preview while the user drags, then
/// converts the finished gesture path into a PKStroke and calls onShapeDrawn.
final class ShapeOverlayView: UIView {
    var shapeType: ShapeType
    var strokeColor: UIColor { didSet { previewLayer.strokeColor = strokeColor.cgColor } }
    var strokeWidth: CGFloat  { didSet { previewLayer.lineWidth  = strokeWidth } }
    private let onShapeDrawn: (PKStroke) -> Void

    private let previewLayer = CAShapeLayer()
    private var startPoint: CGPoint = .zero

    init(
        shapeType: ShapeType,
        strokeColor: UIColor,
        strokeWidth: CGFloat,
        onShapeDrawn: @escaping (PKStroke) -> Void
    ) {
        self.shapeType   = shapeType
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.onShapeDrawn = onShapeDrawn
        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false

        previewLayer.fillColor      = UIColor.clear.cgColor
        previewLayer.strokeColor    = strokeColor.cgColor
        previewLayer.lineWidth      = strokeWidth
        previewLayer.lineDashPattern = [6, 4]
        previewLayer.isHidden       = true
        layer.addSublayer(previewLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            startPoint = point
            previewLayer.isHidden = false
        case .changed:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.path = makeBezierPath(from: startPoint, to: point).cgPath
            CATransaction.commit()
        case .ended:
            previewLayer.isHidden = true
            previewLayer.path     = nil
            onShapeDrawn(makeStroke(from: startPoint, to: point))
        default:
            previewLayer.isHidden = true
            previewLayer.path     = nil
        }
    }

    // MARK: Path Construction

    private func makeBezierPath(from: CGPoint, to: CGPoint) -> UIBezierPath {
        switch shapeType {
        case .line:
            let p = UIBezierPath(); p.move(to: from); p.addLine(to: to)
            return p
        case .rectangle:
            return UIBezierPath(rect: CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            ))
        case .circle:
            return UIBezierPath(ovalIn: CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            ))
        case .arrow:
            let p = UIBezierPath(); p.move(to: from); p.addLine(to: to)
            let angle   = atan2(to.y - from.y, to.x - from.x)
            let headLen = min(24, hypot(to.x - from.x, to.y - from.y) * 0.25)
            let left  = CGPoint(x: to.x - headLen * cos(angle - .pi / 6),
                                y: to.y - headLen * sin(angle - .pi / 6))
            let right = CGPoint(x: to.x - headLen * cos(angle + .pi / 6),
                                y: to.y - headLen * sin(angle + .pi / 6))
            p.move(to: to); p.addLine(to: left)
            p.move(to: to); p.addLine(to: right)
            return p
        }
    }

    // MARK: Stroke Construction

    private func makeStroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let ink    = PKInk(.pen, color: strokeColor)
        let points = samplePath(makeBezierPath(from: from, to: to), spacing: 3)

        // Ensure at least two points so PencilKit renders a visible stroke.
        let resolved = points.count >= 2 ? points : [from, to]

        let pkPoints = resolved.enumerated().map { i, pt in
            PKStrokePoint(
                location: pt,
                timeOffset: TimeInterval(i) * 0.005,
                size: CGSize(width: strokeWidth, height: strokeWidth),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let pkPath = PKStrokePath(controlPoints: pkPoints, creationDate: Date())
        return PKStroke(ink: ink, path: pkPath, transform: .identity, mask: nil)
    }

    /// Densely samples a UIBezierPath into evenly-spaced CGPoints.
    private func samplePath(_ bezier: UIBezierPath, spacing: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []
        var prev: CGPoint = .zero

        bezier.cgPath.applyWithBlock { ptr in
            let el = ptr.pointee
            switch el.type {
            case .moveToPoint:
                prev = el.points[0]; result.append(prev)

            case .addLineToPoint:
                let end = el.points[0]
                linearSample(from: prev, to: end, spacing: spacing, into: &result)
                prev = end

            case .addQuadCurveToPoint:
                let ctrl = el.points[0]; let end = el.points[1]
                let steps = max(4, Int(hypot(end.x - prev.x, end.y - prev.y) / spacing))
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    result.append(CGPoint(
                        x: (1-t)*(1-t)*prev.x + 2*(1-t)*t*ctrl.x + t*t*end.x,
                        y: (1-t)*(1-t)*prev.y + 2*(1-t)*t*ctrl.y + t*t*end.y
                    ))
                }; prev = end

            case .addCurveToPoint:
                let c1 = el.points[0]; let c2 = el.points[1]; let end = el.points[2]
                let steps = max(8, Int(hypot(end.x - prev.x, end.y - prev.y) / spacing))
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps); let mt = 1 - t
                    result.append(CGPoint(
                        x: mt*mt*mt*prev.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x,
                        y: mt*mt*mt*prev.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y
                    ))
                }; prev = end

            case .closeSubpath:
                if let first = result.first {
                    linearSample(from: prev, to: first, spacing: spacing, into: &result)
                    prev = first
                }

            @unknown default: break
            }
        }
        return result
    }

    private func linearSample(from: CGPoint, to: CGPoint, spacing: CGFloat, into result: inout [CGPoint]) {
        let dist  = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(dist / spacing))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            result.append(CGPoint(
                x: from.x + t * (to.x - from.x),
                y: from.y + t * (to.y - from.y)
            ))
        }
    }
}
