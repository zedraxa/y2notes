import UIKit
import SwiftUI

// MARK: - Y2SplitController

/// A UIKit `UISplitViewController` wrapper that gives full control over
/// column widths, collapse behaviour, and custom transition animations.
///
/// Unlike SwiftUI's `NavigationSplitView`, this provides:
/// - Pixel-level column width control
/// - Custom collapse/expand animations
/// - Programmatic column visibility with completion handlers
/// - Full delegate control for split behaviour on rotation
///
/// **SwiftUI usage:**
/// ```swift
/// Y2SplitControllerView(
///     sidebar: { ShelfSidebarView() },
///     content: { NoteGridView() },
///     detail:  { NoteEditorView() }
/// )
/// ```
final class Y2SplitController: UISplitViewController {

    // MARK: - Configuration

    struct Configuration {
        var preferredPrimaryWidth: CGFloat = 280
        var minimumPrimaryWidth: CGFloat = 220
        var maximumPrimaryWidth: CGFloat = 380
        var preferredSupplementaryWidth: CGFloat = 320
        var minimumSupplementaryWidth: CGFloat = 260
        var maximumSupplementaryWidth: CGFloat = 500
        var preferredDisplayMode: UISplitViewController.DisplayMode = .twoBesideSecondary
        var presentsWithGesture: Bool = true
        var respectsReduceMotion: Bool = true
    }

    // MARK: - Properties

    private let config: Configuration

    // MARK: - Init

    init(configuration: Configuration = .init()) {
        self.config = configuration
        super.init(style: .tripleColumn)
        applyConfiguration()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    // MARK: - Configuration

    private func applyConfiguration() {
        preferredDisplayMode = config.preferredDisplayMode
        presentsWithGesture = config.presentsWithGesture

        preferredPrimaryColumnWidth = config.preferredPrimaryWidth
        minimumPrimaryColumnWidth = config.minimumPrimaryWidth
        maximumPrimaryColumnWidth = config.maximumPrimaryWidth

        preferredSupplementaryColumnWidth = config.preferredSupplementaryWidth
        minimumSupplementaryColumnWidth = config.minimumSupplementaryWidth
        maximumSupplementaryColumnWidth = config.maximumSupplementaryWidth

        primaryBackgroundStyle = .sidebar

        delegate = self
    }

    // MARK: - Column Management

    /// Sets the sidebar view controller.
    func setSidebar(_ viewController: UIViewController) {
        setViewController(viewController, for: .primary)
    }

    /// Sets the content (supplementary) view controller.
    func setContent(_ viewController: UIViewController) {
        setViewController(viewController, for: .supplementary)
    }

    /// Sets the detail view controller.
    func setDetail(_ viewController: UIViewController) {
        setViewController(viewController, for: .secondary)
    }

    /// Toggles sidebar visibility with optional custom animation.
    func toggleSidebar(animated: Bool = true) {
        let target: UISplitViewController.Column = .primary
        if isCollapsed {
            show(target)
        } else {
            hide(target)
        }
    }

    /// Shows a specific column with optional spring animation.
    func showColumn(_ column: UISplitViewController.Column, animated: Bool = true) {
        if animated && !shouldReduceMotion {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: .allowUserInteraction,
                animations: { self.show(column) }
            )
        } else {
            show(column)
        }
    }

    /// Hides a specific column with optional animation.
    func hideColumn(_ column: UISplitViewController.Column, animated: Bool = true) {
        if animated && !shouldReduceMotion {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction],
                animations: { self.hide(column) }
            )
        } else {
            hide(column)
        }
    }

    // MARK: - Helpers

    private var shouldReduceMotion: Bool {
        config.respectsReduceMotion && UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - UISplitViewControllerDelegate

extension Y2SplitController: UISplitViewControllerDelegate {

    func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        // On compact width, show detail if available, else supplementary
        .secondary
    }

    func splitViewController(
        _ svc: UISplitViewController,
        displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode
    ) -> UISplitViewController.DisplayMode {
        config.preferredDisplayMode
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI hosting wrapper for ``Y2SplitController``.
///
/// Provides a 3-column split view with full UIKit control under the hood.
struct Y2SplitControllerView<Sidebar: View, Content: View, Detail: View>: UIViewControllerRepresentable {

    var configuration: Y2SplitController.Configuration
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content
    @ViewBuilder var detail: () -> Detail

    init(
        configuration: Y2SplitController.Configuration = .init(),
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.configuration = configuration
        self.sidebar = sidebar
        self.content = content
        self.detail = detail
    }

    func makeUIViewController(context: Context) -> Y2SplitController {
        let split = Y2SplitController(configuration: configuration)
        split.setSidebar(UIHostingController(rootView: sidebar()))
        split.setContent(UIHostingController(rootView: content()))
        split.setDetail(UIHostingController(rootView: detail()))
        return split
    }

    func updateUIViewController(_ uiViewController: Y2SplitController, context: Context) {
        // Update column content on SwiftUI state changes
        if let sidebar = uiViewController.viewController(for: .primary) as? UIHostingController<Sidebar> {
            sidebar.rootView = self.sidebar()
        }
        if let content = uiViewController.viewController(for: .supplementary) as? UIHostingController<Content> {
            content.rootView = self.content()
        }
        if let detail = uiViewController.viewController(for: .secondary) as? UIHostingController<Detail> {
            detail.rootView = self.detail()
        }
    }
}
