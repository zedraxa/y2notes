import UIKit
import SwiftUI

// MARK: - Y2PageIndicator

/// Small "3 / 4" page indicator shown in the bottom-left of the editor.
///
/// **Design (from reference):**
/// - Subtle, small text (caption weight), semi-transparent background pill.
/// - Tappable — opens the page panel or a page picker popover.
/// - Updates live as the user swipes between pages.
///
/// This is a UIKit view with a SwiftUI hosting wrapper.
final class Y2PageIndicator: UIView {

    // MARK: - Callbacks

    /// Called when the user taps the indicator.
    var onTap: (() -> Void)?

    // MARK: - Subviews

    private let label: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let pillBackground: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterial)
        let v = UIVisualEffectView(effect: blur)
        v.layer.cornerRadius = 12
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        setupGesture()
        setupAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    // MARK: - Layout

    private func setupLayout() {
        addSubview(pillBackground)
        pillBackground.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            pillBackground.topAnchor.constraint(equalTo: topAnchor),
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.topAnchor.constraint(equalTo: pillBackground.contentView.topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: pillBackground.contentView.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: pillBackground.contentView.trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: pillBackground.contentView.bottomAnchor, constant: -4),
        ])
    }

    private func setupGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = NSLocalizedString("Opens page navigator", comment: "Page indicator a11y hint")
    }

    // MARK: - Public API

    /// Updates the displayed page numbers.
    func update(currentPage: Int, totalPages: Int) {
        label.text = "\(currentPage) / \(totalPages)"
        accessibilityLabel = String(
            format: NSLocalizedString("Page %d of %d", comment: "Page indicator a11y"),
            currentPage, totalPages
        )
    }

    // MARK: - Gesture

    @objc private func handleTap() {
        onTap?()
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(width: labelSize.width + 20, height: labelSize.height + 8)
    }
}

// MARK: - SwiftUI Wrapper

/// Thin SwiftUI wrapper for `Y2PageIndicator`.
struct Y2PageIndicatorView: UIViewRepresentable {
    let currentPage: Int
    let totalPages: Int
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> Y2PageIndicator {
        let indicator = Y2PageIndicator()
        indicator.update(currentPage: currentPage, totalPages: totalPages)
        indicator.onTap = onTap
        return indicator
    }

    func updateUIView(_ view: Y2PageIndicator, context: Context) {
        view.update(currentPage: currentPage, totalPages: totalPages)
        view.onTap = onTap
    }
}
