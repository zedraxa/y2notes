import UIKit
import PencilKit
import os

// MARK: - CanvasConfiguration

/// Immutable configuration snapshot for a canvas page.
///
/// `Y2CanvasViewController` accepts a configuration on init and supports
/// incremental updates via `apply(_:)`.  Using a value type ensures that
/// diffing is cheap and atomic.
struct CanvasConfiguration {
    let noteID: UUID
    let drawingData: Data
    let backgroundColor: UIColor
    let defaultInkColor: UIColor
    let currentTool: PKTool
    let isShapeToolActive: Bool
    let activeShapeType: ShapeType
    let shapeColor: UIColor
    let shapeWidth: Double
    let drawingPolicy: PKCanvasViewDrawingPolicy
    let pageType: PageType
    let paperMaterial: PaperMaterial
    let activeFX: WritingFXType
    let fxColor: UIColor
    let pageIndex: Int
    let pdfURL: URL?

    // Object layers
    let shapes: [ShapeInstance]
    let attachments: [AttachmentObject]
    let widgets: [NoteWidget]
    let stickers: [StickerInstance]
    let textObjects: [TextObject]
}

// MARK: - Y2CanvasViewController

/// Pure UIKit canvas controller that owns a `PKCanvasView`, an effect overlay,
/// and all Apple Pencil interaction handling.
///
/// ## Design Principles
/// - **No SwiftUI dependency**: this class never imports SwiftUI.
/// - **Own lifecycle**: the controller manages its own view hierarchy, gesture
///   recognisers, and undo stack — it does not depend on SwiftUI view identity.
/// - **Delegate-based communication**: all output goes through `CanvasDelegate`.
/// - **State-driven updates**: call `apply(_:)` with a new configuration to
///   update tool, color, effect, or page content.
///
/// ## View Hierarchy
/// ```
/// self.view (container)
/// ├── PageBackgroundView (ruling lines, paper material)
/// ├── PKCanvasView (drawing input + native stroke rendering)
/// ├── ShapeOverlayView / StickerCanvasView / ... (object layers)
/// └── EffectOverlayLayer.overlayView (particle & animation effects)
/// ```
///
/// ## Threading
/// All public API must be called on the main thread.
final class Y2CanvasViewController: UIViewController {

    // MARK: - Public Properties

    /// Delegate that receives drawing changes, undo state, and navigation requests.
    weak var delegate: CanvasDelegate?

    /// The current configuration snapshot.
    private(set) var configuration: CanvasConfiguration

    /// The stroke rendering pipeline that manages effects and coordinate mapping.
    let renderingPipeline = StrokeRenderingPipeline()

    // MARK: - Internal Views

    /// The PencilKit canvas view that captures Apple Pencil and touch input.
    private(set) var canvasView: PKCanvasView!

    /// Apple Pencil feature coordinator (double-tap, squeeze, hover, barrel-roll).
    private var pencilCoordinator: PencilInteractionCoordinator?

    /// Debounce timer for persisting drawing changes.
    private var drawingDebounceTimer: Timer?

    private let logger = Logger(subsystem: "com.y2notes", category: "Y2CanvasViewController")
    private let signposter = OSSignposter(subsystem: "com.y2notes", category: "canvas.perf")

    // MARK: - Init

    /// Create a canvas controller with the given initial configuration.
    ///
    /// - Parameter configuration: Initial page configuration (drawing data, tool, effects, etc.).
    init(configuration: CanvasConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let state = signposter.beginInterval("canvasSetup")

        view.backgroundColor = .systemBackground

        setupCanvasView()
        setupEffectOverlay()
        setupPencilInteractions()
        loadDrawing()

        renderingPipeline.configure(fx: configuration.activeFX, fxColor: configuration.fxColor)

        signposter.endInterval("canvasSetup", state)
        logger.debug("[\(self.configuration.noteID, privacy: .public)] canvas controller loaded")
    }

    // MARK: - Public API

    /// Apply an updated configuration.
    ///
    /// This method diffs the new configuration against the current one and
    /// applies only the changes that actually differ, avoiding unnecessary
    /// PencilKit state resets (e.g. never sets `canvas.tool` mid-stroke).
    ///
    /// - Parameter newConfig: The updated configuration.
    func apply(_ newConfig: CanvasConfiguration) {
        let old = configuration
        configuration = newConfig

        // Tool update — only between strokes to preserve pressure pipeline
        if !isDrawing {
            canvasView.tool = newConfig.currentTool
        }

        // Drawing policy
        if old.drawingPolicy != newConfig.drawingPolicy {
            canvasView.drawingPolicy = newConfig.drawingPolicy
        }

        // Effect pipeline
        if old.activeFX != newConfig.activeFX || old.fxColor != newConfig.fxColor {
            renderingPipeline.configure(fx: newConfig.activeFX, fxColor: newConfig.fxColor)
        }
    }

    /// Trigger an animated reset to 1× zoom scale.
    func resetZoom(animated: Bool = true) {
        guard let scrollView = canvasView else { return }
        scrollView.setZoomScale(1.0, animated: animated)
    }

    /// Perform undo on the canvas's own undo manager.
    func performUndo() {
        canvasView.undoManager?.undo()
    }

    /// Perform redo on the canvas's own undo manager.
    func performRedo() {
        canvasView.undoManager?.redo()
    }

    // MARK: - Private State

    /// True while the user is actively drawing (between touchesBegan and touchesEnded).
    private var isDrawing = false

    // MARK: - Setup

    private func setupCanvasView() {
        let canvas = PKCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.drawingPolicy = configuration.drawingPolicy
        canvas.tool = configuration.currentTool
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = self
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0

        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.canvasView = canvas
    }

    private func setupEffectOverlay() {
        renderingPipeline.effectOverlay.install(in: view)
    }

    private func setupPencilInteractions() {
        let coordinator = PencilInteractionCoordinator()
        coordinator.delegate = self
        coordinator.attach(to: canvasView)
        self.pencilCoordinator = coordinator
    }

    private func loadDrawing() {
        guard !configuration.drawingData.isEmpty else { return }
        do {
            let drawing = try PKDrawing(data: configuration.drawingData)
            canvasView.drawing = drawing
        } catch {
            logger.error("Failed to load drawing: \(error.localizedDescription)")
        }
    }

    // MARK: - Drawing Persistence

    private func scheduleDrawingSave() {
        drawingDebounceTimer?.invalidate()
        drawingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self else { return }
            let data = self.canvasView.drawing.dataRepresentation()
            self.delegate?.canvasDidUpdateDrawing(data: data)
        }
    }

    private func reportUndoState() {
        let canUndo = canvasView.undoManager?.canUndo ?? false
        let canRedo = canvasView.undoManager?.canRedo ?? false
        delegate?.canvasDidChangeUndoState(canUndo: canUndo, canRedo: canRedo)
    }
}

// MARK: - PKCanvasViewDelegate

extension Y2CanvasViewController: PKCanvasViewDelegate {

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        scheduleDrawingSave()
        reportUndoState()
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = true

        let midpoint = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
        let inkColor = configuration.defaultInkColor
        renderingPipeline.strokeBegan(
            at: midpoint,
            inkColor: inkColor,
            inkEffectEngine: nil // Engine wired during full integration
        )
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = false

        // Report the final stroke endpoint for effects
        let strokes = canvasView.drawing.strokes
        if let lastStroke = strokes.last {
            let bounds = lastStroke.renderBounds
            let viewportBounds = renderingPipeline.viewportRect(from: bounds, in: canvasView)
            let endPoint = CGPoint(x: bounds.maxX, y: bounds.midY)
            let viewportEnd = renderingPipeline.viewportPoint(from: endPoint, in: canvasView)
            let startPoint = CGPoint(x: bounds.minX, y: bounds.midY)
            let viewportStart = renderingPipeline.viewportPoint(from: startPoint, in: canvasView)

            renderingPipeline.strokeEnded(
                at: viewportEnd,
                startPoint: viewportStart,
                inkColor: configuration.defaultInkColor,
                headingBounds: viewportBounds,
                inkEffectEngine: nil
            )
        }
    }
}

// MARK: - PencilActionDelegate

extension Y2CanvasViewController: PencilActionDelegate {

    func pencilDidRequestSwitchToEraser() {
        canvasView.tool = PKEraserTool(.bitmap)
    }

    func pencilDidRequestSwitchToPreviousTool() {
        canvasView.tool = configuration.currentTool
    }

    func pencilDidRequestContextualPalette(at anchorPoint: CGPoint) {
        // Contextual palette presentation is handled by the hosting layer
        logger.debug("Contextual palette requested at \(anchorPoint)")
    }

    func pencilDidRequestUndo() {
        performUndo()
    }

    func pencilDidRequestRedo() {
        performRedo()
    }

    func pencilDidRequestDeleteLastStroke() {
        var drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { return }
        drawing.strokes.removeLast()
        canvasView.drawing = drawing
    }

    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        // Hover overlay is managed by the coordinator; no additional action needed here
    }

    func pencilBarrelRollChanged(angle: CGFloat) {
        // Barrel roll modulates fountain-pen width — handled by the rendering pipeline
    }
}
