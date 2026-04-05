import CoreHaptics
import UIKit

// MARK: - PencilHapticEngine

/// Plays subtle CoreHaptics feedback events tied to Apple Pencil hover proximity.
///
/// Three tiers of feedback are provided:
/// * `hoverBegan()` / `hoverEnded()` — soft pulses that bracket a hover session.
/// * Altitude-threshold ticks fired from `updateAltitude(_:)` — a distinct
///   "nearly touching" click when the pencil descends below ~20° and a gentle
///   release tick when it rises back above ~45°.
///
/// All calls are no-ops when haptic hardware is unavailable (older devices or
/// the Simulator), so no guard-checks are needed at the call site.
final class PencilHapticEngine {

    // MARK: - Private state

    private var engine: CHHapticEngine?
    private let isSupported: Bool

    /// Altitude bucket last signalled to the engine.
    /// 0 = approaching (< ~20°), 1 = near (< ~45°), 2 = far (≥ ~45°), −1 = none.
    private var lastAltitudeBucket: Int = -1

    // MARK: - Init

    init() {
        isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard isSupported else { return }
        do {
            let eng = try CHHapticEngine()
            engine = eng
            try eng.start()
            eng.resetHandler = { [weak eng] in
                try? eng?.start()
            }
            eng.stoppedHandler = { [weak eng] reason in
                if reason != .engineDestroyed { try? eng?.start() }
            }
        } catch {
            // Haptics initialisation failed — all calls will be no-ops.
        }
    }

    // MARK: - Public API

    /// Soft pulse played when the pencil enters the hover range.
    func hoverBegan() {
        lastAltitudeBucket = -1
        play(intensity: 0.25, sharpness: 0.10, duration: 0.04)
    }

    /// Very gentle pulse played when the pencil leaves the hover range.
    func hoverEnded() {
        lastAltitudeBucket = -1
        play(intensity: 0.15, sharpness: 0.05, duration: 0.03)
    }

    /// Update altitude tier and fire a haptic tick when the pencil crosses a
    /// proximity threshold.
    ///
    /// - Parameter altitude: Pencil altitude in radians (0 = flat, π/2 = perpendicular).
    func updateAltitude(_ altitude: CGFloat) {
        let nearThreshold: CGFloat = .pi / 9   // ~20° — almost touching
        let farThreshold:  CGFloat = .pi / 4   // ~45° — within hover range
        let newBucket: Int = altitude < nearThreshold ? 0
                           : altitude < farThreshold  ? 1
                           :                            2

        guard newBucket != lastAltitudeBucket else { return }
        defer { lastAltitudeBucket = newBucket }

        switch (lastAltitudeBucket, newBucket) {
        case (_, 0):
            // Pencil nearly touching — sharper approach tick.
            play(intensity: 0.45, sharpness: 0.70, duration: 0.03)
        case (0, _):
            // Lifted back from near range — soft release tick.
            play(intensity: 0.20, sharpness: 0.30, duration: 0.025)
        default:
            break
        }
    }

    // MARK: - Private

    private func play(intensity: Float, sharpness: Float, duration: TimeInterval) {
        guard let engine else { return }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [i, s],
            relativeTime: 0,
            duration: duration
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player  = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Pattern playback failed — silently skip.
        }
    }
}
