import UIKit
import SwiftUI

// MARK: - EffectIntensity

/// Stub type representing the intensity tier for visual/haptic effects.
///
/// The full implementation was removed during Phase 4 cleanup. This stub
/// preserves API surface so call-sites compile while features are dormant.
enum EffectIntensity: Equatable {
    case full
    case reduced
    case minimal

    var allowsMagicMode: Bool { self == .full }
    var allowsPageTurnPhysics: Bool { self != .minimal }
}

// MARK: - EffectIntensityReceiver

/// Stub protocol for views that accept an effect-intensity setting.
protocol EffectIntensityReceiver: AnyObject {
    var effectIntensity: EffectIntensity { get set }
}

// MARK: - AmbientScene

/// Stub type for ambient environment scenes.
///
/// The `AmbientEnvironmentEngine` was removed during Phase 4 cleanup.
/// This enum preserves the type reference in `CanvasPageConfiguration`
/// and `DrawingToolStore` so they continue to compile.
enum AmbientScene: String, Codable, Equatable, CaseIterable {
    case rainStudy
    case lofiLight
    case nightGrain
}

// MARK: - WritingEffectConfig

/// Stub configuration for the writing-effects pipeline.
///
/// `WritingEffectModel.swift` was removed during Phase 4 cleanup.
/// This stub satisfies the `toolStoreRef?.writingEffectConfig ?? .default`
/// call-site in `CanvasCoordinator+DiffUpdate.swift`.
struct WritingEffectConfig: Codable, Equatable {
    static let `default` = WritingEffectConfig()
}

// MARK: - InteractionFeedbackEngine

/// Stub haptic feedback engine for tool-switch and eraser events.
///
/// `InteractionFeedbackEngine.swift` was removed during Phase 4 cleanup.
final class InteractionFeedbackEngine {
    enum Event {
        case eraserEngage
        case toolSwitch
    }

    func play(_ event: Event, on layer: CALayer) {}
}

// MARK: - MicroInteractionEngine

/// Stub micro-interaction engine for selection, drag, snap, and release animations.
///
/// `MicroInteractionEngine.swift` was removed during Phase 4 cleanup.
final class MicroInteractionEngine {
    var effectIntensity: EffectIntensity = .full

    func configureInteractionLayer(_ layer: CALayer) {}
    func hideInteractionLayer(_ layer: CALayer) {}
    func showInteractionLayer(_ layer: CALayer, for rect: CGRect) {}
    func playSelectScale(on layer: CALayer) {}
    func playSelectionGlow(on layer: CALayer) {}
    func playDeselectScale(on layer: CALayer) {}
    func playSnapBounce(on layer: CALayer) {}
    func playMomentumShadow(on layer: CALayer, velocity: CGPoint) {}
    func resetMomentumShadow(on layer: CALayer) {}
    func playReleaseBounce(on layer: CALayer) {}
    func playSoftShadow(on layer: CALayer, dragDirection: CGPoint) {}
    func resetSoftShadow(on layer: CALayer) {}
    func playToolSwitchMorph(on layer: CALayer) {}

    static func inertiaDecay(for speed: CGFloat) -> CGFloat { 0.95 }
}

// MARK: - SnapAlignEffectEngine

/// Stub snap-alignment effect engine for guide-line flash and haptic snap feedback.
///
/// `SnapAlignEffectEngine.swift` was removed during Phase 4 cleanup.
final class SnapAlignEffectEngine {
    var effectIntensity: EffectIntensity = .full

    func prepareHaptics() {}

    func playSnapFeedback(on layer: CALayer, snappedX: Bool, snappedY: Bool) {}

    func playLineGuideFlash(from start: CGPoint, to end: CGPoint, in layer: CALayer) {}

    func updatePerfectAlignment(isAligned: Bool) {}
}

// MARK: - PageTransitionDirection

/// Stub direction enum for page-transition animations.
///
/// `PageTransitionEngine.swift` was removed during Phase 4 cleanup.
enum PageTransitionDirection {
    case forward
    case backward
}

// MARK: - PageTransitionEngine

/// Stub page-transition animation engine.
///
/// `PageTransitionEngine.swift` was removed during Phase 4 cleanup. The stub
/// exposes the same static and instance API so callers in `CanvasViewCoordinator`
/// and `CanvasPageView` continue to compile.
final class PageTransitionEngine {
    var effectIntensity: EffectIntensity = .full

    func beginInteractiveDrag(
        on view: UIView,
        direction: PageTransitionDirection,
        pageWidth: CGFloat
    ) {}

    func updateInteractiveDrag(
        on view: UIView,
        translation: CGFloat,
        pageWidth: CGFloat
    ) {}

    func finishInteractiveDrag(
        on view: UIView,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        completion: @escaping (Bool) -> Void
    ) {
        completion(false)
    }

    func cancelInteractiveDrag(on view: UIView, completion: @escaping () -> Void) {
        completion()
    }

    static func playNewPageReveal(on layer: CALayer) {}
}

// MARK: - EffectsCoordinator

/// Stub effects coordinator for magic-mode and study-mode layer overlays.
///
/// `EffectsCoordinator.swift` was removed during Phase 4 cleanup.
final class EffectsCoordinator {
    func setMagicMode(active: Bool, on layer: CALayer) {}
    func setStudyMode(active: Bool, on layer: CALayer) {}
}

// MARK: - AmbientEnvironmentEngine

/// Stub ambient environment engine for scene activation and soundscape control.
///
/// `AmbientEnvironmentEngine.swift` was removed during Phase 4 cleanup.
final class AmbientEnvironmentEngine {
    var soundEnabled: Bool = true
    var activeScene: AmbientScene?

    func activate(_ scene: AmbientScene, on layer: CALayer, toolStore: DrawingToolStore) {}
    func deactivate(toolStore: DrawingToolStore) {}
    func updateLayout(containerBounds: CGRect) {}
}

// MARK: - AdaptiveEffectsEngine

/// Stub adaptive effects engine that scales visual complexity based on page count.
///
/// `AdaptiveEffectsEngine.swift` was removed during Phase 4 cleanup.
final class AdaptiveEffectsEngine {
    var pageCount: Int = 1
}

// MARK: - WritingEffectsPipeline

/// Stub writing-effects pipeline for pressure, pooling, and brush modulation.
///
/// `WritingEffectsPipeline.swift` was removed during Phase 4 cleanup.
final class WritingEffectsPipeline {
    func configure(config: WritingEffectConfig, color: UIColor) {}
}

// MARK: - InkEffectEngine

/// Stub ink-effect engine that drives `CAEmitterLayer`-based writing FX.
///
/// `InkEffectEngine.swift` was removed during Phase 4 cleanup.
final class InkEffectEngine {
    func syncLayerFrames() {}
    func configure(fx: WritingFXType, color: UIColor) {}
}

// MARK: - InkEffectPickerView

/// Stub SwiftUI sheet for browsing and selecting ink-effect presets.
///
/// `InkEffectPickerView.swift` was removed during Phase 4 cleanup. This stub
/// renders a placeholder so the toolbar button compiles without crashing.
struct InkEffectPickerView: View {
    var inkStore: InkEffectStore

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Ink Effects",
                systemImage: "wand.and.stars",
                description: Text("Ink effects are not available in this build.")
            )
            .navigationTitle("Ink Effects")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
