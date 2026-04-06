import UIKit
import SwiftUI

// MARK: - PageFlipTransition

/// A custom page-flip animation for switching between note pages.
///
/// Uses Core Animation's `CATransformLayer` with a 3D perspective transform
/// to simulate a realistic page turn. Falls back to a simple cross-dissolve
/// when `UIAccessibility.isReduceMotionEnabled` is true.
///
/// **Usage (UIKit):**
/// ```swift
/// let transition = PageFlipTransition()
/// transition.flip(
///     from: currentPageView,
///     to: nextPageView,
///     in: containerView,
///     direction: .forward
/// )
/// ```
///
/// **Usage (SwiftUI):**
/// ```swift
/// content
///     .transition(.pageFlip)
/// ```
final class PageFlipTransition {

    // MARK: - Types

    enum Direction {
        case forward   // left-to-right flip (next page)
        case backward  // right-to-left flip (previous page)
    }

    // MARK: - Configuration

    struct Configuration {
        var duration: TimeInterval = 0.6
        var perspective: CGFloat = -1.0 / 800
        var shadowMaxOpacity: Float = 0.25
        var respectsReduceMotion: Bool = true
    }

    // MARK: - Properties

    private let configuration: Configuration

    // MARK: - Init

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Performs a page-flip transition between two views.
    func flip(
        from fromView: UIView,
        to toView: UIView,
        in container: UIView,
        direction: Direction,
        completion: (() -> Void)? = nil
    ) {
        if shouldReduceMotion {
            crossDissolve(from: fromView, to: toView, in: container, completion: completion)
            return
        }

        performFlip(from: fromView, to: toView, in: container, direction: direction, completion: completion)
    }

    // MARK: - 3D Flip Animation

    private func performFlip(
        from fromView: UIView,
        to toView: UIView,
        in container: UIView,
        direction: Direction,
        completion: (() -> Void)?
    ) {
        // Setup perspective
        var perspective = CATransform3DIdentity
        perspective.m34 = configuration.perspective

        container.layer.sublayerTransform = perspective

        // Prepare the incoming view
        toView.frame = container.bounds
        toView.layer.isDoubleSided = false
        container.addSubview(toView)

        // Initial rotation for the incoming page (hidden behind)
        let startAngle: CGFloat = direction == .forward ? .pi / 2 : -.pi / 2
        let endAngle: CGFloat = direction == .forward ? -.pi / 2 : .pi / 2

        toView.layer.transform = CATransform3DRotate(
            CATransform3DIdentity,
            startAngle,
            0, 1, 0
        )
        toView.alpha = 0

        // Shadow overlay on the from-view
        let shadowLayer = CALayer()
        shadowLayer.frame = fromView.bounds
        shadowLayer.backgroundColor = UIColor.black.cgColor
        shadowLayer.opacity = 0
        fromView.layer.addSublayer(shadowLayer)

        let halfDuration = configuration.duration / 2

        // Phase 1: Rotate out the current page
        UIView.animate(
            withDuration: halfDuration,
            delay: 0,
            options: .curveEaseIn,
            animations: {
                fromView.layer.transform = CATransform3DRotate(
                    CATransform3DIdentity,
                    endAngle,
                    0, 1, 0
                )
                shadowLayer.opacity = self.configuration.shadowMaxOpacity
            },
            completion: { _ in
                // Phase 2: Rotate in the new page
                fromView.alpha = 0
                toView.alpha = 1

                UIView.animate(
                    withDuration: halfDuration,
                    delay: 0,
                    options: .curveEaseOut,
                    animations: {
                        toView.layer.transform = CATransform3DIdentity
                    },
                    completion: { _ in
                        fromView.removeFromSuperview()
                        shadowLayer.removeFromSuperlayer()
                        fromView.layer.transform = CATransform3DIdentity
                        fromView.alpha = 1
                        container.layer.sublayerTransform = CATransform3DIdentity
                        completion?()
                    }
                )
            }
        )
    }

    // MARK: - Reduced Motion Fallback

    private func crossDissolve(
        from fromView: UIView,
        to toView: UIView,
        in container: UIView,
        completion: (() -> Void)?
    ) {
        toView.frame = container.bounds
        toView.alpha = 0
        container.addSubview(toView)

        UIView.animate(withDuration: 0.25) {
            fromView.alpha = 0
            toView.alpha = 1
        } completion: { _ in
            fromView.removeFromSuperview()
            fromView.alpha = 1
            completion?()
        }
    }

    // MARK: - Helpers

    private var shouldReduceMotion: Bool {
        configuration.respectsReduceMotion && UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - SwiftUI AnyTransition Extension

extension AnyTransition {
    /// A page-flip transition for SwiftUI views.
    ///
    /// Falls back to opacity when Reduce Motion is enabled.
    static var pageFlip: AnyTransition {
        if UIAccessibility.isReduceMotionEnabled {
            return .opacity
        }
        return .asymmetric(
            insertion: .modifier(
                active: PageFlipModifier(progress: 0, isInsertion: true),
                identity: PageFlipModifier(progress: 1, isInsertion: true)
            ),
            removal: .modifier(
                active: PageFlipModifier(progress: 1, isInsertion: false),
                identity: PageFlipModifier(progress: 0, isInsertion: false)
            )
        )
    }
}

// MARK: - PageFlipModifier

/// A `ViewModifier` that applies a 3D rotation for the page flip effect.
private struct PageFlipModifier: ViewModifier {
    let progress: Double
    let isInsertion: Bool

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            .opacity(opacity)
    }

    private var angle: Double {
        if isInsertion {
            return (1 - progress) * 90
        } else {
            return progress * -90
        }
    }

    private var opacity: Double {
        if isInsertion {
            return progress
        } else {
            return 1 - progress
        }
    }
}
