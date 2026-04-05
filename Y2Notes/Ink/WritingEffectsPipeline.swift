import UIKit
import QuartzCore

// MARK: - Writing Effects Pipeline

/// Renders the advanced writing overlay effects defined in `WritingEffectModel`.
///
/// This engine is the runtime counterpart to the dormant `WritingEffectModel`
/// specification.  It brings to life the four **advanced** overlay effects:
///
/// | Effect | Mechanism | Budget |
/// |--------|-----------|--------|
/// | **Glow Pen** | `CAGradientLayer` (radial, 40 pt) follows the nib | < 0.15 ms |
/// | **Neon Ink** | `screenBlendMode` compositing on overlay layer | < 0.20 ms |
/// | **Ink Trail Fade** | `CAShapeLayer` path that fades over 0.3 s | < 0.35 ms |
/// | **Gradient Ink** | Ink color interpolated per stroke segment | < 0.05 ms |
///
/// Core stroke-level effects (pressure spread, velocity thickness, edge fade,
/// micro texture, opacity fluctuation) are defined in `WritingEffectModel` and
/// require PencilKit stroke-point modification; they are gated by
/// `WritingEffectConfig` and evaluated externally during stroke collection.
///
/// **Activation:**
/// ```swift
/// pipeline.configure(config: store.effectConfig, color: activeColor)
/// pipeline.attach(to: canvasView)
/// pipeline.onStrokeBegan(at: point)
/// pipeline.onStrokeUpdated(at: point)
/// pipeline.onStrokeEnded()
/// ```
///
/// **Reduce Motion**: all animations are suppressed when
/// `ReduceMotionObserver.shared.isEnabled` is `true`.
///
/// **Budget**: each effect stays within the Stage 4 budget of 0.8 ms defined
/// by `WritingEffectPipeline.stage4OverlayBudgetMs`.
final class WritingEffectsPipeline {

    // MARK: - Tuning

    private enum Tuning {
        // ── Glow Pen ────────────────────────────────────────────────────
        static let glowLayerSize: CGFloat          = GlowPenParams.diameter
        static let glowBaseOpacity: Float          = Float(GlowPenParams.baseOpacity)
        static let glowMaxOpacity: Float           = Float(GlowPenParams.maxOpacity)
        static let glowFadeOutDuration: CFTimeInterval = GlowPenParams.fadeOutDuration

        // ── Neon Ink ─────────────────────────────────────────────────────
        static let neonShadowRadius: CGFloat       = NeonInkParams.shadowRadius
        static let neonShadowOpacity: Float        = NeonInkParams.shadowOpacity
        static let neonFilter: String              = NeonInkParams.compositingFilter

        // ── Ink Trail ────────────────────────────────────────────────────
        static let trailLineWidth: CGFloat         = InkTrailFadeParams.lineWidth
        static let trailStartOpacity: CGFloat      = InkTrailFadeParams.startOpacity
        static let trailMaxAge: TimeInterval       = InkTrailFadeParams.maxAge
        static let trailPruneInterval: TimeInterval = InkTrailFadeParams.pruneInterval

        // ── Gradient Ink ─────────────────────────────────────────────────
        static let gradientVelocityCeiling: CGFloat = VelocityThicknessParams.velocityCeiling

        // ── General ──────────────────────────────────────────────────────
        static let transitionDuration: CFTimeInterval = 0.25
    }

    // MARK: - State

    /// Active configuration.  Updated by `configure(config:color:)`.
    private var config: WritingEffectConfig = .default

    /// Current ink colour.  Drives glow and neon tint.
    private var inkColor: UIColor = .black

    /// Device capability tier — gates advanced effects.
    private let deviceTier: DeviceCapabilityTier = DeviceCapabilityTier.current

    /// Current adaptive effect intensity.  Set by `EffectsCoordinator`.
    var effectIntensity: EffectIntensity = .full

    /// Non-interactive overlay view added above the canvas.
    private(set) var overlayView: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }()

    /// Tracks the previous nib position for trail path building.
    private var lastNibPoint: CGPoint?

    /// Ephemeral glow gradient layer positioned at the current nib.
    private weak var glowLayer: CAGradientLayer?

    /// Neon ink overlay applied to the drawing canvas.
    private weak var neonOverlay: CALayer?

    /// Timer that prunes expired trail segments.
    private var pruneTimer: Timer?

    /// Pending trail segments: (path, layer, birthTime).
    private var trailSegments: [(path: CGPath, layer: CAShapeLayer, born: TimeInterval)] = []

    // MARK: - Computed Helpers

    private var shouldSuppressAnimations: Bool {
        ReduceMotionObserver.shared.isEnabled
    }

    private var effectiveConfig: WritingEffectConfig {
        config
            .resolved(for: deviceTier)
            .adapted(for: effectIntensity)
    }

    // MARK: - Lifecycle

    /// Attaches the overlay view to the given canvas view.
    ///
    /// Call once when the canvas is set up.  The overlay matches the canvas
    /// bounds and is always kept at zero animation overhead when no effect is
    /// active.
    func attach(to canvasView: UIView) {
        overlayView.frame = canvasView.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.addSubview(overlayView)
        if effectiveConfig.hasAdvancedEffects {
            schedulePruneTimer()
        }
    }

    /// Removes the overlay view from its superview and tears down all layers.
    func detach() {
        pruneTimer?.invalidate()
        pruneTimer = nil
        trailSegments.forEach { $0.layer.removeFromSuperlayer() }
        trailSegments.removeAll()
        glowLayer?.removeFromSuperlayer()
        neonOverlay?.removeFromSuperlayer()
        overlayView.removeFromSuperview()
    }

    // MARK: - Configuration

    /// Updates the active effect configuration and ink colour.
    ///
    /// Call whenever the user changes the ink preset or advanced-effect toggles.
    ///
    /// - Parameters:
    ///   - config: The new writing effect configuration.
    ///   - color: The active ink colour (used for glow / neon tint).
    func configure(config: WritingEffectConfig, color: UIColor) {
        self.config = config
        self.inkColor = color
        syncNeonOverlay()
        if effectiveConfig.hasAdvancedEffects {
            schedulePruneTimer()
        } else {
            pruneTimer?.invalidate()
            pruneTimer = nil
        }
    }

    // MARK: - Stroke Hooks

    /// Call when the Apple Pencil touches the canvas.
    func onStrokeBegan(at point: CGPoint, pressure: CGFloat = 1.0) {
        lastNibPoint = point
        if effectiveConfig.glowPenEnabled {
            updateGlowLayer(at: point, pressure: pressure)
        }
    }

    /// Call on each coalesced point update during the stroke.
    func onStrokeUpdated(at point: CGPoint, pressure: CGFloat = 1.0, velocity: CGFloat = 500) {
        defer { lastNibPoint = point }

        let cfg = effectiveConfig

        // ── Glow Pen: follow nib position ──────────────────────────────
        if cfg.glowPenEnabled {
            updateGlowLayer(at: point, pressure: pressure)
        }

        // ── Ink Trail: add a new segment ────────────────────────────────
        if cfg.inkTrailFadeEnabled, let prev = lastNibPoint {
            addTrailSegment(from: prev, to: point)
        }
    }

    /// Call when the Apple Pencil lifts from the canvas.
    func onStrokeEnded() {
        lastNibPoint = nil
        fadeOutGlowLayer()
    }

    // MARK: - Glow Pen

    private func updateGlowLayer(at point: CGPoint, pressure: CGFloat) {
        guard !shouldSuppressAnimations else { return }

        let size = Tuning.glowLayerSize
        let half = size / 2

        // Create the layer on first use; reuse afterwards.
        let layer: CAGradientLayer
        if let existing = glowLayer {
            layer = existing
        } else {
            let newLayer = makeGlowLayer()
            overlayView.layer.addSublayer(newLayer)
            glowLayer = newLayer
            layer = newLayer
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(x: point.x - half, y: point.y - half, width: size, height: size)
        // Scale opacity with pressure (clamped to max).
        let normalised = min(pressure, 1.0)
        let opacity = Tuning.glowBaseOpacity + Float(normalised) * (Tuning.glowMaxOpacity - Tuning.glowBaseOpacity)
        layer.opacity = opacity
        CATransaction.commit()
    }

    private func fadeOutGlowLayer() {
        guard let layer = glowLayer else { return }
        if shouldSuppressAnimations {
            layer.removeFromSuperlayer()
            glowLayer = nil
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.opacity
        fade.toValue = 0.0
        fade.duration = Tuning.glowFadeOutDuration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in
            layer?.removeFromSuperlayer()
        }
        layer.add(fade, forKey: "fadeOut")
        CATransaction.commit()
        glowLayer = nil
    }

    private func makeGlowLayer() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        let rgb = inkColor.cgColor.components ?? [0, 0, 0, 1]
        let glow = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1.0).cgColor
        let clear = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 0.0).cgColor
        layer.colors = [glow, clear]
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer.opacity = Tuning.glowBaseOpacity
        return layer
    }

    // MARK: - Neon Ink Overlay

    private func syncNeonOverlay() {
        let cfg = effectiveConfig
        if cfg.neonInkEnabled, !shouldSuppressAnimations {
            if neonOverlay == nil {
                let layer = CALayer()
                layer.compositingFilter = Tuning.neonFilter
                layer.shadowColor = inkColor.cgColor
                layer.shadowRadius = Tuning.neonShadowRadius
                layer.shadowOpacity = Tuning.neonShadowOpacity
                layer.shadowOffset = .zero
                layer.frame = overlayView.bounds
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                overlayView.layer.addSublayer(layer)
                neonOverlay = layer
            } else {
                neonOverlay?.shadowColor = inkColor.cgColor
            }
        } else {
            neonOverlay?.removeFromSuperlayer()
            neonOverlay = nil
        }
    }

    // MARK: - Ink Trail Fade

    private func addTrailSegment(from start: CGPoint, to end: CGPoint) {
        guard !shouldSuppressAnimations else { return }

        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let segLayer = CAShapeLayer()
        segLayer.path = path
        segLayer.strokeColor = inkColor.withAlphaComponent(Tuning.trailStartOpacity).cgColor
        segLayer.fillColor = UIColor.clear.cgColor
        segLayer.lineWidth = Tuning.trailLineWidth
        segLayer.lineCap = .round
        overlayView.layer.addSublayer(segLayer)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = Tuning.trailMaxAge
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        segLayer.add(fade, forKey: "trailFade")

        trailSegments.append((path: path, layer: segLayer, born: CACurrentMediaTime()))
    }

    private func pruneExpiredTrailSegments() {
        let now = CACurrentMediaTime()
        trailSegments.removeAll { entry in
            if now - entry.born > Tuning.trailMaxAge {
                entry.layer.removeFromSuperlayer()
                return true
            }
            return false
        }
    }

    private func schedulePruneTimer() {
        guard pruneTimer == nil else { return }
        pruneTimer = Timer.scheduledTimer(
            withTimeInterval: Tuning.trailPruneInterval,
            repeats: true
        ) { [weak self] _ in
            self?.pruneExpiredTrailSegments()
        }
    }

    // MARK: - Gradient Ink Color

    /// Returns the ink colour to use for the current stroke point, accounting
    /// for the gradient-ink effect.
    ///
    /// When gradient ink is disabled, returns `inkColor` unchanged.  When
    /// enabled, interpolates between `gradientStartColor` and `gradientEndColor`
    /// based on the normalised `velocity` or `pressure` (as configured).
    ///
    /// - Parameters:
    ///   - velocity: Current nib speed in points/second.
    ///   - pressure: Current Apple Pencil pressure (0–1).
    /// - Returns: The colour to apply to the active `PKInkingTool`.
    func resolvedInkColor(velocity: CGFloat = 500, pressure: CGFloat = 1.0) -> UIColor {
        let cfg = effectiveConfig
        guard cfg.gradientInkEnabled else { return inkColor }

        let start = cfg.gradientStartColor
        let end   = cfg.gradientEndColor
        guard start.count == 4, end.count == 4 else { return inkColor }

        let t: CGFloat
        switch cfg.gradientSource {
        case .velocity:
            // Fast stroke → startColor, slow stroke → endColor
            t = 1.0 - min(velocity / Tuning.gradientVelocityCeiling, 1.0)
        case .pressure:
            // Light pressure → startColor, heavy pressure → endColor
            t = min(pressure, 1.0)
        }

        let r = CGFloat(start[0]) + t * (CGFloat(end[0]) - CGFloat(start[0]))
        let g = CGFloat(start[1]) + t * (CGFloat(end[1]) - CGFloat(start[1]))
        let b = CGFloat(start[2]) + t * (CGFloat(end[2]) - CGFloat(start[2]))
        let a = CGFloat(start[3]) + t * (CGFloat(end[3]) - CGFloat(start[3]))
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
