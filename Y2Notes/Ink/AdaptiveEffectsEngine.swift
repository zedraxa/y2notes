import UIKit
import Combine

// MARK: - Effect Intensity

/// Describes the current intensity level for visual effects.
///
/// The adaptive engine continuously evaluates contextual signals — writing
/// velocity, canvas zoom, battery state, and notebook complexity — and
/// publishes one of these levels.  Every effect subsystem consults
/// `EffectIntensity` before committing GPU work.
///
/// **Graceful degradation contract**
/// - `.full`    → all effects play at authored fidelity
/// - `.reduced` → advanced writing effects and ambient animations disabled;
///                micro-interactions still fire but with shorter durations
/// - `.minimal` → only essential selection / deselection feedback; all
///                decorative effects suppressed
enum EffectIntensity: Int, Comparable, CaseIterable {
    case minimal  = 0
    case reduced  = 1
    case full     = 2

    static func < (lhs: EffectIntensity, rhs: EffectIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Duration multiplier applied to micro-interaction animations.
    /// Shorter = snappier under load.
    var durationMultiplier: Double {
        switch self {
        case .full:    return 1.0
        case .reduced: return 0.6
        case .minimal: return 0.0
        }
    }

    /// Whether advanced writing effects (glow pen, neon ink, etc.) should run.
    var allowsAdvancedWritingEffects: Bool { self >= .full }

    /// Whether ambient environment animations (rain, grain drift) should run.
    var allowsAmbientAnimations: Bool { self >= .full }

    /// Whether snap-align visual effects (glow, flash) should run.
    /// Haptic feedback is unaffected.
    var allowsSnapAlignVisuals: Bool { self >= .reduced }

    /// Whether page-turn physics (inertia, bend) should run.
    /// Cross-fade fallback is used at `.reduced` and below.
    var allowsPageTurnPhysics: Bool { self >= .full }

    /// Whether focus-mode decorative overlays (vignette, paper glow) should run.
    var allowsFocusModeOverlays: Bool { self >= .reduced }

    /// Whether micro-interaction animations (scale, shadow, bounce) should run.
    var allowsMicroInteractions: Bool { self >= .reduced }
}

// MARK: - Adaptive Effects Engine

/// Central coordinator that computes a live `EffectIntensity` from contextual
/// signals and publishes it to all effect subsystems.
///
/// **Signals evaluated (in priority order):**
/// 1. **Low-power mode** — reduces to `.reduced` or `.minimal`
/// 2. **Canvas zoom** — zoomed out past 0.5× disables heavy effects
/// 3. **Writing velocity** — fast strokes reduce effects to avoid interference
/// 4. **Notebook complexity** — large page counts or high stroke counts simplify
///
/// **Performance contract**: evaluation runs on main thread, takes < 0.05 ms
/// (three float comparisons + one enum write).  Published via Combine for
/// SwiftUI observation or direct reads.
///
/// **Budget**: 0.1 ms setup, zero steady-state CPU (reactive to input only).
@MainActor
final class AdaptiveEffectsEngine: ObservableObject {

    // MARK: - Published State

    /// The current computed effect intensity.  All effect engines should
    /// consult this value before committing GPU work.
    @Published private(set) var intensity: EffectIntensity = .full

    // MARK: - Input Signals

    /// Current canvas zoom scale (1.0 = 100 %).  Updated by the editor
    /// coordinator whenever `scrollViewDidZoom` fires.
    var zoomScale: CGFloat = 1.0 {
        didSet { reevaluate() }
    }

    /// Exponentially smoothed stroke velocity (strokes per second).
    /// Updated each time `canvasViewDrawingDidChange` fires.
    private var smoothedStrokeRate: Double = 0.0

    /// Total page count of the active notebook.
    var pageCount: Int = 1 {
        didSet { reevaluate() }
    }

    /// Total stroke count on the current page.
    var currentPageStrokeCount: Int = 0 {
        didSet { reevaluate() }
    }

    /// Whether the system is in Low Power Mode.
    private var isLowPowerMode: Bool = false {
        didSet { reevaluate() }
    }

    // MARK: - Thresholds

    private enum Thresholds {
        /// Zoom scale below which heavy effects are disabled.
        static let zoomOutCutoff: CGFloat = 0.5

        /// Zoom scale below which ALL decorative effects are disabled.
        static let zoomOutMinimal: CGFloat = 0.3

        /// Strokes-per-second above which effects are reduced.
        static let fastWritingRate: Double = 4.0

        /// Strokes-per-second above which effects go minimal.
        static let veryFastWritingRate: Double = 8.0

        /// Page count above which notebook is considered "large".
        static let largeNotebookPages: Int = 50

        /// Stroke count above which current page is considered "complex".
        static let complexPageStrokes: Int = 1500

        /// Smoothing factor for exponential moving average (0–1).
        /// Lower = smoother / slower to react.
        static let velocitySmoothingAlpha: Double = 0.3
    }

    // MARK: - Stroke Timing

    private var lastStrokeTimestamp: CFTimeInterval = 0

    // MARK: - Low Power Mode Observation

    private var powerStateObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    deinit {
        if let observer = powerStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Stroke Velocity Tracking

    /// Call each time a stroke change is detected (from `canvasViewDrawingDidChange`).
    /// Updates the exponentially smoothed stroke rate.
    func reportStrokeChange() {
        let now = CACurrentMediaTime()
        if lastStrokeTimestamp > 0 {
            let interval = now - lastStrokeTimestamp
            if interval > 0 && interval < 5.0 {  // ignore gaps > 5 s (user paused)
                let instantRate = 1.0 / interval
                let alpha = Thresholds.velocitySmoothingAlpha
                smoothedStrokeRate = alpha * instantRate + (1.0 - alpha) * smoothedStrokeRate
            }
        } else {
            smoothedStrokeRate = 0
        }
        lastStrokeTimestamp = now
        reevaluate()
    }

    /// Call when the user lifts the pencil or pauses.  Decays the smoothed
    /// rate toward zero so effects restore after a pause.
    func reportStrokePause() {
        smoothedStrokeRate *= 0.5
        reevaluate()
    }

    // MARK: - Evaluation

    /// Recomputes `intensity` from all current signals.
    ///
    /// Priority order (highest priority wins lowest intensity):
    /// 1. Low-power mode
    /// 2. Extreme zoom-out
    /// 3. Very fast writing
    /// 4. Large notebook / complex page
    /// 5. Moderate zoom-out or fast writing
    private func reevaluate() {
        var proposed: EffectIntensity = .full

        // 1. Low-power mode — at least `.reduced`
        if isLowPowerMode {
            proposed = min(proposed, .reduced)
        }

        // 2. Extreme zoom-out → minimal
        if zoomScale < Thresholds.zoomOutMinimal {
            proposed = min(proposed, .minimal)
        } else if zoomScale < Thresholds.zoomOutCutoff {
            proposed = min(proposed, .reduced)
        }

        // 3. Writing velocity
        if smoothedStrokeRate > Thresholds.veryFastWritingRate {
            proposed = min(proposed, .minimal)
        } else if smoothedStrokeRate > Thresholds.fastWritingRate {
            proposed = min(proposed, .reduced)
        }

        // 4. Notebook complexity
        if pageCount > Thresholds.largeNotebookPages
            && currentPageStrokeCount > Thresholds.complexPageStrokes {
            proposed = min(proposed, .minimal)
        } else if pageCount > Thresholds.largeNotebookPages
                    || currentPageStrokeCount > Thresholds.complexPageStrokes {
            proposed = min(proposed, .reduced)
        }

        // Only publish when the value actually changes to avoid unnecessary
        // SwiftUI / Combine traffic.
        if proposed != intensity {
            intensity = proposed
        }
    }
}
