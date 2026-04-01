import SwiftUI
import PencilKit

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
                onDrawingChanged: { data in
                    noteStore.updateDrawing(for: note.id, data: data)
                },
                onSaveRequested: {
                    noteStore.save()
                }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                noteThemeMenu

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
        .onAppear { refreshUndoRedoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in
            refreshUndoRedoState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in
            refreshUndoRedoState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in
            refreshUndoRedoState()
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
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = backgroundColor
        container.clipsToBounds = true

        // ── PencilKit canvas ─────────────────────────────────────────────────
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = backgroundColor
        canvas.tool = currentTool

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

        // Become first responder so Apple Pencil is ready immediately.
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        if canvas.backgroundColor != backgroundColor {
            canvas.backgroundColor = backgroundColor
            uiView.backgroundColor = backgroundColor
        }

        canvas.tool = currentTool
        canvas.isUserInteractionEnabled = !isShapeToolActive

        if let overlay = context.coordinator.shapeOverlay {
            overlay.isHidden    = !isShapeToolActive
            overlay.shapeType   = activeShapeType
            overlay.strokeColor = shapeColor
            overlay.strokeWidth = CGFloat(shapeWidth)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (Data) -> Void
        let onSaveRequested: () -> Void
        weak var canvas: PKCanvasView?
        weak var shapeOverlay: ShapeOverlayView?
        private var debounceTimer: Timer?

        init(onDrawingChanged: @escaping (Data) -> Void, onSaveRequested: @escaping () -> Void) {
            self.onDrawingChanged = onDrawingChanged
            self.onSaveRequested  = onSaveRequested
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                self?.onSaveRequested()
            }
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
