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

    /// Sticker instances for the current page.
    var currentPageStickers: [StickerInstance] = []
    /// Callback to persist sticker changes.
    var onStickersChanged: (([StickerInstance]) -> Void)?
    /// Callback when sticker selection changes.
    var onStickerSelectionChanged: ((UUID?) -> Void)?
    /// Image provider for rendering sticker assets.
    var stickerImageProvider: ((String) -> UIImage?)?

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

    /// Whether this page uses infinite canvas mode. When `true` the canvas
    /// provides a much larger content area and a wider zoom range, giving the
    /// user an unbounded whiteboard-like drawing surface.
    var isInfiniteCanvas: Bool = false

    // MARK: - Page dimensions

    /// A4 paper aspect ratio (~1 : √2) used to compute page height from width.
    private static let a4AspectRatio: CGFloat = 1.414

    /// Multiplier applied to the standard page size in each dimension to create
    /// the infinite canvas content area (e.g. 4× = 16× total area).
    private static let infiniteCanvasMultiplier: CGFloat = 4.0

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
            onSaveRequested: onSaveRequested,
            onPinchToOverview: onPinchToOverview
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
        // Frame-based layout sized to the page dimensions so the ruling
        // zooms and scrolls together with the PencilKit drawing content.
        let ps = Self.pageSize
        let bgSize: CGSize
        if isInfiniteCanvas {
            bgSize = CGSize(
                width: ps.width * Self.infiniteCanvasMultiplier,
                height: ps.height * Self.infiniteCanvasMultiplier
            )
        } else {
            bgSize = ps
        }
        let pageBackground = PageBackgroundView(frame: CGRect(origin: .zero, size: bgSize))
        pageBackground.pageColor    = backgroundColor
        pageBackground.pageType     = isInfiniteCanvas ? .blank : pageType
        pageBackground.lineColor    = Self.rulingLineColor(for: backgroundColor)
        pageBackground.isUserInteractionEnabled = false

        // Give the page a soft drop-shadow so it looks like a physical sheet
        // resting on the desk surface.  An explicit shadow path avoids the
        // expensive offscreen-composite pass that Core Animation would otherwise
        // need for a view with a non-opaque background.
        if !isInfiniteCanvas {
            pageBackground.layer.shadowColor = UIColor.black.cgColor
            pageBackground.layer.shadowOpacity = 0.18
            pageBackground.layer.shadowRadius = 12
            pageBackground.layer.shadowOffset = CGSize(width: 0, height: 3)
            pageBackground.layer.shadowPath =
                UIBezierPath(rect: CGRect(origin: .zero, size: bgSize)).cgPath
        }

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
        if isInfiniteCanvas {
            // Infinite canvas: wider zoom range so users can zoom far out to see
            // the whole board or zoom in for fine detail.
            canvas.minimumZoomScale = 0.1
            canvas.maximumZoomScale = 8.0
        } else {
            // Paginated: 0.25× minimum lets users step back for a full-page view.
            // 5× maximum provides fine-detail writing precision.
            canvas.minimumZoomScale = 0.25
            canvas.maximumZoomScale = 5.0
        }
        canvas.bouncesZoom = true

        // Deceleration rate: fast deceleration feels more "anchored" and prevents
        // the canvas from sliding away after a quick pan. This matches the feel
        // of physical paper on a desk.
        canvas.decelerationRate = .fast

        // Set the canvas content area. For infinite canvas mode the area is much
        // larger so the user has essentially unbounded space to draw on.
        let contentSize: CGSize
        if isInfiniteCanvas {
            contentSize = CGSize(
                width: ps.width * Self.infiniteCanvasMultiplier,
                height: ps.height * Self.infiniteCanvasMultiplier
            )
        } else {
            contentSize = ps
        }
        canvas.contentSize = contentSize

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

        // Tell the coordinator whether we're in infinite canvas mode so it can
        // handle dynamic expansion when strokes approach the edges.
        context.coordinator.isInfiniteCanvas = isInfiniteCanvas

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

        // ── Sticker canvas (draggable sticker overlays) ──────────────────────
        let stickerCanvas = StickerCanvasView(frame: .zero)
        stickerCanvas.translatesAutoresizingMaskIntoConstraints = false
        stickerCanvas.stickers = currentPageStickers
        stickerCanvas.imageProvider = stickerImageProvider
        stickerCanvas.onStickerTransformed = { sticker in
            context.coordinator.handleStickerTransformed(sticker)
        }
        stickerCanvas.onStickerDeleted = { stickerID in
            context.coordinator.handleStickerDeleted(stickerID)
        }
        stickerCanvas.onSelectionChanged = { stickerID in
            context.coordinator.handleStickerSelectionChanged(stickerID)
        }
        context.coordinator.onStickersChanged = onStickersChanged
        context.coordinator.onStickerSelectionChanged = onStickerSelectionChanged
        container.addSubview(stickerCanvas)
        NSLayoutConstraint.activate([
            stickerCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            stickerCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stickerCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stickerCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.stickerCanvas = stickerCanvas

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
            guard coordinator.canvasRef?.tool is PKInkingTool else { return }
            let inkColor = (coordinator.canvasRef?.tool as? PKInkingTool)?.color ?? .label
            coordinator.effects.dispatch(
                .strokeBegan(at: location, inkColor: inkColor),
                inkEffectEngine: coordinator.effectEngine
            )
        }
        nibTracker.onNibMoved = { [context] location, force, velocity in
            let coordinator = context.coordinator
            guard coordinator.canvasRef?.tool is PKInkingTool else { return }
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

        // Pinch-in opens page overview (strict threshold to avoid accidental opens
        // during normal zoom interactions).
        let pinchOverview = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinchToOverview(_:))
        )
        pinchOverview.delegate = context.coordinator
        container.addGestureRecognizer(pinchOverview)
        context.coordinator.pinchOverviewGesture = pinchOverview

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

        // For infinite canvas, scroll to the centre of the content area so the
        // user starts drawing in the middle of the board. Deferred to the next
        // run-loop tick because `canvas.bounds` may be `.zero` during `makeUIView`.
        if isInfiniteCanvas {
            DispatchQueue.main.async {
                // If a restored drawing already extends beyond the initial
                // content area (from a previous session that expanded), grow
                // the canvas before centering so all content is reachable.
                context.coordinator.expandCanvasIfNeeded(in: canvas)

                let cs = canvas.contentSize
                let cx = (cs.width - canvas.bounds.width) / 2
                let cy = (cs.height - canvas.bounds.height) / 2
                canvas.contentOffset = CGPoint(x: max(cx, 0), y: max(cy, 0))
            }
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
        context.coordinator.onPinchToOverview = onPinchToOverview
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

        // Sync sticker canvas.
        if let stickerCanvas = coordinator.stickerCanvas {
            stickerCanvas.stickers = currentPageStickers
            stickerCanvas.imageProvider = stickerImageProvider
            stickerCanvas.selectedStickerID = toolStoreForFade?.activeStickerSelection
        }
        coordinator.onStickersChanged = onStickersChanged
        coordinator.onStickerSelectionChanged = onStickerSelectionChanged

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
            widgetCanvas: coordinator.widgetCanvas,
            stickerCanvas: coordinator.stickerCanvas
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

    /// Editor-mode coordinator.
    ///
    /// Inherits all shared drawing lifecycle, object-layer handling, effects,
    /// Apple Pencil support, undo/redo, and background sync from
    /// `CanvasCoordinatorBase`.  Adds infinite-canvas dynamic expansion and
    /// the `CanvasPageDiff`-driven `applyDiff` update path (via the
    /// `CanvasCoordinator+DiffUpdate.swift` extension).
    final class Coordinator: CanvasCoordinatorBase {

        /// Whether this page uses infinite canvas mode.
        var isInfiniteCanvas: Bool = false

        /// True while the canvas is being expanded (content shift in progress).
        /// Prevents recursive `canvasViewDrawingDidChange` triggers from the
        /// programmatic `drawing.transformed(using:)` call during expansion.
        private var isExpandingCanvas = false

        /// Callback forwarded from `CanvasPageView`.
        var onCanvasUndoManagerAvailable: ((UndoManager?) -> Void)?

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onSaveRequested: @escaping () -> Void,
            onPinchToOverview: (() -> Void)? = nil
        ) {
            super.init(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
            self.onPinchToOverview = onPinchToOverview
        }

        // MARK: - Infinite Canvas: Drawing Change Hook

        /// Override the base class hook to add infinite-canvas expansion and
        /// re-propagation when the content area grows.
        override func didProcessDrawingChange(in canvasView: PKCanvasView, data: Data) {
            let preExpansionSize = canvasView.contentSize
            expandCanvasIfNeeded(in: canvasView)
            if canvasView.contentSize != preExpansionSize {
                let updatedData = canvasView.drawing.dataRepresentation()
                if updatedData != data {
                    lastPropagatedDrawingData = updatedData
                    onDrawingChanged(updatedData)
                }
            }
        }

        // MARK: - Dynamic Infinite Canvas Expansion

        /// Distance (in content points) from the current content edge at which
        /// the canvas auto-expands.
        private static let expansionMargin: CGFloat = CanvasPageView.pageSize.width * 0.5

        /// Amount to grow the canvas in each direction that needs expanding.
        private static let expansionIncrement: CGFloat = 2.0

        /// Checks whether the drawing content is approaching the edges of the
        /// current canvas content area and, if so, expands the canvas so the
        /// user never hits a hard boundary.
        func expandCanvasIfNeeded(in canvasView: PKCanvasView) {
            guard isInfiniteCanvas else { return }

            let drawingBounds = canvasView.drawing.bounds
            guard !drawingBounds.isEmpty else { return }

            let currentSize = canvasView.contentSize
            let ps = CanvasPageView.pageSize
            let margin = Self.expansionMargin
            let increment = ps.width * Self.expansionIncrement

            var dw: CGFloat = 0
            var dh: CGFloat = 0
            var offsetDx: CGFloat = 0
            var offsetDy: CGFloat = 0

            if drawingBounds.maxX > currentSize.width - margin {
                dw += increment
            }
            if drawingBounds.minX < margin {
                dw += increment
                offsetDx = increment
            }
            if drawingBounds.maxY > currentSize.height - margin {
                dh += increment
            }
            if drawingBounds.minY < margin {
                dh += increment
                offsetDy = increment
            }

            guard dw > 0 || dh > 0 else { return }

            let newSize = CGSize(
                width: currentSize.width + dw,
                height: currentSize.height + dh
            )

            if offsetDx > 0 || offsetDy > 0 {
                let shift = CGAffineTransform(translationX: offsetDx, y: offsetDy)
                suppressDrawingChangeHandler = true
                canvasView.drawing = canvasView.drawing.transformed(using: shift)
                suppressDrawingChangeHandler = false
            }

            canvasView.contentSize = newSize

            if offsetDx > 0 || offsetDy > 0 {
                var offset = canvasView.contentOffset
                offset.x += offsetDx
                offset.y += offsetDy
                canvasView.contentOffset = offset
            }

            if let bg = pageBackground {
                bg.frame = CGRect(origin: .zero, size: newSize)
            }

            syncBackgroundWithCanvas(canvasView)
        }
    }
}
