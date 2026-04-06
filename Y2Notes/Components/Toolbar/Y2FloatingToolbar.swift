import UIKit
import SwiftUI
import Combine

// MARK: - Y2FloatingToolbar

/// A UIKit-based floating toolbar that can be dragged to any screen edge,
/// collapsed/expanded with spring animation, and customised with arbitrary content.
///
/// **Usage (SwiftUI):**
/// ```swift
/// Y2FloatingToolbarView(edge: .bottom) {
///     HStack { Button("Pen") { } ; Button("Eraser") { } }
/// }
/// ```
///
/// Internally uses a `UIView` subclass for 60 fps drag gestures and
/// Core Animation for collapse/expand transitions.
final class Y2FloatingToolbar: UIView {

    // MARK: - Types

    /// Screen edge the toolbar snaps to after a drag.
    enum Edge: Int, CaseIterable {
        case top, bottom, leading, trailing
    }

    /// Visual state of the toolbar.
    enum State {
        case expanded, collapsed, hidden
    }

    // MARK: - Configuration

    struct Configuration {
        var cornerRadius: CGFloat = 22
        var collapsedWidth: CGFloat = 48
        var expandedInset: CGFloat = 16
        var snapAnimationDuration: TimeInterval = 0.35
        var backgroundStyle: UIBlurEffect.Style = .systemThinMaterial
        var shadowRadius: CGFloat = 8
        var shadowOpacity: Float = 0.15
        var respectsReduceMotion: Bool = true
    }

    // MARK: - Properties

    private(set) var currentEdge: Edge = .bottom
    private(set) var currentState: State = .expanded

    private let configuration: Configuration
    private let blurView: UIVisualEffectView
    private let contentContainer: UIView = UIView()
    private var panGesture: UIPanGestureRecognizer!
    private var dragStartCenter: CGPoint = .zero

    /// Publisher that emits the new edge after every snap.
    let edgeChanged = PassthroughSubject<Edge, Never>()

    /// Publisher that emits the new state after collapse/expand.
    let stateChanged = PassthroughSubject<State, Never>()

    // MARK: - Init

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: configuration.backgroundStyle))
        super.init(frame: .zero)
        setupSubviews()
        setupGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    // MARK: - Setup

    private func setupSubviews() {
        // Blur background
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = configuration.cornerRadius
        blurView.layer.cornerCurve = .continuous
        addSubview(blurView)

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = configuration.shadowRadius
        layer.shadowOpacity = configuration.shadowOpacity

        // Content container
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentContainer.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 8),
            contentContainer.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 12),
            contentContainer.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -12),
            contentContainer.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -8),
        ])

        // Accessibility
        isAccessibilityElement = false
        accessibilityLabel = NSLocalizedString("Floating Toolbar", comment: "Accessibility label for floating toolbar")
        accessibilityTraits = .allowsDirectInteraction
    }

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
    }

    // MARK: - Content

    /// Replaces the toolbar content with the given UIView.
    func setContent(_ view: UIView) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    // MARK: - State Management

    /// Toggles between expanded and collapsed states.
    func toggleCollapse(animated: Bool = true) {
        let target: State = currentState == .expanded ? .collapsed : .expanded
        setState(target, animated: animated)
    }

    /// Sets the toolbar state with optional animation.
    func setState(_ newState: State, animated: Bool = true) {
        guard newState != currentState else { return }
        currentState = newState
        stateChanged.send(newState)

        let useAnimation = animated && !shouldReduceMotion

        let changes: () -> Void = { [self] in
            switch newState {
            case .expanded:
                contentContainer.alpha = 1
                transform = .identity
            case .collapsed:
                contentContainer.alpha = 0
                let scale = configuration.collapsedWidth / max(bounds.width, 1)
                transform = CGAffineTransform(scaleX: scale, y: 1)
            case .hidden:
                alpha = 0
                transform = CGAffineTransform(translationX: 0, y: 20)
            }
        }

        if useAnimation {
            UIView.animate(
                withDuration: configuration.snapAnimationDuration,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: changes
            )
        } else {
            changes()
        }
    }

    // MARK: - Drag Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }

        switch gesture.state {
        case .began:
            dragStartCenter = center
        case .changed:
            let translation = gesture.translation(in: superview)
            center = CGPoint(
                x: dragStartCenter.x + translation.x,
                y: dragStartCenter.y + translation.y
            )
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: superview)
            snapToNearestEdge(velocity: velocity)
        default:
            break
        }
    }

    /// Snaps the toolbar to the closest screen edge with physics-based animation.
    private func snapToNearestEdge(velocity: CGPoint) {
        guard let superview else { return }
        let safeArea = superview.safeAreaInsets
        let bounds = superview.bounds
        let inset = configuration.expandedInset
        let size = self.bounds.size

        // Calculate target positions for each edge
        let targets: [(Edge, CGPoint)] = [
            (.top, CGPoint(
                x: clamp(center.x, min: safeArea.left + size.width / 2 + inset,
                          max: bounds.width - safeArea.right - size.width / 2 - inset),
                y: safeArea.top + size.height / 2 + inset)),
            (.bottom, CGPoint(
                x: clamp(center.x, min: safeArea.left + size.width / 2 + inset,
                          max: bounds.width - safeArea.right - size.width / 2 - inset),
                y: bounds.height - safeArea.bottom - size.height / 2 - inset)),
            (.leading, CGPoint(
                x: safeArea.left + size.width / 2 + inset,
                y: clamp(center.y, min: safeArea.top + size.height / 2 + inset,
                          max: bounds.height - safeArea.bottom - size.height / 2 - inset))),
            (.trailing, CGPoint(
                x: bounds.width - safeArea.right - size.width / 2 - inset,
                y: clamp(center.y, min: safeArea.top + size.height / 2 + inset,
                          max: bounds.height - safeArea.bottom - size.height / 2 - inset))),
        ]

        // Pick closest edge (weighted by velocity direction)
        let bestTarget = targets.min { a, b in
            let distA = hypot(a.1.x - center.x, a.1.y - center.y)
            let distB = hypot(b.1.x - center.x, b.1.y - center.y)
            return distA < distB
        }!

        currentEdge = bestTarget.0
        edgeChanged.send(currentEdge)

        let useAnimation = !shouldReduceMotion
        if useAnimation {
            UIView.animate(
                withDuration: configuration.snapAnimationDuration,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5,
                options: [.allowUserInteraction],
                animations: { self.center = bestTarget.1 }
            )
        } else {
            center = bestTarget.1
        }
    }

    // MARK: - Helpers

    private var shouldReduceMotion: Bool {
        configuration.respectsReduceMotion && UIAccessibility.isReduceMotionEnabled
    }

    private func clamp(_ value: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lo), hi)
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI hosting wrapper for ``Y2FloatingToolbar``.
///
/// ```swift
/// Y2FloatingToolbarView(edge: .bottom) {
///     HStack { toolButtons }
/// }
/// ```
struct Y2FloatingToolbarView<Content: View>: UIViewRepresentable {

    var initialEdge: Y2FloatingToolbar.Edge
    var configuration: Y2FloatingToolbar.Configuration
    @ViewBuilder var content: () -> Content

    init(
        edge: Y2FloatingToolbar.Edge = .bottom,
        configuration: Y2FloatingToolbar.Configuration = .init(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.initialEdge = edge
        self.configuration = configuration
        self.content = content
    }

    func makeUIView(context: Context) -> Y2FloatingToolbar {
        let toolbar = Y2FloatingToolbar(configuration: configuration)
        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .clear
        toolbar.setContent(hostingController.view)
        toolbar.currentEdge = initialEdge
        return toolbar
    }

    func updateUIView(_ uiView: Y2FloatingToolbar, context: Context) {
        // Re-host content on update
        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .clear
        uiView.setContent(hostingController.view)
    }
}
