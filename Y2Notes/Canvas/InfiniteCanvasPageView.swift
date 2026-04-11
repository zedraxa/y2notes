// swiftlint:disable file_length type_body_length
import SwiftUI
import PencilKit
import PDFKit
import OSLog

private let infiniteLogger = Logger(subsystem: "com.y2notes.app", category: "infiniteCanvas")
private let infiniteSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "infiniteCanvas.perf")

// MARK: - InfiniteCanvasPageView

/// UIViewRepresentable for infinite (whiteboard) canvas mode.
///
/// Unlike `CanvasPageView` which renders a fixed-size page with optional
/// pagination, this view provides an unbounded drawing surface with a wider
/// zoom range (0.1×–8.0×).  The canvas automatically expands when strokes
/// approach the edge.
///
/// ## Design
/// - Always page index 0 (single page).
/// - Always blank page type (no ruling lines).
/// - No page shadow (whiteboard feel).
/// - No pinch-to-overview (no page grid for whiteboards).
/// - No page-add / pageCount concepts.
/// - Uses `CanvasViewBuilder.buildOverlays` to share overlay setup code.
struct InfiniteCanvasPageView: UIViewRepresentable {
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
    let zoomResetTrigger: Bool
    let activeFX: WritingFXType
    let fxColor: UIColor
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void
    let onUndoStateChanged: ((Bool, Bool) -> Void)?

    let pdfURL: URL?
    var toolStoreForFade: DrawingToolStore?

    var currentPageShapes: [ShapeInstance] = []
    var onShapesChanged: (([ShapeInstance]) -> Void)?

    var currentPageAttachments: [AttachmentObject] = []
    var attachmentNoteID: UUID = UUID()
    var onAttachmentsChanged: (([AttachmentObject]) -> Void)?
    var onAttachmentSelectionChanged: ((UUID?) -> Void)?

    var currentPageWidgets: [NoteWidget] = []
    var onWidgetsChanged: (([NoteWidget]) -> Void)?
    var onWidgetSelectionChanged: ((UUID?) -> Void)?

    var currentPageStickers: [StickerInstance] = []
    var onStickersChanged: (([StickerInstance]) -> Void)?
    var onStickerSelectionChanged: ((UUID?) -> Void)?
    var stickerImageProvider: ((String) -> UIImage?)?

    var isTextToolActive: Bool = false
    var currentPageTextObjects: [TextObject] = []
    var onTextObjectsChanged: (([TextObject]) -> Void)?
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    var onPlaceTextObject: ((CGPoint) -> Void)?

    var isMagicModeActive: Bool = false
    var isStudyModeActive: Bool = false
    var activeAmbientScene: AmbientScene?
    var isAmbientSoundEnabled: Bool = true

    var onZoomChanged: ((CGFloat) -> Void)?

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDrawingChanged: onDrawingChanged,
            onSaveRequested: onSaveRequested
        )
    }

    // MARK: - makeUIView

    // swiftlint:disable:next function_body_length
    func makeUIView(context: Context) -> UIView {
        let setupState = infiniteSignposter.beginInterval("InfiniteCanvasSetup")
        infiniteLogger.debug("[\(noteID, privacy: .public)] infinite canvas setup - begin")

        let container = UIView()
        container.backgroundColor = CanvasConstants.deskSurfaceColor

        // ── Page background (blank, no ruling — whiteboard feel) ─────────
        let ps = CanvasConstants.pageSize
        let multiplier = CanvasConstants.infiniteCanvasMultiplier
        let bgSize = CGSize(
            width: ps.width * multiplier,
            height: ps.height * multiplier
        )
        let pageBackground = PageBackgroundView(frame: CGRect(origin: .zero, size: bgSize))
        pageBackground.pageColor = backgroundColor
        pageBackground.pageType = .blank
        pageBackground.lineColor = CanvasConstants.rulingLineColor(for: backgroundColor)
        pageBackground.isUserInteractionEnabled = false
        // No shadow for infinite canvas — whiteboard feel.

        container.addSubview(pageBackground)
        context.coordinator.pageBackground = pageBackground

        // ── PencilKit canvas ─────────────────────────────────────────────
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = drawingPolicy
        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = true
        canvas.backgroundColor = .clear
        canvas.tool = currentTool

        if WritingConfig.useTouchTypeFiltering && drawingPolicy == .pencilOnly {
            canvas.drawingGestureRecognizer.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.pencil.rawValue)
            ]
        }

        // Wider zoom range for whiteboard mode.
        canvas.minimumZoomScale = 0.1
        canvas.maximumZoomScale = 8.0
        canvas.bouncesZoom = true
        canvas.decelerationRate = .fast

        let contentSize = CGSize(
            width: ps.width * multiplier,
            height: ps.height * multiplier
        )
        canvas.contentSize = contentSize

        // Suppress the drawing-change handler during the initial load so the
        // delegate callback does not propagate the same drawing data back to
        // SwiftUI, which would trigger a redundant update cycle.
        context.coordinator.suppressDrawingChangeHandler = true
        if !drawingData.isEmpty, let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
        context.coordinator.lastPropagatedDrawingData = canvas.drawing.dataRepresentation()
        context.coordinator.suppressDrawingChangeHandler = false

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

        context.coordinator.observeCanvasScroll(canvas)

        // ── Shape overlay ────────────────────────────────────────────────
        let overlay = ShapeOverlayView(
            shapeType: activeShapeType,
            strokeColor: shapeColor,
            strokeWidth: CGFloat(shapeWidth)
        ) { stroke in
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

        // ── Shared overlays via builder ──────────────────────────────────
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
            onShapesChanged: onShapesChanged
        )

        // Seed coordinator state.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder and center the canvas.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()

            // Expand if a restored drawing exceeds the initial content area.
            context.coordinator.expandCanvasIfNeeded(in: canvas)

            let cs = canvas.contentSize
            let cx = (cs.width - canvas.bounds.width) / 2
            let cy = (cs.height - canvas.bounds.height) / 2
            canvas.contentOffset = CGPoint(x: max(cx, 0), y: max(cy, 0))

            // Explicitly sync the page background after centering so it is
            // perfectly aligned from the first frame.
            context.coordinator.syncBackgroundWithCanvas(canvas)

            infiniteSignposter.endInterval("InfiniteCanvasSetup", setupState)
            infiniteLogger.debug("[\(noteID, privacy: .public)] infinite canvas setup - complete")
        }

        return container
    }

    // MARK: - updateUIView

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        context.coordinator.toolStoreRef = toolStoreForFade

        // Sync drawing data if it changed externally (e.g., page navigated away and back).
        let currentDrawingData = canvas.drawing.dataRepresentation()
        if currentDrawingData != drawingData {
            context.coordinator.suppressDrawingChangeHandler = true
            if !drawingData.isEmpty, let drawing = try? PKDrawing(data: drawingData) {
                canvas.drawing = drawing
                // Re-expand canvas if needed after restoring drawing
                context.coordinator.expandCanvasIfNeeded(in: canvas)
            } else {
                canvas.drawing = PKDrawing()
            }
            context.coordinator.lastPropagatedDrawingData = canvas.drawing.dataRepresentation()
            context.coordinator.suppressDrawingChangeHandler = false
            // Explicitly sync background after drawing restoration
            context.coordinator.syncBackgroundWithCanvas(canvas)
        }

        // Sync page background.
        if let bg = context.coordinator.pageBackground {
            if bg.pageColor != backgroundColor {
                bg.pageColor = backgroundColor
                bg.lineColor = CanvasConstants.rulingLineColor(for: backgroundColor)
            }
            context.coordinator.syncBackgroundWithCanvas(canvas)
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
            }
        }

        context.coordinator.onUndoStateChanged = onUndoStateChanged

        // Effects sync removed

        context.coordinator.onZoomChanged = onZoomChanged
    }

    // MARK: - Coordinator

    /// Infinite-canvas coordinator.
    ///
    /// Inherits all shared drawing lifecycle from `CanvasCoordinatorBase`.
    /// Adds dynamic canvas expansion when strokes approach edges.
    final class Coordinator: CanvasCoordinatorBase {

        /// True while the canvas is being expanded.
        private var isExpandingCanvas = false

        override init(
            onDrawingChanged: @escaping (Data) -> Void,
            onSaveRequested: @escaping () -> Void
        ) {
            super.init(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
        }

        // MARK: - Drawing Change Hook

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

        private static let expansionMargin: CGFloat = CanvasConstants.pageSize.width * 0.5
        private static let expansionIncrement: CGFloat = 2.0

        func expandCanvasIfNeeded(in canvasView: PKCanvasView) {
            let drawingBounds = canvasView.drawing.bounds
            guard !drawingBounds.isEmpty else { return }

            let currentSize = canvasView.contentSize
            let ps = CanvasConstants.pageSize
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
// swiftlint:enable file_length type_body_length
