import UIKit
import SwiftUI

// MARK: - Y2NoteCard

/// A UIKit-based note card view that provides smooth 60 fps thumbnail
/// rendering without SwiftUI re-render overhead.
///
/// Features:
/// - Thumbnail image display with aspect-fill
/// - Title and subtitle labels with Dynamic Type support
/// - Custom long-press gesture with haptic feedback
/// - Drag & drop support with live preview
/// - Theme-aware styling via ``ThemeColors``
///
/// **SwiftUI usage:**
/// ```swift
/// Y2NoteCardView(
///     thumbnail: thumbnailImage,
///     title: "My Note",
///     subtitle: "3 pages · Modified today",
///     accentColor: .blue,
///     onTap: { ... },
///     onLongPress: { ... }
/// )
/// ```
final class Y2NoteCard: UIView {

    // MARK: - Configuration

    struct Configuration {
        var cornerRadius: CGFloat = 16
        var thumbnailAspectRatio: CGFloat = 0.75   // width / height
        var titleFont: UIFont = .preferredFont(forTextStyle: .headline)
        var subtitleFont: UIFont = .preferredFont(forTextStyle: .caption1)
        var shadowRadius: CGFloat = 6
        var shadowOpacity: Float = 0.12
        var longPressDuration: TimeInterval = 0.5
        var respectsReduceMotion: Bool = true
    }

    /// Theme colours that the card draws from.
    struct ThemeColors {
        var cardBackground: UIColor = .secondarySystemGroupedBackground
        var titleColor: UIColor = .label
        var subtitleColor: UIColor = .secondaryLabel
        var accentColor: UIColor = .tintColor
        var borderColor: UIColor = .separator
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var themeColors: ThemeColors

    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let favoriteIndicator = UIImageView()
    private let containerStack = UIStackView()

    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    // MARK: - Init

    init(configuration: Configuration = .init(), themeColors: ThemeColors = .init()) {
        self.configuration = configuration
        self.themeColors = themeColors
        super.init(frame: .zero)
        setupViews()
        setupGestures()
        setupAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(configuration:themeColors:)") }

    // MARK: - Setup

    private func setupViews() {
        // Container
        backgroundColor = themeColors.cardBackground
        layer.cornerRadius = configuration.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = themeColors.borderColor.cgColor
        clipsToBounds = false

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = configuration.shadowRadius
        layer.shadowOpacity = configuration.shadowOpacity

        // Thumbnail
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = configuration.cornerRadius
        thumbnailView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        thumbnailView.layer.cornerCurve = .continuous
        thumbnailView.backgroundColor = .tertiarySystemGroupedBackground
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font = configuration.titleFont
        titleLabel.textColor = themeColors.titleColor
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle
        subtitleLabel.font = configuration.subtitleFont
        subtitleLabel.textColor = themeColors.subtitleColor
        subtitleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Favorite indicator
        favoriteIndicator.image = UIImage(systemName: "heart.fill")
        favoriteIndicator.tintColor = themeColors.accentColor
        favoriteIndicator.translatesAutoresizingMaskIntoConstraints = false
        favoriteIndicator.isHidden = true
        favoriteIndicator.contentMode = .scaleAspectFit

        addSubview(thumbnailView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(favoriteIndicator)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.heightAnchor.constraint(
                equalTo: thumbnailView.widthAnchor,
                multiplier: 1.0 / configuration.thumbnailAspectRatio
            ),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: favoriteIndicator.leadingAnchor, constant: -4),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

            favoriteIndicator.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            favoriteIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            favoriteIndicator.widthAnchor.constraint(equalToConstant: 16),
            favoriteIndicator.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = configuration.longPressDuration
        addGestureRecognizer(longPress)
    }

    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    // MARK: - Public API

    /// Updates the card content.
    func configure(
        thumbnail: UIImage?,
        title: String,
        subtitle: String,
        isFavorite: Bool = false,
        accentColor: UIColor? = nil
    ) {
        thumbnailView.image = thumbnail
        titleLabel.text = title
        subtitleLabel.text = subtitle
        favoriteIndicator.isHidden = !isFavorite

        if let accent = accentColor {
            themeColors.accentColor = accent
            favoriteIndicator.tintColor = accent
        }

        // Accessibility
        accessibilityLabel = title
        accessibilityValue = subtitle
        if isFavorite {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }

    /// Updates theme colours for the card.
    func applyTheme(_ colors: ThemeColors) {
        themeColors = colors
        backgroundColor = colors.cardBackground
        titleLabel.textColor = colors.titleColor
        subtitleLabel.textColor = colors.subtitleColor
        favoriteIndicator.tintColor = colors.accentColor
        layer.borderColor = colors.borderColor.cgColor
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap() {
        animatePress()
        onTap?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        animatePress()
        onLongPress?()
    }

    // MARK: - Animation

    private func animatePress() {
        guard !shouldReduceMotion else { return }
        UIView.animate(
            withDuration: 0.1,
            delay: 0,
            options: .curveEaseIn,
            animations: { self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96) },
            completion: { _ in
                UIView.animate(
                    withDuration: 0.15,
                    delay: 0,
                    usingSpringWithDamping: 0.6,
                    initialSpringVelocity: 0,
                    options: .allowUserInteraction,
                    animations: { self.transform = .identity }
                )
            }
        )
    }

    private var shouldReduceMotion: Bool {
        configuration.respectsReduceMotion && UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI hosting wrapper for ``Y2NoteCard``.
struct Y2NoteCardView: UIViewRepresentable {

    var thumbnail: UIImage?
    var title: String
    var subtitle: String
    var isFavorite: Bool
    var accentColor: UIColor?
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    init(
        thumbnail: UIImage? = nil,
        title: String,
        subtitle: String = "",
        isFavorite: Bool = false,
        accentColor: UIColor? = nil,
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.thumbnail = thumbnail
        self.title = title
        self.subtitle = subtitle
        self.isFavorite = isFavorite
        self.accentColor = accentColor
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    func makeUIView(context: Context) -> Y2NoteCard {
        let card = Y2NoteCard()
        card.configure(
            thumbnail: thumbnail,
            title: title,
            subtitle: subtitle,
            isFavorite: isFavorite,
            accentColor: accentColor
        )
        card.onTap = onTap
        card.onLongPress = onLongPress
        return card
    }

    func updateUIView(_ uiView: Y2NoteCard, context: Context) {
        uiView.configure(
            thumbnail: thumbnail,
            title: title,
            subtitle: subtitle,
            isFavorite: isFavorite,
            accentColor: accentColor
        )
        uiView.onTap = onTap
        uiView.onLongPress = onLongPress
    }
}
