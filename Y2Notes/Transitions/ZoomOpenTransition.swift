import UIKit
import SwiftUI

// MARK: - ZoomOpenTransition

/// A custom zoom-in transition for opening a note from the grid.
///
/// Captures a snapshot of the source card, then scales and fades it into
/// the full note editor. Falls back to a simple scale-opacity transition
/// when `UIAccessibility.isReduceMotionEnabled` is true.
///
/// **Usage (UIKit):**
/// ```swift
/// let transition = ZoomOpenTransition()
/// transition.open(
///     from: cardView,
///     to: editorViewController,
///     in: navigationController
/// )
/// ```
///
/// **Usage (SwiftUI):**
/// ```swift
/// .matchedGeometryEffect(id: note.id, in: namespace)
/// .transition(.zoomOpen)
/// ```
final class ZoomOpenTransition: NSObject {

    // MARK: - Configuration

    struct Configuration {
        var duration: TimeInterval = 0.45
        var cornerRadiusStart: CGFloat = 16
        var cornerRadiusEnd: CGFloat = 0
        var scaleDownFactor: CGFloat = 0.85
        var backgroundDimAlpha: CGFloat = 0.3
        var respectsReduceMotion: Bool = true
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var sourceFrame: CGRect = .zero
    private var sourceSnapshot: UIView?

    // MARK: - Init

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        super.init()
    }

    // MARK: - Public API

    /// Performs the zoom-open transition from a source view to a destination.
    func open(
        from sourceView: UIView,
        to destinationView: UIView,
        in container: UIView,
        completion: (() -> Void)? = nil
    ) {
        if shouldReduceMotion {
            simpleScaleIn(destinationView: destinationView, in: container, completion: completion)
            return
        }

        performZoomOpen(
            from: sourceView,
            to: destinationView,
            in: container,
            completion: completion
        )
    }

    /// Performs the reverse (zoom-close) transition.
    func close(
        from editorView: UIView,
        to cardFrame: CGRect,
        in container: UIView,
        completion: (() -> Void)? = nil
    ) {
        if shouldReduceMotion {
            simpleScaleOut(editorView: editorView, completion: completion)
            return
        }

        performZoomClose(
            from: editorView,
            to: cardFrame,
            in: container,
            completion: completion
        )
    }

    // MARK: - Zoom Open

    private func performZoomOpen(
        from sourceView: UIView,
        to destinationView: UIView,
        in container: UIView,
        completion: (() -> Void)?
    ) {
        // Capture source frame in container coordinates
        sourceFrame = sourceView.convert(sourceView.bounds, to: container)

        // Create snapshot of the source card
        let snapshot = sourceView.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = sourceFrame
        snapshot.layer.cornerRadius = configuration.cornerRadiusStart
        snapshot.layer.cornerCurve = .continuous
        snapshot.clipsToBounds = true

        // Background dimming layer
        let dimView = UIView(frame: container.bounds)
        dimView.backgroundColor = UIColor.black
        dimView.alpha = 0

        // Setup destination
        destinationView.frame = container.bounds
        destinationView.alpha = 0
        destinationView.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)

        container.addSubview(dimView)
        container.addSubview(snapshot)
        container.addSubview(destinationView)

        sourceView.alpha = 0

        UIView.animate(
            withDuration: configuration.duration,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: .curveEaseInOut,
            animations: {
                // Scale snapshot to fill container
                snapshot.frame = container.bounds
                snapshot.layer.cornerRadius = self.configuration.cornerRadiusEnd
                snapshot.alpha = 0.3

                // Fade in destination
                destinationView.alpha = 1
                destinationView.transform = .identity

                dimView.alpha = self.configuration.backgroundDimAlpha
            },
            completion: { _ in
                snapshot.removeFromSuperview()
                dimView.removeFromSuperview()
                sourceView.alpha = 1
                completion?()
            }
        )
    }

    // MARK: - Zoom Close

    private func performZoomClose(
        from editorView: UIView,
        to cardFrame: CGRect,
        in container: UIView,
        completion: (() -> Void)?
    ) {
        let snapshot = editorView.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = editorView.frame
        snapshot.layer.cornerRadius = configuration.cornerRadiusEnd
        snapshot.layer.cornerCurve = .continuous
        snapshot.clipsToBounds = true
        container.addSubview(snapshot)

        editorView.alpha = 0

        UIView.animate(
            withDuration: configuration.duration * 0.8,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: .curveEaseInOut,
            animations: {
                snapshot.frame = cardFrame
                snapshot.layer.cornerRadius = self.configuration.cornerRadiusStart
                snapshot.alpha = 0
            },
            completion: { _ in
                snapshot.removeFromSuperview()
                editorView.removeFromSuperview()
                completion?()
            }
        )
    }

    // MARK: - Reduced Motion Fallback

    private func simpleScaleIn(
        destinationView: UIView,
        in container: UIView,
        completion: (() -> Void)?
    ) {
        destinationView.frame = container.bounds
        destinationView.alpha = 0
        destinationView.transform = CGAffineTransform(
            scaleX: configuration.scaleDownFactor,
            y: configuration.scaleDownFactor
        )
        container.addSubview(destinationView)

        UIView.animate(withDuration: 0.25) {
            destinationView.alpha = 1
            destinationView.transform = .identity
        } completion: { _ in
            completion?()
        }
    }

    private func simpleScaleOut(
        editorView: UIView,
        completion: (() -> Void)?
    ) {
        UIView.animate(withDuration: 0.2) {
            editorView.alpha = 0
            editorView.transform = CGAffineTransform(
                scaleX: self.configuration.scaleDownFactor,
                y: self.configuration.scaleDownFactor
            )
        } completion: { _ in
            editorView.removeFromSuperview()
            editorView.transform = .identity
            editorView.alpha = 1
            completion?()
        }
    }

    // MARK: - Helpers

    private var shouldReduceMotion: Bool {
        configuration.respectsReduceMotion && UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - SwiftUI Transition

extension AnyTransition {
    /// A zoom-open transition for SwiftUI views.
    ///
    /// Falls back to scale + opacity when Reduce Motion is enabled.
    static var zoomOpen: AnyTransition {
        if UIAccessibility.isReduceMotionEnabled {
            return .scale.combined(with: .opacity)
        }
        return .asymmetric(
            insertion: .modifier(
                active: ZoomOpenModifier(progress: 0),
                identity: ZoomOpenModifier(progress: 1)
            ),
            removal: .modifier(
                active: ZoomCloseModifier(progress: 1),
                identity: ZoomCloseModifier(progress: 0)
            )
        )
    }
}

// MARK: - ZoomOpenModifier

private struct ZoomOpenModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        let scale: CGFloat = 0.85 + 0.15 * progress
        content
            .scaleEffect(scale)
            .opacity(progress)
            .clipShape(RoundedRectangle(
                cornerRadius: 16 * (1 - progress),
                style: .continuous
            ))
    }
}

// MARK: - ZoomCloseModifier

private struct ZoomCloseModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        let scale: CGFloat = 1.0 - 0.15 * progress
        content
            .scaleEffect(scale)
            .opacity(1 - progress)
            .clipShape(RoundedRectangle(
                cornerRadius: 16 * progress,
                style: .continuous
            ))
    }
}
