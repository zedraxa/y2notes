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
public enum EffectIntensity: Int, Comparable, CaseIterable {
    case minimal  = 0
    case reduced  = 1
    case full     = 2

    public static func < (lhs: EffectIntensity, rhs: EffectIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Duration multiplier applied to micro-interaction animations.
    /// Shorter = snappier under load.
    public var durationMultiplier: Double {
        switch self {
        case .full:    return 1.0
        case .reduced: return 0.6
        case .minimal: return 0.0
        }
    }

    /// Whether advanced writing effects (glow pen, neon ink, etc.) should run.
    public var allowsAdvancedWritingEffects: Bool { self >= .full }

    /// Whether ambient environment animations (rain, grain drift) should run.
    public var allowsAmbientAnimations: Bool { self >= .full }

    /// Whether snap-align visual effects (glow, flash) should run.
    /// Haptic feedback is unaffected.
    public var allowsSnapAlignVisuals: Bool { self >= .reduced }

    /// Whether page-turn physics (inertia, bend) should run.
    /// Cross-fade fallback is used at `.reduced` and below.
    public var allowsPageTurnPhysics: Bool { self >= .full }

    /// Whether focus-mode decorative overlays (vignette, paper glow) should run.
    public var allowsFocusModeOverlays: Bool { self >= .reduced }

    /// Whether micro-interaction animations (scale, shadow, bounce) should run.
    public var allowsMicroInteractions: Bool { self >= .reduced }

    /// Whether magic-mode decorative effects (particles, glow, highlight) should run.
    public var allowsMagicMode: Bool { self >= .full }

    /// Whether study-mode feedback effects (heading glow, checklist pulse) should run.
    public var allowsStudyMode: Bool { self >= .reduced }

    /// Whether interaction feedback visuals (flash, scale pulse, border highlight) should run.
    /// Haptic feedback is unaffected — it always fires.
    public var allowsInteractionFeedback: Bool { self >= .reduced }
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
public final class AdaptiveEffectsEngine: ObservableObject {

    // MARK: - Published State

    /// The current computed effect intensity.  All effect engines should
    /// consult this value before committing GPU work.
    @Published public private(set) var intensity: EffectIntensity = .full

    // MARK: - Input Signals

    /// Current canvas zoom scale (1.0 = 100 %).  Updated by the editor
    /// coordinator whenever `scrollViewDidZoom` fires.
    public var zoomScale: CGFloat = 1.0 {
        didSet { reevaluate() }
    }

    /// Exponentially smoothed stroke velocity (strokes per second).
    /// Updated each time `canvasViewDrawingDidChange` fires.
    private var smoothedStrokeRate: Double = 0.0

    /// Total page count of the active notebook.
    public var pageCount: Int = 1 {
        didSet { reevaluate() }
    }

    /// Total stroke count on the current page.
    public var currentPageStrokeCount: Int = 0 {
        didSet { reevaluate() }
    }

    /// Whether the system is in Low Power Mode.
    private var isLowPowerMode: Bool = false {
        didSet { reevaluate() }
    }

    /// Current thermal state of the device.  Updated via notification.
    private var thermalState: ProcessInfo.ThermalState = .nominal {
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

        /// Thermal state at which effects begin reducing.
        /// `.fair` means the device is warm but not throttling yet.
        static let thermalReduceState: ProcessInfo.ThermalState = .fair

        /// Thermal state at which effects go minimal.
        /// `.serious` means the device is approaching throttling.
        static let thermalMinimalState: ProcessInfo.ThermalState = .serious
    }

    // MARK: - Stroke Timing

    private var lastStrokeTimestamp: CFTimeInterval = 0

    // MARK: - Low Power Mode & Thermal State Observation

    private var powerStateObserver: NSObjectProtocol?
    private var thermalStateObserver: NSObjectProtocol?

    // MARK: - Init

    public init() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState

        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }

        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.thermalState = ProcessInfo.processInfo.thermalState
            }
        }
    }

    deinit {
        if let observer = powerStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Stroke Velocity Tracking

    /// Call each time a stroke change is detected (from `canvasViewDrawingDidChange`).
    /// Updates the exponentially smoothed stroke rate.
    public func reportStrokeChange() {
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
    public func reportStrokePause() {
        smoothedStrokeRate *= 0.5
        reevaluate()
    }

    // MARK: - Evaluation

    /// Recomputes `intensity` from all current signals.
    ///
    /// Priority order (highest priority wins lowest intensity):
    /// 1. Thermal state (device overheating)
    /// 2. Low-power mode
    /// 3. Extreme zoom-out
    /// 4. Very fast writing
    /// 5. Large notebook / complex page
    /// 6. Moderate zoom-out or fast writing
    private func reevaluate() {
        var proposed: EffectIntensity = .full

        // 1. Thermal state — highest priority; critical thermal → minimal
        if thermalState.rawValue >= Thresholds.thermalMinimalState.rawValue {
            proposed = min(proposed, .minimal)
        } else if thermalState.rawValue >= Thresholds.thermalReduceState.rawValue {
            proposed = min(proposed, .reduced)
        }

        // 2. Low-power mode — at least `.reduced`
        if isLowPowerMode {
            proposed = min(proposed, .reduced)
        }

        // 3. Extreme zoom-out → minimal
        if zoomScale < Thresholds.zoomOutMinimal {
            proposed = min(proposed, .minimal)
        } else if zoomScale < Thresholds.zoomOutCutoff {
            proposed = min(proposed, .reduced)
        }

        // 4. Writing velocity
        if smoothedStrokeRate > Thresholds.veryFastWritingRate {
            proposed = min(proposed, .minimal)
        } else if smoothedStrokeRate > Thresholds.fastWritingRate {
            proposed = min(proposed, .reduced)
        }

        // 5. Notebook complexity
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
