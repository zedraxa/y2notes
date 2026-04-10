// swiftlint:disable file_length type_body_length
import SwiftUI
import PencilKit
import PDFKit
import OSLog
import UniformTypeIdentifiers

private let canvasPageLogger = Logger(subsystem: "com.y2notes.app", category: "canvasPage")
private let canvasPageSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "canvasPage.perf")

struct CanvasPageView: UIViewRepresentable {
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
    /// Page ruling style rendered behind the canvas.
    let pageType: PageType
    /// Paper material used for background tint and grain texture.
    let paperMaterial: PaperMaterial
    /// Active writing FX type from the ink-effects system (`.none` = no FX).
    let activeFX: WritingFXType
    /// Ink colour resolved for the active FX preset.
    let fxColor: UIColor
    /// Zero-based page index within the multi-page note.
    let pageIndex: Int
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void
    /// Called after each stroke with updated (canUndo, canRedo) from the canvas undo manager.
    let onUndoStateChanged: ((Bool, Bool) -> Void)?

    /// Called when the user performs a strong pinch-out gesture to return to the page overview.
    var onPinchToOverview: (() -> Void)?
    /// On-disk URL of the note's backing PDF, if available.
    /// When non-nil the canvas renders the PDF page as background instead of the
    /// procedural `PageBackgroundView`, giving the note a book-like appearance.
    let pdfURL: URL?
    /// Reference to the toolbar store, used to drive auto-fade during drawing.
    var toolStoreForFade: DrawingToolStore?

    /// Shape objects for the current page.
    var currentPageShapes: [ShapeInstance] = []
    /// Callback to persist shape changes.
    var onShapesChanged: (([ShapeInstance]) -> Void)?

    /// Attachment objects for the current page.
    var currentPageAttachments: [AttachmentObject] = []
    /// Note ID used for attachment file lookups.
    var attachmentNoteID: UUID = UUID()
    /// Callback to persist attachment changes.
    var onAttachmentsChanged: (([AttachmentObject]) -> Void)?
    /// Callback when attachment selection changes.
    var onAttachmentSelectionChanged: ((UUID?) -> Void)?

    /// Widget instances for the current page.
    var currentPageWidgets: [NoteWidget] = []
    /// Callback to persist widget changes.
    var onWidgetsChanged: (([NoteWidget]) -> Void)?
    /// Callback when widget selection changes.
    var onWidgetSelectionChanged: ((UUID?) -> Void)?

    /// Whether the text tool is active (text canvas overlay intercepts touches).
    var isTextToolActive: Bool = false
    /// Text objects for the current page.
    var currentPageTextObjects: [TextObject] = []
    /// Callback to persist text object changes.
    var onTextObjectsChanged: (([TextObject]) -> Void)?
    /// Callback when text object selection changes.
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    /// Called when the user taps an empty area while the text tool is active.
    var onPlaceTextObject: ((CGPoint) -> Void)?

    /// Total number of pages in the note, used for adaptive effects complexity signals.
    var pageCount: Int = 1

    /// Whether Magic Mode is active (writing particles, keyword glow, highlight).
    var isMagicModeActive: Bool = false
    /// Whether Study Mode is active (heading glow, checklist pulse, timer pulse).
    var isStudyModeActive: Bool = false
    /// The currently active ambient environment scene, or `nil` when inactive.
    var activeAmbientScene: AmbientScene?
    /// Whether ambient soundscapes are enabled.
    var isAmbientSoundEnabled: Bool = true

    /// When `true`, `makeUIView` plays a paper-settle reveal animation on the
    /// container layer to celebrate the addition of a brand-new blank page.
    var isNewPage: Bool = false

    /// Called when the scroll view's zoom scale changes.
    var onZoomChanged: ((CGFloat) -> Void)?

    /// Initial zoom scale to restore when the page becomes visible. If `nil`,
    /// the page uses fit-to-width zoom. This allows the carousel to persist
    /// zoom state per-page across page switches.
    var initialZoomScale: CGFloat?

    // MARK: - Page dimensions

    /// A4 paper aspect ratio (~1 : √2) used to compute page height from width.
    private static let a4AspectRatio: CGFloat = 1.414

    /// Fixed page size for the canvas content area. Uses the *landscape* screen
    /// width (the larger dimension) with an A4 aspect ratio so the page fills
    /// the screen in width regardless of orientation and provides vertical
    /// scrolling room like a real paper page.
    static let pageSize: CGSize = {
        let screen = UIScreen.main.bounds
        let w = max(screen.width, screen.height)
        return CGSize(width: w, height: ceil(w * a4AspectRatio))
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDrawingChanged: onDrawingChanged,
            onSaveRequested: onSaveRequested
        )
    }

    // swiftlint:disable:next function_body_length
    func makeUIView(context: Context) -> UIView {
        let setupState = canvasPageSignposter.beginInterval("CanvasSetup")
        canvasPageLogger.debug("[\(noteID, privacy: .public)] canvas setup - begin")

        let container = UIView()
        // The container is the "desk surface" — it shows around the page when
        // zoomed out.  The paper colour is rendered by PageBackgroundView instead.
        container.backgroundColor = Self.deskSurfaceColor

        // ── Page background (ruling + paper tint, sits behind the canvas) ──────
        // Frame-based layout sized to the fixed page dimensions so the ruling
        // zooms and scrolls together with the PencilKit drawing content.
        let ps = Self.pageSize
        let pageBackground = PageBackgroundView(frame: CGRect(origin: .zero, size: ps))
        pageBackground.pageColor    = backgroundColor
        pageBackground.pageType     = pageType
        pageBackground.lineColor    = Self.rulingLineColor(for: backgroundColor)
        pageBackground.grainIntensity = paperMaterial.grainIntensity
        pageBackground.rulingTint   = paperMaterial.rulingTint
        pageBackground.isUserInteractionEnabled = false

        // Give the page a soft drop-shadow so it looks like a physical sheet
        // resting on the desk surface.  An explicit shadow path avoids the
        // expensive offscreen-composite pass that Core Animation would otherwise
        // need for a view with a non-opaque background.
        pageBackground.layer.shadowColor = UIColor.black.cgColor
        pageBackground.layer.shadowOpacity = 0.18
        pageBackground.layer.shadowRadius = 12
        pageBackground.layer.shadowOffset = CGSize(width: 0, height: 3)
        pageBackground.layer.shadowPath =
            UIBezierPath(rect: CGRect(origin: .zero, size: ps)).cgPath

        container.addSubview(pageBackground)
        context.coordinator.pageBackground = pageBackground

        // ── PDF page background (book-like feel) ─────────────────────────────
        // When the note has a backing PDF, render the template page from the PDF
        // file so the background is a real PDF page.  This sits above the
        // procedural PageBackgroundView and provides pixel-perfect fidelity with
        // the exported PDF.
        if let pdfURL,
           let pdfDoc = PDFDocument(url: pdfURL),
           let pdfPage = pdfDoc.page(at: pageIndex) {
            let mediaBox = pdfPage.bounds(for: .mediaBox)
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: ps, format: format)
            let pageImage = renderer.image { ctx in
                let cgCtx = ctx.cgContext
                cgCtx.setFillColor(backgroundColor.cgColor)
                cgCtx.fill(CGRect(origin: .zero, size: ps))
                // Scale from PDF media box to canvas page size
                let sx = ps.width / mediaBox.width
                let sy = ps.height / mediaBox.height
                let scale = min(sx, sy)
                cgCtx.saveGState()
                cgCtx.scaleBy(x: scale, y: -scale)
                cgCtx.translateBy(x: 0, y: -mediaBox.height)
                pdfPage.draw(with: .mediaBox, to: cgCtx)
                cgCtx.restoreGState()
            }
            let pdfImageView = UIImageView(image: pageImage)
            pdfImageView.frame = CGRect(origin: .zero, size: ps)
            pdfImageView.contentMode = .scaleToFill
            pdfImageView.isUserInteractionEnabled = false
            container.addSubview(pdfImageView)
            context.coordinator.pdfBackgroundView = pdfImageView
        }

        // ── PencilKit canvas ─────────────────────────────────────────────────
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = drawingPolicy
        canvas.alwaysBounceVertical   = true
        canvas.alwaysBounceHorizontal = true
        // Canvas is transparent so the page background shows through.
        canvas.backgroundColor = .clear
        canvas.tool = currentTool

        // Touch type filtering for latency reduction: when pencilOnly mode is
        // active, restrict the drawing gesture recognizer to pencil touches only.
        // This eliminates the ~16ms first-touch discrimination delay that
        // PKCanvasView normally incurs waiting to decide if a touch is pencil
        // or finger.
        if WritingConfig.useTouchTypeFiltering && drawingPolicy == .pencilOnly {
            canvas.drawingGestureRecognizer.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.pencil.rawValue)
            ]
        }

        // Zoom/pan: PKCanvasView inherits UIScrollView zoom support.
        // 0.25× minimum lets users step back for a full-page view.
        // 5×   maximum provides fine-detail writing precision.
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.bouncesZoom = true

        // Deceleration rate: fast deceleration feels more "anchored" and prevents
        // the canvas from sliding away after a quick pan. This matches the feel
        // of physical paper on a desk.
        canvas.decelerationRate = .fast

        // Set the canvas content area to the fixed page dimensions so the user
        // can draw across the full page and scroll vertically.
        canvas.contentSize = ps

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

        // Begin observing scroll/zoom so the page background tracks the canvas
        // content (zoom + pan).
        context.coordinator.observeCanvasScroll(canvas)

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

        // ── Attachment canvas (attachment cards layer) ────────────────────────
        let attachCanvas = AttachmentCanvasView(frame: .zero)
        attachCanvas.translatesAutoresizingMaskIntoConstraints = false
        attachCanvas.noteID = attachmentNoteID
        attachCanvas.attachments = currentPageAttachments
        attachCanvas.onSelectionChanged = { attachmentID in
            context.coordinator.onAttachmentSelectionChanged?(attachmentID)
        }
        attachCanvas.onAttachmentTransformed = { attachment in
            context.coordinator.handleAttachmentTransformed(attachment)
        }
        attachCanvas.onAttachmentsChanged = { attachments in
            context.coordinator.handleAttachmentsChanged(attachments)
        }
        context.coordinator.onAttachmentsChanged = onAttachmentsChanged
        context.coordinator.onAttachmentSelectionChanged = onAttachmentSelectionChanged
        container.addSubview(attachCanvas)
        NSLayoutConstraint.activate([
            attachCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            attachCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            attachCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            attachCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.attachmentCanvas = attachCanvas

        // ── Widget canvas (interactive widget cards layer) ───────────────────
        let widgetCanvas = WidgetCanvasView(frame: .zero)
        widgetCanvas.translatesAutoresizingMaskIntoConstraints = false
        widgetCanvas.widgets = currentPageWidgets
        widgetCanvas.onSelectionChanged = { widgetID in
            context.coordinator.onWidgetSelectionChanged?(widgetID)
        }
        widgetCanvas.onWidgetTransformed = { widget in
            context.coordinator.handleWidgetTransformed(widget)
        }
        widgetCanvas.onWidgetsChanged = { widgets in
            context.coordinator.handleWidgetsChanged(widgets)
        }
        // Study mode: fire checklist completion animation.
        widgetCanvas.onChecklistCompleted = { _, center in
            context.coordinator.studyModeEngine.checklistComplete(at: center)
        }
        // Study mode: fire timer/progress completion animation.
        widgetCanvas.onTimerCompleted = { _, _ in
            context.coordinator.studyModeEngine.timerComplete()
        }
        context.coordinator.onWidgetsChanged = onWidgetsChanged
        context.coordinator.onWidgetSelectionChanged = onWidgetSelectionChanged
        container.addSubview(widgetCanvas)
        NSLayoutConstraint.activate([
            widgetCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            widgetCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            widgetCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            widgetCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.widgetCanvas = widgetCanvas

        // ── Text object canvas (anchored text boxes layer) ───────────────────
        let textCanvas = TextCanvasView(frame: .zero)
        textCanvas.translatesAutoresizingMaskIntoConstraints = false
        textCanvas.isTextToolActive = isTextToolActive
        textCanvas.textObjects = currentPageTextObjects
        textCanvas.onSelectionChanged = { textObjectID in
            context.coordinator.onTextObjectSelectionChanged?(textObjectID)
        }
        textCanvas.onTextObjectsChanged = { textObjects in
            context.coordinator.handleTextObjectsChanged(textObjects)
        }
        textCanvas.onPlaceTextObject = { point in
            context.coordinator.onPlaceTextObject?(point)
        }
        textCanvas.onTextObjectTransformed = { textObject in
            context.coordinator.handleTextObjectTransformed(textObject)
        }
        context.coordinator.onTextObjectsChanged = onTextObjectsChanged
        context.coordinator.onTextObjectSelectionChanged = onTextObjectSelectionChanged
        context.coordinator.onPlaceTextObject = onPlaceTextObject
        container.addSubview(textCanvas)
        NSLayoutConstraint.activate([
            textCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            textCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.textCanvas = textCanvas

        // ── Shape object canvas (editable shapes layer) ──────────────────────
        let shapeCanvas = ShapeCanvasView(frame: .zero)
        shapeCanvas.translatesAutoresizingMaskIntoConstraints = false
        shapeCanvas.shapes = currentPageShapes
        shapeCanvas.isShapeToolActive = isShapeToolActive
        shapeCanvas.onShapesChanged = { [weak shapeCanvas] shapes in
            guard let shapeCanvas else { return }
            context.coordinator.handleShapesChanged(shapes)
            shapeCanvas.shapes = shapes
        }
        shapeCanvas.onSelectionChanged = { shapeID in
            context.coordinator.handleShapeSelectionChanged(shapeID)
        }
        context.coordinator.onShapesChanged = onShapesChanged
        container.addSubview(shapeCanvas)
        NSLayoutConstraint.activate([
            shapeCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            shapeCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shapeCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shapeCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.shapeCanvas = shapeCanvas

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

        // ── Eraser cursor overlay (non-interactive, shows ring sized to eraser width) ──
        let eraserCursor = EraserCursorOverlay(frame: .zero)
        eraserCursor.translatesAutoresizingMaskIntoConstraints = false
        eraserCursor.isUserInteractionEnabled = false
        canvas.addSubview(eraserCursor)
        NSLayoutConstraint.activate([
            eraserCursor.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            eraserCursor.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            eraserCursor.topAnchor.constraint(equalTo: canvas.topAnchor),
            eraserCursor.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        context.coordinator.eraserCursorOverlay = eraserCursor

        // ── Apple Pencil interaction coordinator ─────────────────────────────
        let pencilCoordinator = PencilInteractionCoordinator()
        pencilCoordinator.delegate = context.coordinator
        pencilCoordinator.attach(to: canvas)
        context.coordinator.pencilCoordinator = pencilCoordinator
        context.coordinator.canvasRef = canvas

        // ── Real-time nib tracker for effects ────────────────────────────────
        // PencilNibTrackerGestureRecognizer fires on every pencil touchesMoved
        // event at the hardware's native frame rate (up to 240 Hz).  This drives
        // ink-effect emitter positions in real time instead of waiting for
        // canvasViewDrawingDidChange (which only fires on committed stroke batches
        // and lags 100–300 ms behind the actual pen tip).
        let nibTracker = PencilNibTrackerGestureRecognizer()
        nibTracker.onNibBegan = { [context] location in
            let coordinator = context.coordinator
            guard coordinator.isDrawing,
                  coordinator.canvasRef?.tool is PKInkingTool else { return }
            let inkColor = (coordinator.canvasRef?.tool as? PKInkingTool)?.color ?? .label
            coordinator.effects.dispatch(
                .strokeBegan(at: location, inkColor: inkColor),
                inkEffectEngine: coordinator.effectEngine
            )
        }
        nibTracker.onNibMoved = { [context] location, force, velocity in
            let coordinator = context.coordinator
            guard coordinator.isDrawing,
                  coordinator.canvasRef?.tool is PKInkingTool else { return }
            coordinator.effects.dispatch(
                .strokeUpdated(at: location, pressure: force, velocity: velocity),
                inkEffectEngine: coordinator.effectEngine
            )
        }
        canvas.addGestureRecognizer(nibTracker)
        context.coordinator.nibTracker = nibTracker

        // ── Scratch-to-delete gesture recognizer ─────────────────────────────
        // ScribbleDeleteRecognizer is a fully passive observer: it never cancels
        // or prevents PKCanvasView's own drawing recognizer.  When a rapid
        // back-and-forth pencil motion is detected, the matching ink strokes are
        // removed via deleteScratchStrokes(in:).  The deletion is dispatched
        // asynchronously to guarantee PKCanvasView has committed the stroke before
        // we modify canvas.drawing.
        let scratchRecognizer = ScribbleDeleteRecognizer()
        scratchRecognizer.onScratchDetected = { [weak coordinator = context.coordinator] viewportRect in
            DispatchQueue.main.async {
                coordinator?.deleteScratchStrokes(in: viewportRect)
            }
        }
        canvas.addGestureRecognizer(scratchRecognizer)
        context.coordinator.scratchDeleteRecognizer = scratchRecognizer

        // Pre-warm all haptic generators for interaction feedback (AGENT-23).
        context.coordinator.interactionFeedback.prepareAll()

        // ── Ink effect engine (fire / sparkle / glitch / ripple) ────────────
        let engine = InkEffectEngine(tier: DeviceCapabilityTier.current)
        engine.configure(fx: activeFX, color: fxColor)
        engine.attach(to: container)
        context.coordinator.effectEngine = engine

        // ── Writing Effects Pipeline (glow, neon, trail, taper, pooling) ───
        context.coordinator.writingPipeline.attach(to: container)
        context.coordinator.writingPipeline.configure(
            config: toolStoreForFade?.writingEffectConfig ?? .default,
            color: toolStoreForFade?.activeColor ?? .black
        )

        // Seed coordinator state so the first updateUIView call does not misfire.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder so Apple Pencil is ready immediately.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            // Restore zoom state if the carousel provided a previously recorded
            // zoom level for this page. Otherwise fit-to-width so the user sees
            // a complete, correctly-proportioned page on first open.
            let canvasW = canvas.bounds.width
            if canvasW > 0 {
                let targetZoom: CGFloat
                if let saved = self.initialZoomScale {
                    targetZoom = saved
                } else {
                    targetZoom = canvasW / CanvasPageView.pageSize.width
                }
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, targetZoom))
                canvas.setZoomScale(clamped, animated: false)
            }
            canvasPageSignposter.endInterval("CanvasSetup", setupState)
            canvasPageLogger.debug("[\(noteID, privacy: .public)] canvas setup - complete")
        }

        // Play a paper-settle reveal when this canvas represents a newly added page.
        if isNewPage {
            PageTransitionEngine.playNewPageReveal(on: container.layer)
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        // Wire up toolbar store reference for auto-fade (idempotent).
        context.coordinator.toolStoreRef = toolStoreForFade

        syncPageBackground(context.coordinator, canvas: canvas)
        syncDrawingPolicy(context.coordinator, canvas: canvas)
        syncActiveTool(context.coordinator, canvas: canvas)
        canvas.isUserInteractionEnabled = !isShapeToolActive

        syncOverlayCanvases(context.coordinator, canvas: canvas)

        // Zoom reset: animate to fit-to-width when the trigger value flips.
        // "Fit to width" is more useful than a fixed 1× scale because it adapts
        // to the current screen size and orientation.
        if context.coordinator.lastZoomResetTrigger != zoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            // Dispatch to avoid mutating scroll state mid-layout-pass.
            DispatchQueue.main.async {
                let canvasW = canvas.bounds.width
                let fitZoom = canvasW > 0 ? canvasW / CanvasPageView.pageSize.width : 1.0
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, fitZoom))
                canvas.setZoomScale(clamped, animated: true)
                canvasPageLogger.debug("[\(noteID, privacy: .public)] zoom reset to fit-width (\(clamped, format: .fixed(precision: 2))×)")
            }
        }

        // Keep the undo state callback current (closures capture SwiftUI state by value).
        context.coordinator.onUndoStateChanged = onUndoStateChanged

        syncEffectsEngines(context.coordinator, layer: uiView.layer, bounds: uiView.bounds)

        // Keep the zoom-changed callback current.
        context.coordinator.onZoomChanged = onZoomChanged
    }

    // MARK: - updateUIView helpers

    private func syncPageBackground(_ coordinator: Coordinator, canvas: PKCanvasView) {
        guard let bg = coordinator.pageBackground else { return }
        if bg.pageColor != backgroundColor {
            bg.pageColor = backgroundColor
            bg.lineColor = Self.rulingLineColor(for: backgroundColor)
        }
        if bg.pageType != pageType {
            bg.pageType = pageType
        }
        let wantedIntensity = paperMaterial.grainIntensity
        if bg.grainIntensity != wantedIntensity {
            bg.grainIntensity = wantedIntensity
        }
        let wantedTint = paperMaterial.rulingTint
        if bg.rulingTint != wantedTint {
            bg.rulingTint = wantedTint
        }
        // Re-sync position/scale in case SwiftUI re-rendered while
        // the canvas was scrolled or zoomed.
        coordinator.syncBackgroundWithCanvas(canvas)
    }

    private func syncDrawingPolicy(_ coordinator: Coordinator, canvas: PKCanvasView) {
        guard canvas.drawingPolicy != drawingPolicy else { return }
        canvas.drawingPolicy = drawingPolicy
        // Update touch type filtering to match: pencilOnly → restrict to pencil
        // touches for faster first-touch discrimination, anyInput → allow all.
        if WritingConfig.useTouchTypeFiltering {
            if drawingPolicy == .pencilOnly {
                canvas.drawingGestureRecognizer.allowedTouchTypes = [
                    NSNumber(value: UITouch.TouchType.pencil.rawValue)
                ]
            } else {
                canvas.drawingGestureRecognizer.allowedTouchTypes = [
                    NSNumber(value: UITouch.TouchType.direct.rawValue),
                    NSNumber(value: UITouch.TouchType.pencil.rawValue),
                ]
            }
        }
        // Reset palm guard when switching modes.
        coordinator.palmGuard.reset()
    }

    private func syncActiveTool(_ coordinator: Coordinator, canvas: PKCanvasView) {
        // Update the active tool from DrawingToolStore — but ONLY when:
        // 1. The user is not mid-stroke (setting tool mid-stroke kills PencilKit's
        //    internal pressure/tilt pipeline, destroying pressure sensitivity).
        // 2. The tool actually changed. We compare a lightweight snapshot of the
        //    tool's identity (type + ink type + color + width) to avoid redundant
        //    assignments that would reset PencilKit's state.
        guard !coordinator.isDrawing else { return }
        let snapshot = ToolSnapshot(currentTool)
        guard coordinator.lastToolSnapshot != snapshot else { return }
        canvas.tool = currentTool
        coordinator.lastToolSnapshot = snapshot

        // ── Interaction feedback for tool switch (AGENT-23) ─────
        if currentTool is PKEraserTool {
            coordinator.interactionFeedback.play(.eraserEngage, on: canvas.layer)
        } else {
            coordinator.interactionFeedback.play(.toolSwitch, on: canvas.layer)
            coordinator.microInteractionEngine.playToolSwitchMorph(on: canvas.layer)
        }
    }

    private func syncOverlayCanvases(_ coordinator: Coordinator, canvas: PKCanvasView) {
        // Sync shape overlay properties.
        if let overlay = coordinator.shapeOverlay {
            overlay.isHidden = !isShapeToolActive
            overlay.shapeType = activeShapeType
            overlay.strokeColor = shapeColor
            overlay.strokeWidth = CGFloat(shapeWidth)
        }

        // Sync shape object canvas.
        if let shapeCanvas = coordinator.shapeCanvas {
            shapeCanvas.isShapeToolActive = isShapeToolActive
            shapeCanvas.shapes = currentPageShapes
            shapeCanvas.selectedShapeID = toolStoreForFade?.activeShapeSelection
        }

        // Sync attachment canvas.
        if let attachCanvas = coordinator.attachmentCanvas {
            attachCanvas.attachments = currentPageAttachments
            attachCanvas.noteID = attachmentNoteID
            attachCanvas.selectedAttachmentID = toolStoreForFade?.activeAttachmentSelection
            attachCanvas.zoomScale = canvas.zoomScale
        }
        coordinator.onAttachmentsChanged = onAttachmentsChanged
        coordinator.onAttachmentSelectionChanged = onAttachmentSelectionChanged

        // Sync widget canvas.
        if let widgetCanvas = coordinator.widgetCanvas {
            widgetCanvas.widgets = currentPageWidgets
            widgetCanvas.selectedWidgetID = toolStoreForFade?.activeWidgetSelection
        }
        coordinator.onWidgetsChanged = onWidgetsChanged
        coordinator.onWidgetSelectionChanged = onWidgetSelectionChanged

        // Sync text object canvas.
        if let textCanvas = coordinator.textCanvas {
            textCanvas.isTextToolActive = isTextToolActive
            textCanvas.textObjects = currentPageTextObjects
            textCanvas.selectedTextObjectID = toolStoreForFade?.activeTextObjectSelection
        }
        coordinator.onTextObjectsChanged = onTextObjectsChanged
        coordinator.onTextObjectSelectionChanged = onTextObjectSelectionChanged
        coordinator.onPlaceTextObject = onPlaceTextObject
    }

    private func syncEffectsEngines(_ coordinator: Coordinator, layer: CALayer, bounds: CGRect) {
        // Sync page boundary info so adaptive effects can track page position.
        coordinator.coordinatorPageIndex = pageIndex
        coordinator.coordinatorPageCount = pageCount

        // Sync adaptive effects engine with current note complexity.
        coordinator.adaptiveEffectsEngine.pageCount = pageCount
        // Propagate current intensity to canvas sub-views (coordinator
        // handles its own sub-engines automatically via Combine).
        let intensity = coordinator.adaptiveEffectsEngine.intensity
        coordinator.effects.distribute(
            intensity: intensity,
            shapeCanvas: coordinator.shapeCanvas,
            attachmentCanvas: coordinator.attachmentCanvas,
            widgetCanvas: coordinator.widgetCanvas
        )

        // Sync magic mode engine — activate/deactivate when toggle changes.
        coordinator.effects.setMagicMode(active: isMagicModeActive, on: layer)
        // Sync study mode engine — activate/deactivate when toggle changes.
        coordinator.effects.setStudyMode(active: isStudyModeActive, on: layer)
        // Keep layout-sensitive engines in sync on resize / rotation.
        coordinator.effects.updateLayout(containerBounds: bounds)

        // Sync ambient environment engine — activate/deactivate/sound when scene changes.
        let ambientEngine = coordinator.ambientEngine
        ambientEngine.soundEnabled = isAmbientSoundEnabled
        if let ts = toolStoreForFade {
            switch (activeAmbientScene, ambientEngine.activeScene) {
            case let (scene?, current) where current != scene:
                ambientEngine.activate(scene, on: layer, toolStore: ts)
            case (nil, .some):
                ambientEngine.deactivate(toolStore: ts)
            default:
                break
            }
        }
        if ambientEngine.activeScene != nil {
            ambientEngine.updateLayout(containerBounds: bounds)
        }

        // Sync ink effect engine configuration when FX type or colour changes.
        if let engine = coordinator.effectEngine {
            engine.syncLayerFrames()
            engine.configure(fx: activeFX, color: fxColor)
        }

        // Sync writing effects pipeline when the pen tool or colour changes.
        coordinator.writingPipeline.configure(
            config: toolStoreForFade?.writingEffectConfig ?? .default,
            color: toolStoreForFade?.activeColor ?? .black
        )
    }

    // MARK: - Ruling line color helper

    /// Returns a ruling line color that is visible against the given background.
    /// On dark backgrounds the lines are white at low opacity; on light backgrounds
    /// they are black at low opacity.
    static func rulingLineColor(for background: UIColor) -> UIColor {
        let isDarkBackground: Bool = {
            var white: CGFloat = 0
            if background.getWhite(&white, alpha: nil) {
                return white < 0.5
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            if background.getRed(&red, green: &green, blue: &blue, alpha: nil) {
                let relativeLuminance =
                    (0.2126 * red) +
                    (0.7152 * green) +
                    (0.0722 * blue)
                return relativeLuminance < 0.5
            }

            return false
        }()

        return isDarkBackground
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.label.withAlphaComponent(0.10)
    }

    // MARK: - Desk surface color

    /// The background color shown outside the page boundaries (the "desk" surface).
    /// Uses a neutral warm-gray that contrasts with the paper in both light and
    /// dark appearances, giving the canvas the look of a real page resting on a table.
    private static let deskSurfaceColor: UIColor = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.13, alpha: 1)
            : UIColor(white: 0.86, alpha: 1)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let onDrawingChanged: (Data) -> Void
        let onSaveRequested: () -> Void
        weak var canvas: PKCanvasView?
        weak var shapeOverlay: ShapeOverlayView?
        /// Page ruling / background view placed behind the canvas.
        weak var pageBackground: PageBackgroundView?
        /// PDF page image rendered behind the canvas (book-like feel).
        weak var pdfBackgroundView: UIImageView?
        /// Updated by updateUIView to always hold the freshest closure.
        var onUndoStateChanged: ((Bool, Bool) -> Void)?
        /// Tracks the last zoom-reset trigger seen so we only react to flips.
        var lastZoomResetTrigger: Bool = false
        private var debounceTimer: Timer?

        // Apple Pencil support
        var pencilCoordinator: PencilInteractionCoordinator?
        /// Passive gesture recognizer that feeds real-time pencil positions
        /// to the effects engines at the hardware's native touch rate.
        var nibTracker: PencilNibTrackerGestureRecognizer?
        var hoverOverlay: PencilHoverOverlayView?
        var eraserCursorOverlay: EraserCursorOverlay?
        /// Passive gesture recognizer that detects scratch-to-delete gestures.
        var scratchDeleteRecognizer: ScribbleDeleteRecognizer?
        weak var canvasRef: PKCanvasView?

        /// Ink effect engine that renders fire/sparkle/glitch/ripple overlays.
        var effectEngine: InkEffectEngine?

        /// Central coordinator that owns and wires all effect sub-engines.
        let effects = EffectsCoordinator()

        // Convenience accessors forwarded to the coordinator.
        var pageTransitionEngine: PageTransitionEngine { effects.pageTransitionEngine }
        var focusModeEngine: FocusModeEngine           { effects.focusModeEngine }
        var ambientEngine: AmbientEnvironmentEngine    { effects.ambientEngine }
        var magicModeEngine: MagicModeEngine           { effects.magicModeEngine }
        var studyModeEngine: StudyModeEngine           { effects.studyModeEngine }
        var adaptiveEffectsEngine: AdaptiveEffectsEngine { effects.adaptiveEngine }
        var writingPipeline: WritingEffectsPipeline    { effects.writingEffectsPipeline }
        var microInteractionEngine: MicroInteractionEngine { effects.microInteractionEngine }
        var snapAlignEffectEngine: SnapAlignEffectEngine { effects.snapAlignEffectEngine }
        var interactionFeedback: InteractionFeedbackEngine { effects.interactionFeedbackEngine }

        /// Shape objects canvas for the current page.
        weak var shapeCanvas: ShapeCanvasView?

        /// Debounce timer for persisting shape changes.
        private var shapeDebounceTimer: Timer?

        /// Callback to persist shape changes.
        var onShapesChanged: (([ShapeInstance]) -> Void)?

        /// Attachment canvas overlay for the current page.
        weak var attachmentCanvas: AttachmentCanvasView?

        /// Debounce timer for persisting attachment changes.
        private var attachmentDebounceTimer: Timer?

        /// Callback to persist attachment changes.
        var onAttachmentsChanged: (([AttachmentObject]) -> Void)?

        /// Callback when attachment selection changes.
        var onAttachmentSelectionChanged: ((UUID?) -> Void)?

        /// Widget canvas overlay for the current page.
        weak var widgetCanvas: WidgetCanvasView?

        /// Debounce timer for persisting widget changes.
        private var widgetDebounceTimer: Timer?

        /// Callback to persist widget changes.
        var onWidgetsChanged: (([NoteWidget]) -> Void)?

        /// Callback when widget selection changes.
        var onWidgetSelectionChanged: ((UUID?) -> Void)?

        /// Text object canvas overlay for the current page.
        weak var textCanvas: TextCanvasView?

        /// Debounce timer for persisting text object changes.
        private var textDebounceTimer: Timer?

        /// Callback to persist text object changes.
        var onTextObjectsChanged: (([TextObject]) -> Void)?

        /// Callback when text object selection changes.
        var onTextObjectSelectionChanged: ((UUID?) -> Void)?

        /// Called when the user taps empty space with the text tool active.
        var onPlaceTextObject: ((CGPoint) -> Void)?

        /// Callback to propagate text object transform to the view.
        var onTextObjectTransformed: ((TextObject) -> Void)?

        /// Weak reference to the drawing tool store for toolbar auto-fade.
        weak var toolStoreRef: DrawingToolStore?

        /// Task that schedules the toolbar fade after a delay of active drawing.
        private var fadeTask: Task<Void, Never>?

        /// Current zero-based page index, kept in sync by `updateUIView`.
        var coordinatorPageIndex: Int = 0
        /// Total page count, kept in sync by `updateUIView`.
        var coordinatorPageCount: Int = 1

        /// True while the user is actively drawing a stroke. Used to prevent
        /// `updateUIView` from overwriting `canvas.tool` mid-stroke, which
        /// would reset PencilKit's internal pressure/tilt pipeline.
        private(set) var isDrawing = false

        /// Tracks the last PKTool identity set on the canvas so updateUIView
        /// skips redundant assignments that would reset PencilKit's state.
        var lastToolSnapshot: ToolSnapshot?

        /// Stable base width captured from the tool when a fountain-pen stroke
        /// begins. Used for barrel-roll modulation so the feedback loop does
        /// not shift the reference width on every micro-movement.
        var barrelRollBaseWidth: CGFloat?

        /// The last active inking tool before switching to the eraser.
        /// Used to restore the tool when the user double-taps "switch to previous".
        private var previousInkingTool: PKTool?

        /// Zoom scale captured when a stroke begins. When `WritingConfig.lockZoomDuringWriting`
        /// is enabled, the canvas zoom is pinned to this value during active writing to
        /// prevent accidental zoom drift from multi-touch interference.
        private var strokeStartZoomScale: CGFloat?

        /// Timer that re-enables zoom/scroll gestures after a short delay following
        /// the end of a stroke. Prevents accidental zoom when lifting the hand
        /// between quick successive strokes.
        private var postStrokeZoomUnlockTimer: Timer?

        /// Timer that fires when the user holds the pen still after drawing a stroke,
        /// triggering automatic straightening of the last stroke into a clean line.
        private var holdToStraightenTimer: Timer?

        /// True while `straightenLastStroke` is replacing the canvas drawing so
        /// `canvasViewDrawingDidChange` does not restart `holdToStraightenTimer`
        /// on the programmatic change.
        private var isStraightening = false

        /// Tracks Apple Pencil contact timing for palm rejection in `.anyInput` mode.
        let palmGuard = PalmGuardState()

        /// Tracks stroke count and data size for performance warnings.
        let strokeMonitor = StrokePerformanceMonitor()

        // KVO observers that keep the page background in sync with canvas
        // scroll offset and zoom scale. Invalidated automatically on dealloc.
        private var contentOffsetObservation: NSKeyValueObservation?
        private var zoomScaleObservation: NSKeyValueObservation?

        /// Tracks whether the last zoom update landed on a detent, so the
        /// visual micro-bounce fires only on the leading edge (entry, not hold).
        private var wasOnZoomDetent: Bool = false

        // Pre-prepared haptic generator for double-tap pencil delete feedback.
        // Preparing eagerly avoids the latency spike that would occur if the
        // generator were created and prepared on the first deletion event.
        private let deletionImpactGenerator: UIImpactFeedbackGenerator = {
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            return g
        }()

        /// Called when the scroll view's zoom scale changes.
        var onZoomChanged: ((CGFloat) -> Void)?

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onSaveRequested: @escaping () -> Void
        ) {
            self.onDrawingChanged = onDrawingChanged
            self.onSaveRequested  = onSaveRequested
        }

        deinit {
            // Flush any pending drawing save so strokes are never silently
            // dropped when the coordinator deallocates (e.g. on page change).
            flushPendingSave()
            // Invalidate remaining timers.
            postStrokeZoomUnlockTimer?.invalidate()
            shapeDebounceTimer?.invalidate()
            attachmentDebounceTimer?.invalidate()
            // KVO observations are invalidated automatically by
            // NSKeyValueObservation.deinit, but nil them for clarity.
            contentOffsetObservation?.invalidate()
            zoomScaleObservation?.invalidate()
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        // MARK: - Drawing lifecycle (protects pressure/tilt pipeline)

        /// Converts a PKDrawing content-space point to the viewport/overlay
        /// coordinate space so that ink-effect particles render at the correct
        /// on-screen position regardless of zoom/scroll state.
        private func viewportPoint(from contentPoint: CGPoint, in canvasView: PKCanvasView) -> CGPoint {
            let zoom = canvasView.zoomScale
            let offset = canvasView.contentOffset
            return CGPoint(
                x: contentPoint.x * zoom - offset.x,
                y: contentPoint.y * zoom - offset.y
            )
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = true
            // Cancel any pending zoom-unlock timer from a previous stroke so
            // rapid successive strokes keep zoom locked continuously.
            postStrokeZoomUnlockTimer?.invalidate()
            postStrokeZoomUnlockTimer = nil

            // Cancel any pending hold-to-straighten from the previous stroke.
            holdToStraightenTimer?.invalidate()
            holdToStraightenTimer = nil

            // Lock zoom during writing to prevent accidental zoom drift from
            // multi-touch interference (e.g. palm resting on screen).
            if WritingConfig.lockZoomDuringWriting {
                strokeStartZoomScale = canvasView.zoomScale
                canvasView.pinchGestureRecognizer?.isEnabled = false
                canvasView.isScrollEnabled = false
            }

            // Capture base width for barrel-roll modulation at stroke start.
            if let inkTool = canvasView.tool as? PKInkingTool {
                barrelRollBaseWidth = inkTool.width
            }
            // NOTE: .strokeBegan is dispatched by PencilNibTrackerGestureRecognizer
            // with the actual first-contact position.  No dispatch needed here.
            // Auto-fade toolbar using config constants
            fadeTask?.cancel()
            fadeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(WritingConfig.toolbarFadeDelay))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFadedOpacity
                }
            }
            // Pause attachment rendering during active strokes for zero lag.
            attachmentCanvas?.renderingPaused = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = false
            // Pen lifted — discard any pending hold-to-straighten.
            holdToStraightenTimer?.invalidate()
            holdToStraightenTimer = nil
            // If barrel-roll modulated the fountain-pen width during this stroke,
            // the canvas tool is left at the modulated (drifted) width.
            // Invalidate lastToolSnapshot so updateUIView resets canvas.tool to
            // the canonical width from DrawingToolStore before the next stroke,
            // preventing a compounding feedback loop where each stroke starts
            // wider than the last.
            if barrelRollBaseWidth != nil {
                lastToolSnapshot = nil
            }
            barrelRollBaseWidth = nil

            // Re-enable zoom and scroll after a short delay to prevent
            // accidental zoom when lifting the hand between rapid successive
            // strokes.  Guard `isDrawing` in the callback to handle the rare
            // case where a new stroke begins before the timer fires.
            // Also clamp the zoom back to what it was at stroke-start if any
            // multi-touch interference caused a drift while gestures were locked.
            if WritingConfig.lockZoomDuringWriting {
                let savedZoom = strokeStartZoomScale
                postStrokeZoomUnlockTimer?.invalidate()
                postStrokeZoomUnlockTimer = Timer.scheduledTimer(
                    withTimeInterval: WritingConfig.postStrokeZoomLockDelay,
                    repeats: false
                ) { [weak self, weak canvasView] _ in
                    guard let self, !self.isDrawing, let canvas = canvasView else { return }
                    // Clamp zoom back to pre-stroke level if it drifted.
                    if let savedZoom, abs(canvas.zoomScale - savedZoom) > WritingConfig.zoomDriftTolerance {
                        canvas.setZoomScale(savedZoom, animated: true)
                    }
                    canvas.pinchGestureRecognizer?.isEnabled = true
                    canvas.isScrollEnabled = true
                }
                strokeStartZoomScale = nil
            }

            // Record pencil end time for palm guard (finger rejection window).
            palmGuard.pencilStrokeEnded()

            // Signal stroke pause to the adaptive effects engine so it can
            // decay the smoothed writing rate and potentially restore effects.
            Task { @MainActor [weak self] in
                self?.adaptiveEffectsEngine.reportStrokePause()
            }

            // Dispatch stroke-ended through the effects coordinator (single stroke read).
            let fallbackPt = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
            if let lastStroke = canvasView.drawing.strokes.last {
                let path = lastStroke.path
                let endPt = path.last.map {
                    viewportPoint(from: CGPoint(x: $0.location.x, y: $0.location.y), in: canvasView)
                } ?? fallbackPt
                let startPt = path.first.map {
                    viewportPoint(from: CGPoint(x: $0.location.x, y: $0.location.y), in: canvasView)
                } ?? endPt
                let bbox = lastStroke.renderBounds
                let vpOrigin = viewportPoint(from: bbox.origin, in: canvasView)
                let vpMax = viewportPoint(from: CGPoint(x: bbox.maxX, y: bbox.maxY), in: canvasView)
                let headingBounds = CGRect(
                    x: vpOrigin.x,
                    y: vpOrigin.y,
                    width: vpMax.x - vpOrigin.x,
                    height: vpMax.y - vpOrigin.y
                )
                let strokeEndColor = (canvasView.tool as? PKInkingTool)?.color ?? .label
                effects.dispatch(
                    .strokeEnded(
                        at: endPt,
                        start: startPt,
                        inkColor: strokeEndColor,
                        headingBounds: headingBounds
                    ),
                    inkEffectEngine: effectEngine
                )
            } else {
                effects.dispatch(
                    .strokeEnded(
                        at: fallbackPt,
                        start: fallbackPt,
                        inkColor: .label,
                        headingBounds: .zero
                    ),
                    inkEffectEngine: effectEngine
                )
            }
            // Restore toolbar opacity after drawing ends using config constants
            fadeTask?.cancel()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(WritingConfig.toolbarRestoreDelay))
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFullOpacity
                }
            }
            // Detect lasso selection state. When the user finishes a lasso gesture
            // the canvas holds an internal selection. We set hasActiveSelection so
            // the floating toolbar morphs to show selection actions.
            if canvasView.tool is PKLassoTool {
                markLassoSelectionActive()
            } else {
                updateSelectionState(for: canvasView)
            }
            // Resume attachment rendering after a short delay (matches toolbar restore timing).
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.attachmentCanvas?.renderingPaused = false
                self?.attachmentCanvas?.setNeedsDisplay()
            }
        }

        /// Updates `toolStore.hasActiveSelection` based on whether the canvas
        /// currently holds a lasso selection. Called after tool-end events and
        /// drawing changes to keep the toolbar in sync.
        ///
        /// Detection: when the lasso tool finishes a gesture, PencilKit holds an
        /// internal selection. We track this via a simple flag that is set when
        /// `canvasViewDidEndUsingTool` fires while a PKLassoTool is active, and
        /// cleared when the drawing changes (selection committed) or the tool
        /// switches away from lasso.
        func updateSelectionState(for canvasView: PKCanvasView) {
            let isLasso = canvasView.tool is PKLassoTool
            // Only set true when lasso tool just finished a gesture (likely selected
            // something). Reset when drawing changes or tool switches.
            if !isLasso && toolStoreRef?.hasActiveSelection == true {
                Task { @MainActor [weak self] in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        self?.toolStoreRef?.hasActiveSelection = false
                    }
                }
            }
        }

        /// Marks that the lasso tool completed a selection gesture.
        /// Called from `canvasViewDidEndUsingTool` when the active tool is a lasso.
        func markLassoSelectionActive() {
            guard toolStoreRef?.hasActiveSelection != true else { return }
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self?.toolStoreRef?.hasActiveSelection = true
                }
            }
        }

        /// Clears the selection state (e.g. after the drawing changes, meaning
        /// the selection was committed or the canvas was otherwise modified).
        func clearSelectionState() {
            guard toolStoreRef?.hasActiveSelection != false else { return }
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self?.toolStoreRef?.hasActiveSelection = false
                }
            }
        }

        // MARK: - Shape Object Handlers

        /// Called when the shape canvas reports changes to shape objects.
        func handleShapesChanged(_ shapes: [ShapeInstance]) {
            shapeDebounceTimer?.invalidate()
            shapeDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: ShapeConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onShapesChanged?(shapes)
            }
        }

        /// Called when shape selection changes.
        func handleShapeSelectionChanged(_ shapeID: UUID?) {
            Task { @MainActor [weak self] in
                self?.toolStoreRef?.activeShapeSelection = shapeID
            }
        }

        // MARK: - Attachment Coordination

        /// Called when an attachment is moved or resized.
        func handleAttachmentTransformed(_ attachment: AttachmentObject) {
            guard var attachments = attachmentCanvas?.attachments else { return }
            if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                attachments[idx] = attachment
            }
            handleAttachmentsChanged(attachments)
        }

        /// Debounced persistence for attachment changes.
        func handleAttachmentsChanged(_ attachments: [AttachmentObject]) {
            attachmentDebounceTimer?.invalidate()
            attachmentDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: AttachmentConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onAttachmentsChanged?(attachments)
            }
        }

        // MARK: - Widget Coordinator

        func handleWidgetTransformed(_ widget: NoteWidget) {
            guard var widgets = widgetCanvas?.widgets else { return }
            if let idx = widgets.firstIndex(where: { $0.id == widget.id }) {
                widgets[idx] = widget
            }
            handleWidgetsChanged(widgets)
        }

        /// Debounced persistence for widget changes.
        func handleWidgetsChanged(_ widgets: [NoteWidget]) {
            widgetDebounceTimer?.invalidate()
            widgetDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: WidgetConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onWidgetsChanged?(widgets)
            }
        }

        // MARK: - Text Object Coordinator

        /// Called when a text object is moved, resized, or rotated.
        func handleTextObjectTransformed(_ textObject: TextObject) {
            guard var textObjects = textCanvas?.textObjects else { return }
            if let idx = textObjects.firstIndex(where: { $0.id == textObject.id }) {
                textObjects[idx] = textObject
            }
            handleTextObjectsChanged(textObjects)
        }

        /// Debounced persistence for text object changes.
        func handleTextObjectsChanged(_ textObjects: [TextObject]) {
            textDebounceTimer?.invalidate()
            textDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: TextObjectConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onTextObjectsChanged?(textObjects)
            }
        }

        // MARK: - Double-tap pencil to delete last stroke

        /// Removes the most recently drawn stroke from the canvas.
        /// Called when the user double-taps Apple Pencil.  Registered with the
        /// canvas's own `UndoManager` so it can be reversed with undo.
        func deleteLastStroke() {
            guard let canvas = canvasRef else { return }
            let strokes = Array(canvas.drawing.strokes)
            guard !strokes.isEmpty else { return }

            let oldDrawing = canvas.drawing
            let newDrawing = PKDrawing(strokes: Array(strokes.dropLast()))

            canvas.undoManager?.registerUndo(withTarget: canvas) { cv in
                cv.drawing = oldDrawing
            }
            canvas.undoManager?.setActionName(
                NSLocalizedString("Delete Stroke", comment: "Undo action name for pencil double-tap delete")
            )

            canvas.drawing = newDrawing

            deletionImpactGenerator.impactOccurred()
            deletionImpactGenerator.prepare()
        }

        // MARK: - Scratch-to-delete

        /// Removes every PKStroke whose render bounds intersect the scratch region
        /// described by `viewportRect` (in the canvas scroll-view's bounds coordinates).
        ///
        /// This is called by ``ScribbleDeleteRecognizer`` after it confirms that the
        /// user drew a rapid back-and-forth scratch gesture.  Because the scratch was
        /// drawn with the active inking tool it becomes a regular PKStroke — that
        /// stroke's render bounds lie within `viewportRect`, so it is included in the
        /// set of strokes to remove alongside any pre-existing strokes it overlaps.
        ///
        /// The operation is registered with the canvas's `UndoManager` so it can be
        /// reversed with a standard Undo gesture or Cmd-Z.
        func deleteScratchStrokes(in viewportRect: CGRect) {
            guard let canvas = canvasRef else { return }

            // Expand the hit region slightly to account for stroke width — strokes
            // are compared by their render bounds, which already includes the ink
            // radius, but a small inset guards against sub-pixel rounding gaps.
            let contentRect = self.contentRect(from: viewportRect, in: canvas)
            let hitRect     = contentRect.insetBy(dx: -10, dy: -10)

            let allStrokes = Array(canvas.drawing.strokes)
            let remaining  = allStrokes.filter { !$0.renderBounds.intersects(hitRect) }

            // Nothing to delete — either the scratch was over empty space or the
            // detection fired erroneously.  Bail early without touching undo stack.
            guard remaining.count < allStrokes.count else { return }

            let oldDrawing = canvas.drawing
            let newDrawing = PKDrawing(strokes: remaining)

            canvas.undoManager?.registerUndo(withTarget: canvas) { cv in
                cv.drawing = oldDrawing
            }
            canvas.undoManager?.setActionName(
                NSLocalizedString("Editor.ScratchDelete.UndoAction",
                                  comment: "Undo action name for scribble-to-delete")
            )

            canvas.drawing = newDrawing

            // Scale haptic weight with the number of strokes removed: a single
            // scratch stroke that erases only itself gets a normal impact, while
            // removing several strokes at once gets a heavier double-impact.
            let deletedCount = allStrokes.count - remaining.count
            deletionImpactGenerator.impactOccurred()
            if deletedCount > 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.deletionImpactGenerator.impactOccurred()
                }
            }
            deletionImpactGenerator.prepare()
        }

        /// Converts a rectangle from the canvas scroll-view's **viewport** (bounds)
        /// coordinate space into the PKDrawing **content** coordinate space.
        ///
        /// PKStroke.renderBounds lives in content space; gesture touch locations are
        /// reported in the scroll-view's bounds space.  The mapping is:
        ///
        ///     contentPoint.x = (viewportPoint.x + contentOffset.x) / zoomScale
        ///
        /// which is the inverse of `viewportPoint(from:in:)` defined nearby.
        private func contentRect(from viewportRect: CGRect, in canvasView: PKCanvasView) -> CGRect {
            let zoom = canvasView.zoomScale
            let offset = canvasView.contentOffset
            let origin = CGPoint(
                x: (viewportRect.minX + offset.x) / zoom,
                y: (viewportRect.minY + offset.y) / zoom
            )
            let size = CGSize(
                width: viewportRect.width / zoom,
                height: viewportRect.height / zoom
            )
            return CGRect(origin: origin, size: size)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            canvasPageSignposter.emitEvent("DrawingChanged")

            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

            // NOTE: effect position updates are driven by PencilNibTrackerGestureRecognizer
            // at the hardware's native touch rate.  No position dispatch is needed here.

            // Report undo/redo availability directly from the canvas's undo manager.
            // PKCanvasView inherits UIResponder.undoManager which traverses the responder
            // chain — the same manager PencilKit registers stroke actions against.
            let um = canvasView.undoManager
            onUndoStateChanged?(um?.canUndo ?? false, um?.canRedo ?? false)

            // Drawing changed — selection was committed (paste, delete, move, etc.)
            // so clear the selection state to collapse the selection toolbar.
            clearSelectionState()

            // Update stroke performance monitor for warning thresholds.
            let strokeCount = canvasView.drawing.strokes.count
            Task { @MainActor [weak self] in
                self?.strokeMonitor.update(strokeCount: strokeCount, dataSize: data.count)
                self?.adaptiveEffectsEngine.currentPageStrokeCount = strokeCount
                self?.adaptiveEffectsEngine.reportStrokeChange()
            }

            // Hold-to-straighten: restart the timer on every new drawing change
            // while the pen is still down. If drawing stops changing (user holds
            // the pen still), the timer fires and replaces the last stroke with a
            // clean straight line between its start and end points.
            if isDrawing, !isStraightening, canvasView.tool is PKInkingTool {
                holdToStraightenTimer?.invalidate()
                holdToStraightenTimer = Timer.scheduledTimer(
                    withTimeInterval: WritingConfig.holdToStraightenDelay,
                    repeats: false
                ) { [weak self, weak canvasView] _ in
                    guard let self, self.isDrawing, let canvasView else { return }
                    self.holdToStraightenTimer = nil
                    self.straightenLastStroke(in: canvasView)
                }
            }

            // Debounce disk writes using config constant.
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: WritingConfig.saveDebounceInterval, repeats: false) { [weak self] _ in
                canvasPageSignposter.emitEvent("DrawingSaved")
                self?.onSaveRequested()
            }
        }

        /// Immediately cancels the pending debounce timer and triggers a
        /// synchronous save.  Called before page transitions so strokes
        /// drawn just before a swipe are never silently dropped.
        func flushPendingSave() {
            guard debounceTimer != nil else { return }
            debounceTimer?.invalidate()
            debounceTimer = nil
            onSaveRequested()
        }

        // MARK: - Canvas scroll / zoom → background sync
        // MARK: - Hold-to-Straighten

        /// Replaces the last stroke in `canvasView.drawing` with a clean straight
        /// line from its first point to its last point, preserving the original
        /// ink colour, tool type, and per-point pressure/tilt attributes.
        ///
        /// Called by `holdToStraightenTimer` when the user holds the pen still
        /// after drawing without lifting it. The replacement is registered with
        /// the canvas's own `UndoManager` so it can be reversed with undo.
        private func straightenLastStroke(in canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            let strokes = Array(drawing.strokes)
            guard !strokes.isEmpty else { return }
            let strokeIndex = strokes.count - 1
            let stroke = strokes[strokeIndex]
            let path = stroke.path
            guard path.count >= 2,
                  let firstPoint = path.first,
                  let lastPoint  = path.last else { return }

            let dx = lastPoint.location.x - firstPoint.location.x
            let dy = lastPoint.location.y - firstPoint.location.y
            let length = sqrt(dx * dx + dy * dy)
            guard length >= WritingConfig.holdToStraightenMinLength else { return }

            // Build a straight-line path by mapping original point attributes
            // (size, force, tilt) onto evenly-spaced locations along the new line.
            // This preserves pressure dynamics while straightening the geometry.
            let pointCount = max(3, min(path.count, WritingConfig.holdToStraightenMaxPoints))
            let straightPoints: [PKStrokePoint] = (0 ..< pointCount).map { i in
                let ratio = CGFloat(i) / CGFloat(pointCount - 1)
                let loc = CGPoint(
                    x: firstPoint.location.x + ratio * dx,
                    y: firstPoint.location.y + ratio * dy
                )
                // +0.5 performs nearest-neighbour rounding when mapping the
                // straight-line position back to an original path index.
                let origIdx = min(Int(ratio * CGFloat(path.count - 1) + 0.5), path.count - 1)
                let orig = path[origIdx]
                return PKStrokePoint(
                    location: loc,
                    timeOffset: firstPoint.timeOffset + ratio * (lastPoint.timeOffset - firstPoint.timeOffset),
                    size: orig.size,
                    opacity: orig.opacity,
                    force: orig.force,
                    azimuth: orig.azimuth,
                    altitude: orig.altitude
                )
            }

            let straightPath = PKStrokePath(
                controlPoints: straightPoints,
                creationDate: path.creationDate
            )
            let straightStroke = PKStroke(
                ink: stroke.ink,
                path: straightPath,
                transform: stroke.transform,
                mask: stroke.mask
            )

            var newStrokes = strokes
            newStrokes[strokeIndex] = straightStroke
            let newDrawing = PKDrawing(strokes: newStrokes)

            let oldDrawing = drawing
            isStraightening = true
            canvasView.undoManager?.registerUndo(withTarget: canvasView) { cv in
                cv.drawing = oldDrawing
            }
            canvasView.undoManager?.setActionName(
                NSLocalizedString("Editor.StraightenLine", comment: "Undo action name for hold-to-straighten")
            )
            canvasView.drawing = newDrawing
            isStraightening = false

            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.prepare()
            haptic.impactOccurred()
        }


        /// Start observing the canvas's contentOffset and zoomScale via KVO so
        /// the page background (ruling) follows zoom and scroll.
        func observeCanvasScroll(_ canvas: PKCanvasView) {
            contentOffsetObservation = canvas.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                self?.syncBackgroundWithCanvas(sv)
            }
            zoomScaleObservation = canvas.observe(\.zoomScale, options: [.new]) { [weak self] sv, _ in
                self?.syncBackgroundWithCanvas(sv)
                self?.centerContentDuringZoom(sv)
            }
        }

        /// Positions and scales the page background to match the canvas content.
        ///
        /// The background view sits in the container (same coordinate space as
        /// the canvas viewport). To make it visually overlay the canvas content:
        ///
        /// - **Scale** by `zoomScale` so ruling lines scale with drawing strokes.
        /// - **Translate** to compensate for `contentOffset` so the background
        ///   pans with the content.
        ///
        /// The math: a content point `(px, py)` appears in the viewport at
        /// `(px * z − o.x, py * z − o.y)`. The view's transform is applied
        /// around its center, so we derive `tx`/`ty` to make the visual frame
        /// origin land at `(−o.x, −o.y)`.
        func syncBackgroundWithCanvas(_ scrollView: UIScrollView) {
            guard let bg = pageBackground else { return }
            let zoom = scrollView.zoomScale
            let offset = scrollView.contentOffset
            let pw = bg.bounds.width
            let ph = bg.bounds.height
            let tx = -offset.x + pw * (zoom - 1) / 2
            let ty = -offset.y + ph * (zoom - 1) / 2

            let xform = CGAffineTransform(scaleX: zoom, y: zoom)
                .concatenating(CGAffineTransform(translationX: tx, y: ty))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bg.transform = xform
            pdfBackgroundView?.transform = xform
            // Keep object overlay canvases (shapes, attachments, widgets)
            // in sync with the PencilKit canvas zoom/scroll so objects
            // rendered in page-local coordinates don't drift from ink.
            shapeCanvas?.transform = xform
            attachmentCanvas?.transform = xform
            widgetCanvas?.transform = xform
            CATransaction.commit()
        }

        // MARK: - UIScrollViewDelegate (zoom centering)

        /// Centers the canvas content when zoomed out below 1× so the page
        /// stays centered on screen rather than pinning to the top-left corner.
        /// Also called from the zoomScale KVO observer so the centering logic
        /// fires reliably even when PKCanvasView does not forward
        /// `UIScrollViewDelegate` callbacks.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContentDuringZoom(scrollView)
            adaptiveEffectsEngine.zoomScale = scrollView.zoomScale
            // Zoom detent haptic + visual feedback (AGENT-23).
            interactionFeedback.updateZoom(scrollView.zoomScale, on: scrollView.layer)
            // Micro-bounce visual tick on detent entry (short-circuits on first match).
            let isOnDetent = InteractionFeedbackEngine.zoomDetents.contains {
                abs(scrollView.zoomScale - $0) < InteractionFeedbackEngine.detentTolerance
            }
            if isOnDetent && !wasOnZoomDetent {
                microInteractionEngine.playZoomDetentTick(on: scrollView.layer)
            }
            wasOnZoomDetent = isOnDetent
            onZoomChanged?(scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            onZoomChanged?(scrollView.zoomScale)
        }

        /// Adjusts content insets so the page stays centered when the scaled
        /// content is smaller than the viewport.
        private func centerContentDuringZoom(_ scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            // Horizontal centering: when scaled content is narrower than viewport
            let xInset = max(0, (boundsSize.width - contentSize.width) / 2)
            // Vertical centering: when scaled content is shorter than viewport
            let yInset = max(0, (boundsSize.height - contentSize.height) / 2)

            scrollView.contentInset = UIEdgeInsets(
                top: yInset,
                left: xInset,
                bottom: yInset,
                right: xInset
            )

            syncBackgroundWithCanvas(scrollView)
        }
    }
}

// MARK: - PencilActionDelegate

extension CanvasPageView.Coordinator: PencilActionDelegate {

    // MARK: Tool switching

    func pencilDidRequestSwitchToEraser() {
        guard let canvas = canvasRef else { return }
        if !(canvas.tool is PKEraserTool) {
            // Remember current inking tool before switching to eraser.
            previousInkingTool = canvas.tool
        }
        canvas.tool = toolStoreRef?.makeEraserTool() ?? {
            if #available(iOS 16.4, *) {
                return PKEraserTool(.bitmap, width: EraserSubType.standard.defaultWidth)
            }
            return PKEraserTool(.bitmap)
        }()
        // Interaction feedback for eraser engage (AGENT-23).
        interactionFeedback.play(.eraserEngage, on: canvas.layer)
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
        // Interaction feedback for eraser disengage (AGENT-23).
        interactionFeedback.play(.eraserDisengage, on: canvas.layer)
    }

    // MARK: Contextual palette

    func pencilDidRequestContextualPalette(at anchorPoint: CGPoint) {
        guard let canvas = canvasRef,
              let window = canvas.window else { return }
        // Convert from canvas coordinates to window coordinates.
        let windowPoint = canvas.convert(anchorPoint, to: window)
        let ts = toolStoreRef
        ContextualPencilPaletteView.show(
            at: windowPoint,
            in: window,
            canvas: canvas,
            eraserType: toolStoreRef?.eraserSubType.eraserMode.pkEraserType ?? .vector,
            onToolSelected: { [weak ts] pkTool in
                guard let ts else { return }
                if pkTool is PKEraserTool {
                    ts.activeTool = .eraser
                } else if let ink = pkTool as? PKInkingTool {
                    switch ink.inkType {
                    case .pen:         ts.activeTool = .pen
                    case .pencil:      ts.activeTool = .pencil
                    case .marker:      ts.activeTool = .highlighter
                    case .fountainPen: ts.activeTool = .fountainPen
                    default:           break
                    }
                    ts.activeColor = ink.color
                }
            }
        )
    }

    // MARK: Undo / redo

    func pencilDidRequestUndo() {
        canvasRef?.undoManager?.undo()
        // Interaction feedback for undo (AGENT-23).
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.undo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: true)
        }
    }

    func pencilDidRequestRedo() {
        canvasRef?.undoManager?.redo()
        // Interaction feedback for redo (AGENT-23).
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.redo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: false)
        }
    }

    // MARK: Double-tap delete

    func pencilDidRequestDeleteLastStroke() {
        deleteLastStroke()
    }

    // MARK: Hover preview

    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        let isErasing = canvasRef?.tool is PKEraserTool
        if isErasing {
            // Show sized eraser ring; hide ghost-nib overlay.
            let sub = toolStoreRef?.eraserSubType ?? .standard
            let width = toolStoreRef?.eraserWidth ?? sub.defaultWidth
            eraserCursorOverlay?.update(position: position, subType: sub, eraserWidth: width)
            hoverOverlay?.update(position: nil, altitude: altitude, azimuth: azimuth)
        } else {
            // Sync the ghost-nib appearance with the current tool state on every hover
            // event.  This is cheap and ensures the nib reflects a colour/width change
            // made while the pencil was already hovering.
            if let ts = toolStoreRef {
                let personality = ts.activePersonality
                let info = HoverToolInfo(
                    tool: ts.activeTool,
                    color: ts.activeColor,
                    width: CGFloat(ts.activeWidth),
                    opacity: CGFloat(ts.activeOpacity),
                    widthMultiplier: CGFloat(personality?.widthMultiplier ?? 1.0),
                    showsAzimuthLine: personality?.usesTiltShading == true
                        || personality?.usesBarrelRoll == true,
                    eraserMode: ts.eraserMode
                )
                hoverOverlay?.configure(with: info)
            }
            // Show ghost-nib; hide eraser ring.
            hoverOverlay?.update(position: position, altitude: altitude, azimuth: azimuth)
            eraserCursorOverlay?.update(position: nil, subType: .standard, eraserWidth: 0)
        }
    }

    // MARK: Barrel-roll fountain pen (Apple Pencil Pro, iOS 17.5+)

    func pencilBarrelRollChanged(angle: CGFloat) {
        guard #available(iOS 17.5, *), let canvas = canvasRef else { return }
        guard let inkTool = canvas.tool as? PKInkingTool,
              inkTool.inkType == .fountainPen else { return }

        // Use the stable base width captured at stroke start (not the current
        // tool width, which drifts if we've already modulated once).
        guard let baseWidth = barrelRollBaseWidth else { return }

        // Don't modulate while between strokes — let PencilKit keep its
        // native barrel-roll behaviour for the initial stroke setup.
        guard isDrawing else { return }

        // Map barrel-roll angle to a width variation that mimics a calligraphic nib:
        // • Roll  0 (neutral)       → base width
        // • Roll ±π/2 (edge-on)     → ~30 % of base width (thin stroke)
        // • Roll  π  (flipped)      → base width again (symmetrical)
        let rollFactor   = (cos(angle) + 1) / 2            // 0.0 … 1.0
        let minWidth     = max(baseWidth * 0.3, 1.0)
        let maxWidth     = baseWidth * 1.8
        let targetWidth  = minWidth + rollFactor * (maxWidth - minWidth)
        let clampedWidth = min(max(targetWidth, 1), 20)    // sane bounds

        // Only update when the change is visually meaningful to avoid
        // rebuilding PKInkingTool on every micro-movement.
        let currentWidth = inkTool.width
        if abs(clampedWidth - currentWidth) > 0.8 {
            canvas.tool = PKInkingTool(.fountainPen, color: inkTool.color, width: clampedWidth)
        }
    }
}
