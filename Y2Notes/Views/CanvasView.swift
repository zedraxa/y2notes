import SwiftUI
import PencilKit
import PDFKit
import OSLog

// MARK: - Performance instrumentation (canvas)

private let editorLogger = Logger(subsystem: "com.y2notes.app", category: "editor")
private let editorSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "editor.perf")

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

struct CanvasView: UIViewRepresentable {
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
    /// Called when a two-finger swipe gesture requests a page change.
    /// Positive = next page, negative = previous page.
    let onPageSwipe: ((Int) -> Void)?
    /// Called when a pinch-in gesture requests the page overview.
    let onPinchToOverview: (() -> Void)?
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

    // MARK: - Page dimensions

    /// Canonical page size, forwarded from `CanvasConstants` for call-site
    /// compatibility (e.g. `CanvasView.pageSize`).
    static var pageSize: CGSize { CanvasConstants.pageSize }

    static func pageToken(noteID: UUID, pageIndex: Int) -> String {
        "\(noteID.uuidString)-\(pageIndex)"
    }

    static func pdfBackgroundToken(pdfURL: URL?, pageIndex: Int, backgroundColor: UIColor) -> String {
        let url = pdfURL?.absoluteString ?? ""
        let color = stableColorToken(backgroundColor)
        // Length-prefixing makes parsing unambiguous even when URL/color strings
        // themselves contain '#', '|' or other delimiter-like characters.
        return "\(url.count)#\(url)|\(pageIndex)|\(color.count)#\(color)"
    }

    private static func stableColorToken(_ color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            // 5 decimals gives a stable token while tolerating tiny floating-point
            // conversion noise across equivalent UIColor representations.
            return String(
                format: "%.5f-%.5f-%.5f-%.5f",
                red, green, blue, alpha
            )
        }
        var white: CGFloat = 0
        if color.getWhite(&white, alpha: &alpha) {
            return String(format: "w%.5f-a%.5f", white, alpha)
        }
        if let components = color.cgColor.components {
            let values = components.map { String(format: "%.5f", $0) }.joined(separator: "-")
            return "cg-\(values)"
        }
        return "unknown"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDrawingChanged: onDrawingChanged,
            onSaveRequested: onSaveRequested,
            onPageSwipe: onPageSwipe,
            onPinchToOverview: onPinchToOverview
        )
    }

    // swiftlint:disable:next function_body_length
    func makeUIView(context: Context) -> UIView {
        let setupState = editorSignposter.beginInterval("CanvasSetup")
        editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - begin")

        let container = UIView()
        // The container is the "desk surface" — it shows around the page when
        // zoomed out.  The paper colour is rendered by PageBackgroundView instead.
        container.backgroundColor = CanvasConstants.deskSurfaceColor

        // ── Page background (ruling + paper tint, sits behind the canvas) ──────
        let ps = CanvasConstants.pageSize
        let pageBackground = PageBackgroundView(frame: CGRect(origin: .zero, size: ps))
        pageBackground.pageColor    = backgroundColor
        pageBackground.pageType     = pageType
        pageBackground.lineColor    = CanvasConstants.rulingLineColor(for: backgroundColor)
        pageBackground.isUserInteractionEnabled = false

        // Give the page a soft drop-shadow so it looks like a physical sheet
        // resting on the desk surface.  An explicit shadow path avoids the
        // expensive offscreen-composite pass that Core Animation would otherwise
        // need for a view with a non-opaque background.
        pageBackground.layer.shadowColor   = UIColor.black.cgColor
        pageBackground.layer.shadowOpacity = 0.18
        pageBackground.layer.shadowRadius  = 12
        pageBackground.layer.shadowOffset  = CGSize(width: 0, height: 3)
        pageBackground.layer.shadowPath    =
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
            context.coordinator.pdfBackgroundToken = Self.pdfBackgroundToken(
                pdfURL: pdfURL,
                pageIndex: pageIndex,
                backgroundColor: backgroundColor
            )
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
        context.coordinator.boundPageToken = Self.pageToken(noteID: noteID, pageIndex: pageIndex)
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

        // ── Shared overlays via builder ──────────────────────────────────────
        CanvasViewBuilder.buildOverlays(
            in: container,
            canvas: canvas,
            coordinator: context.coordinator,
            currentPageShapes: currentPageShapes,
            isShapeToolActive: isShapeToolActive,
            currentPageAttachments: currentPageAttachments,
            attachmentNoteID: attachmentNoteID,
            onAttachmentsChanged: onAttachmentsChanged,
            onAttachmentSelectionChanged: onAttachmentSelectionChanged,
            currentPageWidgets: currentPageWidgets,
            onWidgetsChanged: onWidgetsChanged,
            onWidgetSelectionChanged: onWidgetSelectionChanged,
            currentPageStickers: currentPageStickers,
            onStickersChanged: onStickersChanged,
            onStickerSelectionChanged: onStickerSelectionChanged,
            stickerImageProvider: stickerImageProvider,
            isTextToolActive: isTextToolActive,
            currentPageTextObjects: currentPageTextObjects,
            onTextObjectsChanged: onTextObjectsChanged,
            onTextObjectSelectionChanged: onTextObjectSelectionChanged,
            onPlaceTextObject: onPlaceTextObject,
            onShapesChanged: onShapesChanged,
            activeFX: activeFX,
            fxColor: fxColor,
            toolStoreForFade: toolStoreForFade
        )

        // ── Page gestures (two-finger pan + three-finger pinch) ──────────────
        let pagePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePagePan(_:))
        )
        pagePan.minimumNumberOfTouches = 2
        pagePan.maximumNumberOfTouches = 2
        pagePan.delegate = context.coordinator
        container.addGestureRecognizer(pagePan)
        context.coordinator.pagePanGesture = pagePan

        // Pinch-in opens page overview grid.
        // The gesture delegate allows simultaneous recognition with
        // PKCanvasView's built-in pinch-to-zoom so normal zoom still works.
        let pinchOverview = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinchToOverview(_:))
        )
        pinchOverview.delegate = context.coordinator
        container.addGestureRecognizer(pinchOverview)
        context.coordinator.pinchOverviewGesture = pinchOverview

        // ── Book feel: page shadow ──────────────────────────────────────────
        // Shadow is on the pageBackground layer (see above) so it follows the
        // page rather than the full-screen container.

        // Seed coordinator state so the first updateUIView call does not misfire.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder so Apple Pencil is ready immediately.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            // Set initial zoom so the page width fits the visible canvas exactly.
            // This ensures the user sees a complete, correctly-proportioned page on
            // first open regardless of device orientation or screen size.
            let canvasW = canvas.bounds.width
            if canvasW > 0 {
                let fitZoom = canvasW / CanvasConstants.pageSize.width
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, fitZoom))
                canvas.setZoomScale(clamped, animated: false)
            }
            editorSignposter.endInterval("CanvasSetup", setupState)
            editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - complete")
        }

        // Play a paper-settle reveal when this canvas represents a newly added page.
        if isNewPage {
            PageTransitionEngine.playNewPageReveal(on: container.layer)
        }

        return container
    }

    // swiftlint:disable:next cyclomatic_complexity
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        context.coordinator.toolStoreRef = toolStoreForFade

        // Keep a stable PKCanvasView instance and rebind page content when the
        // logical page changes.
        context.coordinator.bindPageIfNeeded(
            pageToken: Self.pageToken(noteID: noteID, pageIndex: pageIndex),
            drawingData: drawingData,
            canvas: canvas
        )

        // Sync page background (ruling view).
        if let bg = context.coordinator.pageBackground {
            if bg.pageColor != backgroundColor {
                bg.pageColor  = backgroundColor
                bg.lineColor  = CanvasConstants.rulingLineColor(for: backgroundColor)
            }
            if bg.pageType != pageType {
                bg.pageType = pageType
            }
            context.coordinator.syncBackgroundWithCanvas(canvas)
        }

        let desiredPDFToken = Self.pdfBackgroundToken(
            pdfURL: pdfURL,
            pageIndex: pageIndex,
            backgroundColor: backgroundColor
        )
        if context.coordinator.pdfBackgroundToken != desiredPDFToken {
            syncPDFBackground(
                in: uiView,
                coordinator: context.coordinator,
                desiredToken: desiredPDFToken
            )
        }

        // Sync drawing policy.
        if canvas.drawingPolicy != drawingPolicy {
            canvas.drawingPolicy = drawingPolicy
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
            context.coordinator.palmGuard.reset()
        }

        // Sync active tool.
        if !context.coordinator.isDrawing {
            let snapshot = ToolSnapshot(currentTool)
            if context.coordinator.lastToolSnapshot != snapshot {
                canvas.tool = currentTool
                context.coordinator.lastToolSnapshot = snapshot
                if currentTool is PKEraserTool {
                    context.coordinator.interactionFeedback.play(.eraserEngage, on: canvas.layer)
                } else {
                    context.coordinator.interactionFeedback.play(.toolSwitch, on: canvas.layer)
                    context.coordinator.microInteractionEngine.playToolSwitchMorph(on: canvas.layer)
                }
            }
        }
        canvas.isUserInteractionEnabled = !isShapeToolActive

        // Sync overlays via shared helper.
        CanvasViewBuilder.syncOverlayCanvases(
            coordinator: context.coordinator,
            canvas: canvas,
            isShapeToolActive: isShapeToolActive,
            activeShapeType: activeShapeType,
            shapeColor: shapeColor,
            shapeWidth: shapeWidth,
            currentPageShapes: currentPageShapes,
            currentPageAttachments: currentPageAttachments,
            attachmentNoteID: attachmentNoteID,
            currentPageWidgets: currentPageWidgets,
            currentPageStickers: currentPageStickers,
            stickerImageProvider: stickerImageProvider,
            isTextToolActive: isTextToolActive,
            currentPageTextObjects: currentPageTextObjects,
            toolStore: toolStoreForFade,
            onAttachmentsChanged: onAttachmentsChanged,
            onAttachmentSelectionChanged: onAttachmentSelectionChanged,
            onWidgetsChanged: onWidgetsChanged,
            onWidgetSelectionChanged: onWidgetSelectionChanged,
            onStickersChanged: onStickersChanged,
            onStickerSelectionChanged: onStickerSelectionChanged,
            onTextObjectsChanged: onTextObjectsChanged,
            onTextObjectSelectionChanged: onTextObjectSelectionChanged,
            onPlaceTextObject: onPlaceTextObject,
            onShapesChanged: onShapesChanged
        )

        // Zoom reset.
        if context.coordinator.lastZoomResetTrigger != zoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            DispatchQueue.main.async {
                let canvasW = canvas.bounds.width
                let fitZoom = canvasW > 0 ? canvasW / CanvasConstants.pageSize.width : 1.0
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, fitZoom))
                canvas.setZoomScale(clamped, animated: true)
                editorLogger.debug("[\(noteID, privacy: .public)] zoom reset to fit-width (\(clamped, format: .fixed(precision: 2))×)")
            }
        }

        context.coordinator.onUndoStateChanged = onUndoStateChanged

        // Sync page boundary info so the page-pan gesture can reject out-of-range drags.
        context.coordinator.coordinatorPageIndex = pageIndex
        context.coordinator.coordinatorPageCount = pageCount

        // Sync effects via shared helper.
        CanvasViewBuilder.syncEffects(
            coordinator: context.coordinator,
            layer: uiView.layer,
            bounds: uiView.bounds,
            pageIndex: pageIndex,
            pageCount: pageCount,
            isMagicModeActive: isMagicModeActive,
            isStudyModeActive: isStudyModeActive,
            activeAmbientScene: activeAmbientScene,
            isAmbientSoundEnabled: isAmbientSoundEnabled,
            activeFX: activeFX,
            fxColor: fxColor,
            toolStore: toolStoreForFade
        )
    }

    /// Ensures exactly one PDF background layer is bound for the current page.
    /// Removes stale page/template layers before binding the new one.
    private func syncPDFBackground(
        in container: UIView,
        coordinator: Coordinator,
        desiredToken: String
    ) {
        coordinator.pdfBackgroundToken = desiredToken

        coordinator.pdfBackgroundView?.removeFromSuperview()
        coordinator.pdfBackgroundView = nil

        guard let pdfURL,
              let pdfDoc = PDFDocument(url: pdfURL),
              let pdfPage = pdfDoc.page(at: pageIndex) else { return }

        let ps = CanvasConstants.pageSize
        let mediaBox = pdfPage.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: ps, format: format)
        let pageImage = renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.setFillColor(backgroundColor.cgColor)
            cgCtx.fill(CGRect(origin: .zero, size: ps))
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
        if let pageBackground = coordinator.pageBackground,
           pageBackground.superview === container {
            container.insertSubview(pdfImageView, aboveSubview: pageBackground)
        } else if let canvas = coordinator.canvas,
                  canvas.superview === container {
            container.insertSubview(pdfImageView, belowSubview: canvas)
        } else {
            container.addSubview(pdfImageView)
        }
        coordinator.pdfBackgroundView = pdfImageView
        if let canvas = coordinator.canvas {
            coordinator.syncBackgroundWithCanvas(canvas)
        }
    }
}
