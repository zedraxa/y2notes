import UIKit
import SwiftUI

// MARK: - Y2ToolPalette

/// A radial or grid tool picker inspired by Procreate's tool wheel.
///
/// When presented, tools fan out in a radial arc (or fall back to a grid
/// when `UIAccessibility.isReduceMotionEnabled` is true).
///
/// **Usage (SwiftUI):**
/// ```swift
/// Y2ToolPaletteView(
///     tools: DrawingTool.allCases,
///     selected: $activeTool,
///     label: { tool in Image(systemName: tool.icon) },
///     onSelect: { tool in ... }
/// )
/// ```
final class Y2ToolPalette: UIView {

    // MARK: - Types

    struct Item {
        let id: String
        let icon: UIImage?
        let tintColor: UIColor
        let accessibilityLabel: String
    }

    enum Layout {
        /// Fan-out arc centred on the anchor point.
        case radial(radius: CGFloat, arcDegrees: CGFloat)
        /// Uniform grid (accessibility fallback).
        case grid(columns: Int, spacing: CGFloat)
    }

    // MARK: - Configuration

    struct Configuration {
        var layout: Layout = .radial(radius: 90, arcDegrees: 180)
        var itemSize: CGFloat = 44
        var backgroundStyle: UIBlurEffect.Style = .systemUltraThinMaterial
        var cornerRadius: CGFloat = 14
        var respectsReduceMotion: Bool = true
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var items: [Item] = []
    private var buttons: [UIButton] = []
    private var selectedIndex: Int = 0
    var onSelect: ((Int) -> Void)?

    private let blurView: UIVisualEffectView

    // MARK: - Init

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: configuration.backgroundStyle))
        super.init(frame: .zero)
        setupBlurBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    // MARK: - Setup

    private func setupBlurBackground() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = configuration.cornerRadius
        blurView.layer.cornerCurve = .continuous
        insertSubview(blurView, at: 0)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public API

    /// Loads the palette with the given tool items.
    func setItems(_ newItems: [Item], selectedIndex: Int = 0) {
        self.items = newItems
        self.selectedIndex = selectedIndex
        rebuildButtons()
    }

    /// Updates the visual selection ring.
    func setSelectedIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        updateSelectionAppearance()
    }

    /// Shows the palette with animation.
    func present(animated: Bool = true) {
        isHidden = false
        if animated && !shouldReduceMotion {
            animatePresentation()
        } else {
            buttons.forEach { $0.alpha = 1; $0.transform = .identity }
        }
    }

    /// Hides the palette with animation.
    func dismiss(animated: Bool = true) {
        let completion: () -> Void = { [self] in isHidden = true }
        if animated && !shouldReduceMotion {
            animateDismissal(completion: completion)
        } else {
            completion()
        }
    }

    // MARK: - Button Construction

    private func rebuildButtons() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        for (index, item) in items.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(item.icon, for: .normal)
            button.tintColor = item.tintColor
            button.tag = index
            button.accessibilityLabel = item.accessibilityLabel
            button.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)

            let size = configuration.itemSize
            button.frame = CGRect(x: 0, y: 0, width: size, height: size)
            button.layer.cornerRadius = size / 2
            button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.6)

            addSubview(button)
            buttons.append(button)
        }

        layoutButtons()
        updateSelectionAppearance()
    }

    // MARK: - Layout

    private func layoutButtons() {
        let effectiveLayout = shouldReduceMotion
            ? Layout.grid(columns: 4, spacing: 8)
            : configuration.layout

        switch effectiveLayout {
        case .radial(let radius, let arcDegrees):
            layoutRadial(radius: radius, arcDegrees: arcDegrees)
        case .grid(let columns, let spacing):
            layoutGrid(columns: columns, spacing: spacing)
        }
    }

    private func layoutRadial(radius: CGFloat, arcDegrees: CGFloat) {
        guard !buttons.isEmpty else { return }
        let count = buttons.count

        let arcRadians = arcDegrees * .pi / 180
        let startAngle = -.pi / 2 - arcRadians / 2
        let step = count > 1 ? arcRadians / CGFloat(count - 1) : 0
        let anchorPoint = CGPoint(x: bounds.midX, y: bounds.maxY)

        for (i, button) in buttons.enumerated() {
            let angle = startAngle + step * CGFloat(i)
            let x = anchorPoint.x + radius * cos(angle)
            let y = anchorPoint.y + radius * sin(angle)
            button.center = CGPoint(x: x, y: y)
        }
    }

    private func layoutGrid(columns: Int, spacing: CGFloat) {
        let size = configuration.itemSize
        for (i, button) in buttons.enumerated() {
            let col = CGFloat(i % columns)
            let row = CGFloat(i / columns)
            button.frame = CGRect(
                x: spacing + col * (size + spacing),
                y: spacing + row * (size + spacing),
                width: size,
                height: size
            )
        }
    }

    // MARK: - Selection

    private func updateSelectionAppearance() {
        for (i, button) in buttons.enumerated() {
            let isSelected = i == selectedIndex
            button.layer.borderWidth = isSelected ? 2.5 : 0
            button.layer.borderColor = isSelected ? tintColor.cgColor : nil
            button.accessibilityTraits = isSelected
                ? [.button, .selected]
                : .button
        }
    }

    @objc private func itemTapped(_ sender: UIButton) {
        let index = sender.tag
        setSelectedIndex(index)
        onSelect?(index)

        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
    }

    // MARK: - Animation

    private func animatePresentation() {
        for (i, button) in buttons.enumerated() {
            button.alpha = 0
            button.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            UIView.animate(
                withDuration: 0.35,
                delay: Double(i) * 0.03,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0,
                options: .allowUserInteraction,
                animations: { button.alpha = 1; button.transform = .identity }
            )
        }
    }

    private func animateDismissal(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for (i, button) in buttons.reversed().enumerated() {
            group.enter()
            UIView.animate(
                withDuration: 0.2,
                delay: Double(i) * 0.02,
                options: .curveEaseIn,
                animations: {
                    button.alpha = 0
                    button.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                },
                completion: { _ in group.leave() }
            )
        }
        group.notify(queue: .main, execute: completion)
    }

    // MARK: - Helpers

    private var shouldReduceMotion: Bool {
        configuration.respectsReduceMotion && UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI hosting wrapper for ``Y2ToolPalette``.
struct Y2ToolPaletteView: UIViewRepresentable {

    let items: [Y2ToolPalette.Item]
    @Binding var selectedIndex: Int
    var configuration: Y2ToolPalette.Configuration
    var onSelect: ((Int) -> Void)?

    init(
        items: [Y2ToolPalette.Item],
        selectedIndex: Binding<Int>,
        configuration: Y2ToolPalette.Configuration = .init(),
        onSelect: ((Int) -> Void)? = nil
    ) {
        self.items = items
        self._selectedIndex = selectedIndex
        self.configuration = configuration
        self.onSelect = onSelect
    }

    func makeUIView(context: Context) -> Y2ToolPalette {
        let palette = Y2ToolPalette(configuration: configuration)
        palette.setItems(items, selectedIndex: selectedIndex)
        palette.onSelect = { index in
            selectedIndex = index
            onSelect?(index)
        }
        return palette
    }

    func updateUIView(_ uiView: Y2ToolPalette, context: Context) {
        uiView.setItems(items, selectedIndex: selectedIndex)
    }
}
