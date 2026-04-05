import UIKit
import Combine

// MARK: - Effects Coordinator

/// Central coordinator that owns all effect engines and keeps them in sync.
///
/// `EffectsCoordinator` replaces the manual wiring previously spread across
/// `NoteEditorView.updateUIView`.  It:
///
/// 1. **Instantiates** every effect engine once.
/// 2. **Distributes** `AdaptiveEffectsEngine.intensity` to all sub-engines
///    automatically via Combine — callers never distribute intensity manually.
/// 3. **Exposes** each engine through named properties for direct use by
///    `NoteEditorView.Coordinator` and canvas views.
///
/// **Usage in `NoteEditorView.Coordinator`:**
/// ```swift
/// let effects = EffectsCoordinator()
///
/// // Activate/deactivate modes:
/// effects.setMagicMode(active: true, on: canvasView.layer)
/// effects.setStudyMode(active: true, on: canvasView.layer)
///
/// // Update notebook complexity for adaptive gating:
/// effects.adaptiveEngine.pageCount = pageCount
/// effects.adaptiveEngine.currentPageStrokeCount = strokeCount
///
/// // Propagate intensity to canvas sub-views:
/// effects.applyIntensity(to: shapeCanvas, attachmentCanvas, widgetCanvas)
/// ```
final class EffectsCoordinator {

    // MARK: - Engines

    /// Evaluates context signals and publishes the current `EffectIntensity`.
    let adaptiveEngine = AdaptiveEffectsEngine()

    /// Physical page-turn effects.
    let pageTransitionEngine = PageTransitionEngine()

    /// Background dim / vignette when focus mode is active.
    let focusModeEngine = FocusModeEngine()

    /// Ambient mood scenes (rain, lo-fi, night grain).
    let ambientEngine = AmbientEnvironmentEngine()

    /// Writing particles, keyword glow, underline highlights.
    let magicModeEngine = MagicModeEngine()

    /// Heading recognition glow, checklist pulse, timer overlay.
    let studyModeEngine = StudyModeEngine()

    /// Core + advanced writing effects (glow pen, neon ink, ink trail, gradient ink).
    let writingEffectsPipeline = WritingEffectsPipeline()

    // MARK: - Private

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init() {
        // Automatically distribute intensity to all sub-engines when it changes.
        adaptiveEngine.$intensity
            .receive(on: RunLoop.main)
            .sink { [weak self] intensity in
                self?.distribute(intensity: intensity)
            }
            .store(in: &cancellables)
    }

    // MARK: - Intensity Distribution

    /// Propagates `intensity` to all engines owned by this coordinator.
    ///
    /// Also call with optional canvas view references to update their
    /// internal snap/micro engines.
    func distribute(
        intensity: EffectIntensity,
        shapeCanvas: (any EffectIntensityReceiver)? = nil,
        attachmentCanvas: (any EffectIntensityReceiver)? = nil,
        widgetCanvas: (any EffectIntensityReceiver)? = nil,
        stickerCanvas: (any EffectIntensityReceiver)? = nil
    ) {
        pageTransitionEngine.effectIntensity = intensity
        focusModeEngine.effectIntensity = intensity
        ambientEngine.effectIntensity = intensity
        magicModeEngine.effectIntensity = intensity
        studyModeEngine.effectIntensity = intensity
        writingEffectsPipeline.effectIntensity = intensity
        shapeCanvas?.effectIntensity = intensity
        attachmentCanvas?.effectIntensity = intensity
        widgetCanvas?.effectIntensity = intensity
        stickerCanvas?.effectIntensity = intensity
    }

    // MARK: - Mode Lifecycle

    /// Activates or deactivates magic mode on the given canvas layer.
    func setMagicMode(active: Bool, on layer: CALayer) {
        if active, !magicModeEngine.isActive {
            magicModeEngine.activate(on: layer)
        } else if !active, magicModeEngine.isActive {
            magicModeEngine.deactivate()
        }
    }

    /// Activates or deactivates study mode on the given canvas layer.
    func setStudyMode(active: Bool, on layer: CALayer) {
        if active, !studyModeEngine.isActive {
            studyModeEngine.activate(on: layer)
        } else if !active, studyModeEngine.isActive {
            studyModeEngine.deactivate()
        }
    }

    // MARK: - Layout Sync

    /// Forwards a layout update to all active, layout-sensitive engines.
    func updateLayout(containerBounds: CGRect) {
        if magicModeEngine.isActive {
            magicModeEngine.updateLayout(containerBounds: containerBounds)
        }
        if ambientEngine.activeScene != nil {
            ambientEngine.updateLayout(containerBounds: containerBounds)
        }
        if focusModeEngine.isActive {
            focusModeEngine.updateLayout(containerBounds: containerBounds)
        }
    }
}

// MARK: - Effect Intensity Receiver

/// Describes a canvas view that accepts an `EffectIntensity` update.
///
/// All four canvas overlay views (`ShapeCanvasView`, `AttachmentCanvasView`,
/// `WidgetCanvasView`, `StickerCanvasView`) satisfy this protocol through
/// their existing `effectIntensity` property.
protocol EffectIntensityReceiver: AnyObject {
    var effectIntensity: EffectIntensity { get set }
}
