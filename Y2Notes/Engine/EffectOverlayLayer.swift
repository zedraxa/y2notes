import UIKit
import QuartzCore
import os

// MARK: - EffectOverlayLayer

/// Manages the non-interactive overlay view that hosts ink-effect visuals
/// (particle emitters, shape animations, gradient glow layers) above the
/// PencilKit canvas.
///
/// ## Lifecycle
/// - Call `install(in:)` once to add the overlay to the canvas container.
/// - Call `activate(with:)` when an ink effect becomes active.
/// - Call `deactivate()` when effects should be hidden (zero layer cost).
/// - Call `remove()` when the canvas controller is torn down.
///
/// ## Layer Hierarchy
/// ```
/// containerView
/// ├── PKCanvasView (drawing input)
/// └── effectOverlayView (this layer — non-interactive, passthrough)
///     ├── CAEmitterLayer (particles)
///     ├── CAShapeLayer (ripple / lightning)
///     └── CAGradientLayer (glow auras)
/// ```
///
/// **Thread safety**: all methods must be called on the main thread.
final class EffectOverlayLayer {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.y2notes", category: "EffectOverlayLayer")

    /// The overlay view that hosts all effect sublayers.
    /// `isUserInteractionEnabled = false` so touches pass through to the canvas.
    private(set) var overlayView: UIView?

    /// The currently active effect type. `.none` means the overlay is hidden.
    private(set) var activeEffect: WritingFXType = .none

    /// Whether the overlay is currently installed in a container.
    var isInstalled: Bool { overlayView?.superview != nil }

    /// Whether the overlay is currently showing effects.
    var isActive: Bool { activeEffect != .none }

    // MARK: - Installation

    /// Install the overlay view into the given container, positioned above the canvas.
    ///
    /// The overlay is pinned to the container's bounds via Auto Layout and
    /// starts hidden (zero visual cost until `activate` is called).
    ///
    /// - Parameter container: The parent view (typically the `Y2CanvasViewController.view`).
    func install(in container: UIView) {
        guard overlayView == nil else {
            logger.warning("EffectOverlayLayer.install called but overlay already exists")
            return
        }

        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear

        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        self.overlayView = view
        logger.debug("Effect overlay installed in container")
    }

    // MARK: - Activation

    /// Show the overlay and configure it for the given effect type.
    ///
    /// This is a lightweight operation — the actual particle emitters and
    /// shape layers are managed by `InkEffectEngine` and attached to
    /// `overlayView` as sublayers when strokes occur.
    ///
    /// - Parameter effect: The ink effect to render. Must not be `.none`.
    func activate(with effect: WritingFXType) {
        guard effect != .none else {
            deactivate()
            return
        }

        activeEffect = effect
        overlayView?.isHidden = false
        logger.debug("Effect overlay activated: \(String(describing: effect))")
    }

    /// Hide the overlay and remove all effect sublayers.
    ///
    /// After deactivation the overlay has zero rendering cost — no layers,
    /// no animations, and the view itself is hidden.
    func deactivate() {
        activeEffect = .none
        guard let view = overlayView else { return }

        // Remove all sublayers added by the effect engines.
        view.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        view.isHidden = true
        logger.debug("Effect overlay deactivated")
    }

    /// Completely remove the overlay from the view hierarchy.
    ///
    /// Call this in the canvas controller's `deinit` or when switching pages.
    func remove() {
        deactivate()
        overlayView?.removeFromSuperview()
        overlayView = nil
        logger.debug("Effect overlay removed from hierarchy")
    }
}
