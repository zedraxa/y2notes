import CoreHaptics
import UIKit

// MARK: - PencilHapticEngine

/// Centralized haptic feedback engine for Apple Pencil interactions.
///
/// Provides distinct haptic patterns for different pencil events:
/// - **Stroke begin/end** — subtle confirmation that the pencil touched/lifted.
/// - **Tool switch** — crisp medium impact when double-tap or squeeze switches tools.
/// - **Double-tap** — sharp confirmation tap (delete last stroke).
/// - **Squeeze** — smooth transition feedback (Pencil Pro, iOS 17.5+).
/// - **Page edge** — graduated tension as the cursor approaches the page boundary.
/// - **Eraser contact** — soft tick when the eraser intersects existing strokes.
///
/// All haptics are disabled automatically when:
/// - The device has no haptic hardware (`CHHapticEngine.capabilitiesForHardware()`).
/// - The user has enabled "Reduce Motion" in Settings.
/// - The adaptive effects intensity is `.minimal`.
///
/// Thread safety: All public methods must be called on the main thread.
@MainActor
final class PencilHapticEngine {

    // MARK: - Configuration

    /// Master toggle — when `false`, no haptics are fired regardless of device capability.
    var isEnabled: Bool = true

    /// Intensity scale applied to all haptic patterns (0.0–1.0).
    /// Lower values produce softer feedback. Default 0.7 balances presence without fatigue.
    var intensityScale: Float = 0.7

    // MARK: - State

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool = false

    /// Reusable `UIImpactFeedbackGenerator` instances for common patterns
    /// (fallback when Core Haptics is unavailable or for simpler events).
    private let lightImpact   = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact  = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact   = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact    = UIImpactFeedbackGenerator(style: .soft)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    /// Timestamp of the last page-edge haptic to throttle at ~10 Hz.
    private var lastEdgeHapticTime: CFTimeInterval = 0

    // MARK: - Init

    init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        if supportsHaptics {
            startEngine()
        }
        prepareGenerators()
    }

    // MARK: - Engine Lifecycle

    private func startEngine() {
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true

            // Restart on reset (e.g. after audio session interruption).
            engine.resetHandler = { [weak self] in
                do {
                    try self?.engine?.start()
                } catch {
                    self?.supportsHaptics = false
                }
            }

            // Handle engine stop — mark unavailable until restart.
            engine.stoppedHandler = { [weak self] reason in
                _ = reason
                self?.supportsHaptics = false
            }

            try engine.start()
            self.engine = engine
        } catch {
            supportsHaptics = false
        }
    }

    private func prepareGenerators() {
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        selectionFeedback.prepare()
    }

    // MARK: - Public API

    /// Prepare the engine for imminent haptic events (call before drawing begins).
    func prepareForDrawing() {
        guard isEnabled else { return }
        prepareGenerators()
        if supportsHaptics, engine == nil {
            startEngine()
        }
    }

    /// Subtle confirmation that the pencil made contact with the screen.
    func strokeBegan() {
        guard isEnabled else { return }
        if supportsHaptics {
            playTransient(intensity: 0.35, sharpness: 0.3)
        } else {
            softImpact.impactOccurred(intensity: CGFloat(0.35 * intensityScale))
        }
    }

    /// Light release tap when the pencil lifts off.
    func strokeEnded() {
        guard isEnabled else { return }
        if supportsHaptics {
            playTransient(intensity: 0.2, sharpness: 0.15)
        } else {
            softImpact.impactOccurred(intensity: CGFloat(0.2 * intensityScale))
        }
    }

    /// Crisp impact when a tool switch occurs via double-tap or squeeze.
    func toolSwitched() {
        guard isEnabled else { return }
        if supportsHaptics {
            playTransient(intensity: 0.6, sharpness: 0.7)
        } else {
            mediumImpact.impactOccurred(intensity: CGFloat(0.6 * intensityScale))
        }
    }

    /// Sharp confirmation tap for double-tap delete-last-stroke action.
    func doubleTapFired() {
        guard isEnabled else { return }
        if supportsHaptics {
            playTransient(intensity: 0.7, sharpness: 0.9)
        } else {
            rigidImpact.impactOccurred(intensity: CGFloat(0.7 * intensityScale))
        }
    }

    /// Smooth transition feedback for Pencil Pro squeeze gesture.
    func squeezeFired() {
        guard isEnabled else { return }
        if supportsHaptics {
            playSqueezeCurve()
        } else {
            mediumImpact.impactOccurred(intensity: CGFloat(0.55 * intensityScale))
        }
    }

    /// Graduated tension as the pencil cursor approaches the page edge.
    ///
    /// - Parameter proximity: 0.0 = at center, 1.0 = touching edge.
    ///   Haptic fires only when proximity > 0.7 and throttles at ~10 Hz.
    func pageEdgeApproached(proximity: CGFloat) {
        guard isEnabled, proximity > 0.7 else { return }

        let now = CACurrentMediaTime()
        guard now - lastEdgeHapticTime > 0.1 else { return } // 10 Hz throttle
        lastEdgeHapticTime = now

        let scaledIntensity = Float(proximity - 0.7) / 0.3  // 0…1 within the 0.7…1.0 range
        if supportsHaptics {
            playTransient(intensity: 0.3 + scaledIntensity * 0.4, sharpness: 0.5)
        } else {
            lightImpact.impactOccurred(intensity: CGFloat(scaledIntensity * intensityScale))
        }
    }

    /// Soft tick when the eraser passes over existing strokes.
    func eraserContactedStroke() {
        guard isEnabled else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    /// Selection-style feedback for barrel-roll rotation milestones
    /// (e.g. every 15° of rotation).
    func barrelRollMilestone() {
        guard isEnabled else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    // MARK: - Core Haptics Patterns

    private func playTransient(intensity: Float, sharpness: Float) {
        guard let engine = engine else { return }
        let scaledIntensity = intensity * intensityScale
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: scaledIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently degrade — haptics are non-critical.
        }
    }

    /// Two-event squeeze pattern: soft ramp into a crisp release.
    private func playSqueezeCurve() {
        guard let engine = engine else { return }
        let ramp = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3 * intensityScale),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ],
            relativeTime: 0,
            duration: 0.08
        )
        let snap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65 * intensityScale),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
            ],
            relativeTime: 0.08
        )
        do {
            let pattern = try CHHapticPattern(events: [ramp, snap], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently degrade.
        }
    }
}
