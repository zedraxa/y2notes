import UIKit
import PencilKit
import os

// MARK: - StrokeRenderingPipeline

/// Manages the rendering stack for strokes drawn on the canvas.
///
/// The pipeline sits between PencilKit's `PKCanvasView` (which captures input)
/// and the display, coordinating:
///   1. **PKCanvasView** rendering for standard strokes (native PencilKit).
///   2. **EffectOverlayLayer** rendering for ink-effect overlays (sparkle, fire, etc.).
///   3. **Coordinate space mapping** between PKCanvasView content space and viewport.
///
/// The pipeline does NOT own the `PKCanvasView` — that remains with
/// `Y2CanvasViewController`. Instead it provides a clean API for configuring
/// rendering state and dispatching stroke lifecycle events to effect engines.
///
/// **Thread safety**: all methods must be called on the main thread.
final class StrokeRenderingPipeline {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.y2notes", category: "StrokeRenderingPipeline")

    /// The active ink effect type. `.none` disables all effect overlays.
    private(set) var activeFX: WritingFXType = .none

    /// The colour used by the active FX preset (when FX is enabled).
    private(set) var fxColor: UIColor = .clear

    /// The effect overlay layer managed by this pipeline.
    let effectOverlay: EffectOverlayLayer

    /// The central effects coordinator that fans out stroke events to sub-engines.
    let effectsCoordinator: EffectsCoordinator

    // MARK: - Init

    init() {
        self.effectOverlay = EffectOverlayLayer()
        self.effectsCoordinator = EffectsCoordinator()
        logger.debug("StrokeRenderingPipeline initialised")
    }

    // MARK: - Configuration

    /// Update the active ink effect and colour.
    ///
    /// Call this when the user selects a new ink preset or the tool state changes.
    /// Setting `fx` to `.none` hides the effect overlay entirely (zero layer cost).
    func configure(fx: WritingFXType, fxColor: UIColor) {
        self.activeFX = fx
        self.fxColor = fxColor

        if fx == .none {
            effectOverlay.deactivate()
        }
    }

    // MARK: - Stroke Lifecycle

    /// Called when a stroke begins. Dispatches to the effects coordinator and
    /// activates the effect overlay if an FX is configured.
    ///
    /// - Parameters:
    ///   - point: Stroke start position in viewport coordinates.
    ///   - inkColor: The current ink colour (used by some effects for tinting).
    ///   - inkEffectEngine: The ink effect engine for particle/animation rendering.
    func strokeBegan(at point: CGPoint, inkColor: UIColor, inkEffectEngine: InkEffectEngine?) {
        guard activeFX != .none else { return }

        effectOverlay.activate(with: activeFX)
        effectsCoordinator.dispatch(
            .strokeBegan(at: point, inkColor: inkColor),
            inkEffectEngine: inkEffectEngine
        )
    }

    /// Called for each new stroke point. Dispatches live position, pressure, and
    /// velocity data to the effects coordinator.
    ///
    /// - Parameters:
    ///   - point: Current nib position in viewport coordinates.
    ///   - pressure: Normalised force (0–1).
    ///   - velocity: Instantaneous speed in points/second.
    ///   - inkEffectEngine: The ink effect engine for particle/animation rendering.
    func strokeUpdated(at point: CGPoint, pressure: CGFloat, velocity: CGFloat,
                       inkEffectEngine: InkEffectEngine?) {
        guard activeFX != .none else { return }

        effectsCoordinator.dispatch(
            .strokeUpdated(at: point, pressure: pressure, velocity: velocity),
            inkEffectEngine: inkEffectEngine
        )
    }

    /// Called when a stroke ends. Dispatches the final stroke geometry to the
    /// effects coordinator for end-of-stroke effects (ripples, lightning, etc.).
    ///
    /// - Parameters:
    ///   - point: Final nib position in viewport coordinates.
    ///   - startPoint: The stroke's start position in viewport coordinates.
    ///   - inkColor: The stroke's ink colour.
    ///   - headingBounds: The stroke's `renderBounds` in viewport space.
    ///   - inkEffectEngine: The ink effect engine for particle/animation rendering.
    func strokeEnded(at point: CGPoint, startPoint: CGPoint, inkColor: UIColor,
                     headingBounds: CGRect, inkEffectEngine: InkEffectEngine?) {
        guard activeFX != .none else { return }

        effectsCoordinator.dispatch(
            .strokeEnded(at: point, start: startPoint, inkColor: inkColor, headingBounds: headingBounds),
            inkEffectEngine: inkEffectEngine
        )
    }

    // MARK: - Coordinate Mapping

    /// Convert a point from PKCanvasView content space to viewport (screen) space.
    ///
    /// PencilKit strokes are stored in content coordinates (which scale with zoom).
    /// Effect overlays need viewport coordinates so particles appear at the correct
    /// screen position regardless of the canvas zoom level.
    ///
    /// - Parameters:
    ///   - contentPoint: A point in PKCanvasView content space.
    ///   - canvasView: The canvas view used for coordinate conversion.
    /// - Returns: The point in the canvas view's viewport (bounds) coordinate space.
    func viewportPoint(from contentPoint: CGPoint, in canvasView: PKCanvasView) -> CGPoint {
        let scrollView = canvasView
        let offsetX = scrollView.contentOffset.x
        let offsetY = scrollView.contentOffset.y
        let zoom = scrollView.zoomScale

        return CGPoint(
            x: (contentPoint.x * zoom) - offsetX,
            y: (contentPoint.y * zoom) - offsetY
        )
    }

    /// Convert a rect from PKCanvasView content space to viewport (screen) space.
    func viewportRect(from contentRect: CGRect, in canvasView: PKCanvasView) -> CGRect {
        let origin = viewportPoint(from: contentRect.origin, in: canvasView)
        let zoom = canvasView.zoomScale
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: contentRect.width * zoom,
            height: contentRect.height * zoom
        )
    }
}
