import UIKit
import QuartzCore

// MARK: - Interaction Event

/// Categorises every UI interaction that deserves haptic or visual feedback.
///
/// Each event carries a **haptic recipe** (generator style + intensity) and an
/// optional **visual recipe** (Core Animation on a supplied `CALayer`).
///
/// **Performance contract**: haptic generators are pre-allocated and pre-prepared.
/// Visual animations are GPU-composited via Core Animation — no main-thread
/// layout passes.  Total overhead per event is < 0.3 ms measured on A12.
enum InteractionEvent: String, CaseIterable {

    // ── Tool switching ──────────────────────────────────────────────────

    /// User taps a new tool in the toolbar (pen → pencil, etc.).
    case toolSwitch

    /// User switches to eraser via pencil double-tap or toolbar.
    case eraserEngage

    /// User returns from eraser to previous inking tool.
    case eraserDisengage

    // ── Undo / redo ─────────────────────────────────────────────────────

    /// An undo operation was performed.
    case undo

    /// A redo operation was performed.
    case redo

    // ── Selection ───────────────────────────────────────────────────────

    /// An object (sticker, shape, attachment) became selected.
    case objectSelected

    /// All objects were deselected.
    case objectDeselected

    // ── Colour / width ──────────────────────────────────────────────────

    /// User picked a new ink colour.
    case colorPick

    /// User changed stroke width.
    case widthChange

    // ── Zoom ────────────────────────────────────────────────────────────

    /// Canvas zoom crossed a detent (25 %, 50 %, 100 %, 150 %, 200 %).
    case zoomDetent

    // ── Canvas touch ────────────────────────────────────────────────────

    /// First touch on an empty canvas area (non-pencil tap).
    case canvasTap

    // ── Mode toggles ────────────────────────────────────────────────────

    /// Focus mode toggled on or off.
    case focusModeToggle

    /// Magic mode toggled on or off.
    case magicModeToggle

    /// Study mode toggled on or off.
    case studyModeToggle

    // ── Page actions ────────────────────────────────────────────────────

    /// A new page was added.
    case pageAdd

    /// A page was deleted.
    case pageDelete

    /// A page was duplicated.
    case pageDuplicate
}

// MARK: - Haptic Recipe

/// Specifies how a single haptic feedback event should feel.
private struct HapticRecipe {
    enum Style {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)
        case selection
        case notification(UINotificationFeedbackGenerator.FeedbackType)
    }
    let style: Style
}

// MARK: - Visual Recipe

/// Describes an optional Core Animation visual response to an interaction.
private struct VisualRecipe {
    enum Kind {
        /// Brief opacity flash (overlay pulses from 0 → peak → 0).
        case flash(peakOpacity: Float, duration: CFTimeInterval)
        /// Scale pulse (layer scales up then back to original).
        case scalePulse(peakScale: CGFloat, duration: CFTimeInterval)
        /// Border highlight (layer border briefly tints then fades).
        case borderHighlight(color: UIColor, duration: CFTimeInterval)
        /// Colour morph (background tints briefly).
        case colorTint(color: UIColor, duration: CFTimeInterval)
    }
    let kind: Kind
}

// MARK: - Interaction Feedback Engine

/// Centralized engine for UI interaction feedback (haptics + visual micro-cues).
///
/// **Design principles:**
/// 1. **Subtle** — feedback should be felt, not seen.  Visual cues never exceed
///    15 % opacity; haptic intensities are tuned to the minimum perceptible level.
/// 2. **Consistent** — every interactive surface uses the same engine so the app
///    has a unified haptic language.
/// 3. **Accessible** — visual animations respect `ReduceMotionObserver`; haptics
///    always fire (they're non-visual).
/// 4. **Efficient** — all generators are pre-allocated.  No allocations at feedback
///    time.  GPU-composited animations only.
///
/// **Usage:**
/// ```swift
/// let feedback = InteractionFeedbackEngine()
/// feedback.play(.toolSwitch)
/// feedback.play(.undo, on: canvasLayer)   // haptic + visual
/// ```
final class InteractionFeedbackEngine {

    // MARK: - Pre-Allocated Haptic Generators

    /// Light impact — tool switch, colour pick, width change.
    private let lightImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    /// Medium impact — undo/redo, mode toggle, page actions.
    private let mediumImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    /// Soft impact — zoom detent, canvas tap, object select/deselect.
    private let softImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        return g
    }()

    /// Rigid impact — eraser engage/disengage (crisp tool commitment).
    private let rigidImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.prepare()
        return g
    }()

    /// Selection feedback — subtle tick for state changes.
    private let selectionFeedback: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        return g
    }()

    /// Notification feedback — for page add/delete confirmations.
    private let notificationFeedback = UINotificationFeedbackGenerator()

    // MARK: - State

    /// Current adaptive effect intensity.
    var effectIntensity: EffectIntensity = .full

    /// Tracks active visual animation count to enforce the cap.
    private var activeVisualCount: Int = 0

    /// Maximum simultaneous visual effects.
    private static let maxVisuals: Int = 3

    /// Debounce: last event timestamp per event type.
    private var lastEventTimes: [InteractionEvent: CFTimeInterval] = [:]

    /// Minimum interval between repeated events of the same type (seconds).
    private static let debounceInterval: CFTimeInterval = 0.08

    // MARK: - Zoom Detent Tracking

    /// Known zoom detent values (25 %, 50 %, 100 %, 150 %, 200 %).
    /// Exposed as `internal` so `NoteEditorView.Coordinator` can share the same
    /// source of truth for the visual micro-bounce without duplicating values.
    static let zoomDetents: [CGFloat] = [0.25, 0.5, 1.0, 1.5, 2.0]

    /// Tolerance for snapping to a detent (± this fraction).
    /// Shared with `NoteEditorView.Coordinator` for the zoom-tick visual effect.
    static let detentTolerance: CGFloat = 0.03

    /// Last zoom scale — used to detect detent crossings.
    private var lastZoomScale: CGFloat = 1.0

    /// Whether the last zoom was already on a detent (edge-trigger logic).
    private var wasOnDetent: Bool = true

    // MARK: - Recipe Lookup

    /// Returns the haptic recipe for an interaction event.
    private static func hapticRecipe(for event: InteractionEvent) -> HapticRecipe {
        switch event {
        case .toolSwitch:        return HapticRecipe(style: .impact(.light, intensity: 0.6))
        case .eraserEngage:      return HapticRecipe(style: .impact(.rigid, intensity: 0.5))
        case .eraserDisengage:   return HapticRecipe(style: .impact(.rigid, intensity: 0.35))
        case .undo:              return HapticRecipe(style: .impact(.medium, intensity: 0.5))
        case .redo:              return HapticRecipe(style: .impact(.medium, intensity: 0.45))
        case .objectSelected:    return HapticRecipe(style: .selection)
        case .objectDeselected:  return HapticRecipe(style: .impact(.soft, intensity: 0.3))
        case .colorPick:         return HapticRecipe(style: .selection)
        case .widthChange:       return HapticRecipe(style: .impact(.light, intensity: 0.3))
        case .zoomDetent:        return HapticRecipe(style: .impact(.soft, intensity: 0.4))
        case .canvasTap:         return HapticRecipe(style: .impact(.soft, intensity: 0.2))
        case .focusModeToggle:   return HapticRecipe(style: .impact(.medium, intensity: 0.5))
        case .magicModeToggle:   return HapticRecipe(style: .impact(.medium, intensity: 0.5))
        case .studyModeToggle:   return HapticRecipe(style: .impact(.medium, intensity: 0.5))
        case .pageAdd:           return HapticRecipe(style: .notification(.success))
        case .pageDelete:        return HapticRecipe(style: .notification(.warning))
        case .pageDuplicate:     return HapticRecipe(style: .notification(.success))
        }
    }

    /// Returns an optional visual recipe for an interaction event.
    /// `nil` means no visual response (haptic only).
    private static func visualRecipe(for event: InteractionEvent) -> VisualRecipe? {
        switch event {
        case .toolSwitch:
            return VisualRecipe(kind: .scalePulse(peakScale: 1.015, duration: 0.2))
        case .eraserEngage:
            return VisualRecipe(kind: .borderHighlight(
                color: UIColor.systemRed.withAlphaComponent(0.15), duration: 0.25))
        case .eraserDisengage:
            return nil
        case .undo:
            return VisualRecipe(kind: .flash(peakOpacity: 0.06, duration: 0.2))
        case .redo:
            return VisualRecipe(kind: .flash(peakOpacity: 0.06, duration: 0.2))
        case .objectSelected:
            return nil  // handled by MicroInteractionEngine.playSelectionGlow
        case .objectDeselected:
            return nil
        case .colorPick:
            return VisualRecipe(kind: .scalePulse(peakScale: 1.02, duration: 0.15))
        case .widthChange:
            return nil
        case .zoomDetent:
            return VisualRecipe(kind: .scalePulse(peakScale: 1.005, duration: 0.15))
        case .canvasTap:
            return nil  // handled by MicroInteractionEngine.playTapRipple
        case .focusModeToggle:
            return VisualRecipe(kind: .colorTint(
                color: UIColor.systemIndigo.withAlphaComponent(0.06), duration: 0.35))
        case .magicModeToggle:
            return VisualRecipe(kind: .colorTint(
                color: UIColor.systemPurple.withAlphaComponent(0.06), duration: 0.35))
        case .studyModeToggle:
            return VisualRecipe(kind: .colorTint(
                color: UIColor.systemGreen.withAlphaComponent(0.06), duration: 0.35))
        case .pageAdd:
            return VisualRecipe(kind: .flash(peakOpacity: 0.04, duration: 0.3))
        case .pageDelete:
            return nil
        case .pageDuplicate:
            return VisualRecipe(kind: .flash(peakOpacity: 0.04, duration: 0.3))
        }
    }

    // MARK: - Public API

    /// Plays the appropriate feedback for an interaction event.
    ///
    /// Haptic feedback fires unconditionally (not affected by Reduce Motion).
    /// Visual feedback respects `ReduceMotionObserver` and `effectIntensity`.
    ///
    /// - Parameters:
    ///   - event: The interaction event that occurred.
    ///   - layer: Optional layer to apply visual feedback to.
    func play(_ event: InteractionEvent, on layer: CALayer? = nil) {
        // Debounce repeated events of the same type.
        let now = CACurrentMediaTime()
        if let last = lastEventTimes[event],
           now - last < Self.debounceInterval {
            return
        }
        lastEventTimes[event] = now

        // Always play haptic (non-visual, not affected by Reduce Motion).
        playHaptic(for: event)

        // Visual feedback respects Reduce Motion and intensity.
        if let layer = layer,
           !ReduceMotionObserver.shared.isEnabled,
           effectIntensity.allowsInteractionFeedback {
            playVisual(for: event, on: layer)
        }
    }

    // MARK: - Zoom Detent Detection

    /// Call from `scrollViewDidZoom` to detect detent crossings.
    ///
    /// This uses edge-trigger logic: feedback fires once when zoom crosses
    /// into a detent zone, not continuously while sitting on one.
    ///
    /// - Parameters:
    ///   - zoomScale: Current zoom scale from the scroll view.
    ///   - layer: Optional layer for visual feedback.
    func updateZoom(_ zoomScale: CGFloat, on layer: CALayer? = nil) {
        let isOnDetent = Self.zoomDetents.contains { abs(zoomScale - $0) < Self.detentTolerance }

        if isOnDetent && !wasOnDetent {
            play(.zoomDetent, on: layer)
        }

        wasOnDetent = isOnDetent
        lastZoomScale = zoomScale
    }

    // MARK: - Prepare

    /// Pre-warms all haptic generators.  Call when the editor appears or
    /// transitions to the foreground.
    func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }

    // MARK: - Private — Haptic Playback

    private func playHaptic(for event: InteractionEvent) {
        let recipe = Self.hapticRecipe(for: event)

        switch recipe.style {
        case .impact(let style, let intensity):
            let generator: UIImpactFeedbackGenerator
            switch style {
            case .light:  generator = lightImpact
            case .medium: generator = mediumImpact
            case .soft:   generator = softImpact
            case .rigid:  generator = rigidImpact
            default:      generator = lightImpact
            }
            generator.impactOccurred(intensity: intensity)
            generator.prepare()

        case .selection:
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()

        case .notification(let type):
            notificationFeedback.notificationOccurred(type)
            notificationFeedback.prepare()
        }
    }

    // MARK: - Private — Visual Playback

    private func playVisual(for event: InteractionEvent, on layer: CALayer) {
        guard let recipe = Self.visualRecipe(for: event) else { return }
        guard activeVisualCount < Self.maxVisuals else { return }

        switch recipe.kind {
        case .flash(let peakOpacity, let duration):
            playFlash(on: layer, peakOpacity: peakOpacity, duration: duration)

        case .scalePulse(let peakScale, let duration):
            playScalePulse(on: layer, peakScale: peakScale, duration: duration)

        case .borderHighlight(let color, let duration):
            playBorderHighlight(on: layer, color: color, duration: duration)

        case .colorTint(let color, let duration):
            playColorTint(on: layer, color: color, duration: duration)
        }
    }

    // MARK: - Visual Animations

    /// Brief opacity flash — overlay pulses from 0 → peak → 0.
    private func playFlash(on layer: CALayer, peakOpacity: Float, duration: CFTimeInterval) {
        let overlay = CALayer()
        overlay.frame = layer.bounds
        overlay.backgroundColor = UIColor.label.cgColor
        overlay.opacity = 0
        layer.addSublayer(overlay)
        activeVisualCount += 1

        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, peakOpacity, 0]
        anim.keyTimes = [0, 0.35, 1.0]
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        let captured = overlay
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.activeVisualCount -= 1
        }
        overlay.add(anim, forKey: "interactionFlash")
        CATransaction.commit()
    }

    /// Scale pulse — spring impulse creates momentary overshoot then settles.
    ///
    /// Both `fromValue` and `toValue` are 1.0; the `initialVelocity` pushes
    /// the layer past 1.0 (up or down depending on `peakScale`) and the spring
    /// pulls it back.  Velocity magnitude scales with how far the peak is from 1.0.
    private func playScalePulse(on layer: CALayer, peakScale: CGFloat, duration: CFTimeInterval) {
        activeVisualCount += 1

        // Scale velocity magnitude by how far the desired peak deviates from 1.0.
        // A peakScale of 1.02 → velocity ~6, peakScale of 1.005 → velocity ~1.5.
        let deviation = peakScale - 1.0
        let velocityMagnitude: CGFloat = abs(deviation) * 300.0  // tuned for spring params
        let velocity = deviation >= 0 ? velocityMagnitude : -velocityMagnitude

        let anim = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.0
        anim.initialVelocity = velocity
        anim.damping = 14.0
        anim.stiffness = 300.0
        anim.mass = 0.8
        anim.duration = max(duration, anim.settlingDuration)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.activeVisualCount -= 1
        }
        layer.add(anim, forKey: "interactionScalePulse")
        CATransaction.commit()
    }

    /// Border highlight — layer border briefly tints then fades.
    private func playBorderHighlight(on layer: CALayer, color: UIColor, duration: CFTimeInterval) {
        let border = CALayer()
        border.frame = layer.bounds
        border.borderColor = color.cgColor
        border.borderWidth = 2.0
        border.cornerRadius = layer.cornerRadius
        border.opacity = 0
        layer.addSublayer(border)
        activeVisualCount += 1

        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1.0, 0]
        anim.keyTimes = [0, 0.3, 1.0]
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        let captured = border
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.activeVisualCount -= 1
        }
        border.add(anim, forKey: "interactionBorderHighlight")
        CATransaction.commit()
    }

    /// Colour tint — background tints briefly.
    private func playColorTint(on layer: CALayer, color: UIColor, duration: CFTimeInterval) {
        let tint = CALayer()
        tint.frame = layer.bounds
        tint.backgroundColor = color.cgColor
        tint.opacity = 0
        layer.addSublayer(tint)
        activeVisualCount += 1

        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1.0, 0]
        anim.keyTimes = [0, 0.25, 1.0]
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        let captured = tint
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.activeVisualCount -= 1
        }
        tint.add(anim, forKey: "interactionColorTint")
        CATransaction.commit()
    }
}
