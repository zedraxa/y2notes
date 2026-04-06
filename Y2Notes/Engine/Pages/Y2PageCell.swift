import UIKit

// MARK: - Y2PageCell

/// UICollectionViewCell for a page thumbnail in the page management panel.
///
/// **Visual design (from reference):**
/// - Full page preview at thumbnail scale.
/// - Page number + dropdown chevron below.
/// - Bookmark icon in top-right corner.
/// - Selected page: blue border (not blue background).
/// - Different template backgrounds visible (cover vs lined vs grid vs blank).
final class Y2PageCell: UICollectionViewCell {

    static let reuseID = "Y2PageCell"

    // MARK: - Callbacks

    var onBookmarkToggle: (() -> Void)?
    var onPageDropdown: (() -> Void)?

    // MARK: - Subviews

    private let thumbnailImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 6
        iv.layer.cornerCurve = .continuous
        iv.layer.borderWidth = 0
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .systemBackground
        return iv
    }()

    private let bookmarkButton: UIButton = {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        btn.tintColor = .systemOrange
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let pageNumberButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = .zero
        config.imagePadding = 2
        config.preferredSymbolConfigurationForImage = .init(pointSize: 8, weight: .medium)
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    // MARK: - State

    private var isPageSelected = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        setupActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupLayout() {
        // Shadow on content view
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = 0.08
        contentView.layer.shadowOffset = CGSize(width: 0, height: 1)
        contentView.layer.shadowRadius = 3

        contentView.addSubview(thumbnailImageView)
        contentView.addSubview(bookmarkButton)
        contentView.addSubview(activityIndicator)
        contentView.addSubview(pageNumberButton)

        NSLayoutConstraint.activate([
            thumbnailImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailImageView.heightAnchor.constraint(equalTo: thumbnailImageView.widthAnchor, multiplier: 1.4),

            bookmarkButton.topAnchor.constraint(equalTo: thumbnailImageView.topAnchor, constant: 4),
            bookmarkButton.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: -4),

            activityIndicator.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),

            pageNumberButton.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: 4),
            pageNumberButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pageNumberButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    private func setupActions() {
        bookmarkButton.addAction(UIAction { [weak self] _ in
            self?.onBookmarkToggle?()
        }, for: .touchUpInside)

        pageNumberButton.addAction(UIAction { [weak self] _ in
            self?.onPageDropdown?()
        }, for: .touchUpInside)
    }

    // MARK: - Configuration

    /// Configures the cell with page data.
    func configure(
        thumbnailImage: UIImage?,
        pageNumber: Int,
        isBookmarked: Bool,
        isSelected: Bool,
        isLoading: Bool = false
    ) {
        thumbnailImageView.image = thumbnailImage
        isPageSelected = isSelected

        // Blue selection border
        thumbnailImageView.layer.borderWidth = isSelected ? 2.5 : 0
        thumbnailImageView.layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : nil

        // Page number with dropdown
        var btnConfig = UIButton.Configuration.plain()
        btnConfig.baseForegroundColor = .secondaryLabel
        btnConfig.title = "\(pageNumber)"
        btnConfig.titleTextAttributesTransformer = .init { container in
            var c = container
            c.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            return c
        }
        btnConfig.image = UIImage(systemName: "chevron.down")
        btnConfig.imagePlacement = .trailing
        btnConfig.imagePadding = 2
        btnConfig.preferredSymbolConfigurationForImage = .init(pointSize: 8, weight: .medium)
        btnConfig.contentInsets = .zero
        pageNumberButton.configuration = btnConfig

        // Bookmark
        let bmName = isBookmarked ? "bookmark.fill" : "bookmark"
        let bmConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        bookmarkButton.setImage(UIImage(systemName: bmName, withConfiguration: bmConfig), for: .normal)
        bookmarkButton.accessibilityLabel = isBookmarked ? "Remove bookmark" : "Bookmark this page"

        // Loading state
        if isLoading {
            activityIndicator.startAnimating()
            thumbnailImageView.alpha = 0.4
        } else {
            activityIndicator.stopAnimating()
            thumbnailImageView.alpha = 1
        }

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "Page \(pageNumber)"
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        if isBookmarked {
            accessibilityValue = "Bookmarked"
        }
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.image = nil
        thumbnailImageView.layer.borderWidth = 0
        activityIndicator.stopAnimating()
        thumbnailImageView.alpha = 1
        onBookmarkToggle = nil
        onPageDropdown = nil
    }
}
