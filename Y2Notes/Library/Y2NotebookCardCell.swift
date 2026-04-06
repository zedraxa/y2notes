import UIKit

// MARK: - Y2NotebookCardCell

/// UICollectionViewCell for a single notebook in the library grid.
///
/// **Visual design (from reference):**
/// - Cover image area (~3:4 aspect ratio) with rounded corners + shadow.
/// - Cloud sync badge (top-left), star/favorite toggle (top-right).
/// - Folded corner triangle (top-right, Core Graphics).
/// - Title label with dropdown chevron below cover.
/// - Relative date label below title.
///
/// The cell is self-contained — it accepts only primitive data via `configure(…)`.
final class Y2NotebookCardCell: UICollectionViewCell {

    static let reuseID = "Y2NotebookCardCell"

    // MARK: - Callbacks

    var onFavoriteToggle: (() -> Void)?
    var onTitleDropdown: (() -> Void)?

    // MARK: - Subviews

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 10
        iv.layer.cornerCurve = .continuous
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .tertiarySystemFill
        return iv
    }()

    private let foldedCornerView = FoldedCornerView()

    private let syncBadge: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "arrow.up.to.line.compact")
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private let favoriteButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .systemYellow
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let titleButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .label
        config.titleAlignment = .leading
        config.contentInsets = .zero
        config.imagePadding = 4
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let shadowContainer = UIView()

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
        shadowContainer.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.layer.shadowColor = UIColor.black.cgColor
        shadowContainer.layer.shadowOpacity = 0.12
        shadowContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        shadowContainer.layer.shadowRadius = 6
        contentView.addSubview(shadowContainer)

        shadowContainer.addSubview(coverImageView)
        coverImageView.addSubview(syncBadge)
        coverImageView.addSubview(favoriteButton)

        foldedCornerView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.addSubview(foldedCornerView)

        contentView.addSubview(titleButton)
        contentView.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            // Shadow container = cover area
            shadowContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            shadowContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shadowContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            coverImageView.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 4.0 / 3.0),

            syncBadge.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 8),
            syncBadge.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor, constant: 8),
            syncBadge.widthAnchor.constraint(equalToConstant: 16),
            syncBadge.heightAnchor.constraint(equalToConstant: 16),

            favoriteButton.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 2),
            favoriteButton.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: -2),

            foldedCornerView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            foldedCornerView.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor),
            foldedCornerView.widthAnchor.constraint(equalToConstant: 20),
            foldedCornerView.heightAnchor.constraint(equalToConstant: 20),

            // Title + date below cover
            titleButton.topAnchor.constraint(equalTo: shadowContainer.bottomAnchor, constant: 8),
            titleButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleButton.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),

            dateLabel.topAnchor.constraint(equalTo: titleButton.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    private func setupActions() {
        favoriteButton.addAction(UIAction { [weak self] _ in
            self?.onFavoriteToggle?()
        }, for: .touchUpInside)

        titleButton.addAction(UIAction { [weak self] _ in
            self?.onTitleDropdown?()
        }, for: .touchUpInside)
    }

    // MARK: - Configuration

    /// Configures the cell with display data.
    func configure(
        coverImage: UIImage?,
        title: String,
        date: Date,
        isFavorited: Bool,
        needsSync: Bool
    ) {
        coverImageView.image = coverImage

        // Title with chevron
        var titleConfig = UIButton.Configuration.plain()
        titleConfig.baseForegroundColor = .label
        titleConfig.title = title
        titleConfig.titleTextAttributesTransformer = .init { container in
            var c = container
            c.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return c
        }
        titleConfig.image = UIImage(systemName: "chevron.down")
        titleConfig.imagePlacement = .trailing
        titleConfig.imagePadding = 4
        titleConfig.preferredSymbolConfigurationForImage = .init(pointSize: 9, weight: .medium)
        titleConfig.contentInsets = .zero
        titleButton.configuration = titleConfig

        // Date — relative format
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        dateLabel.text = formatter.localizedString(for: date, relativeTo: .now)

        // Favorite star
        let starName = isFavorited ? "star.fill" : "star"
        favoriteButton.setImage(UIImage(systemName: starName), for: .normal)
        favoriteButton.accessibilityLabel = isFavorited ? "Remove from favorites" : "Add to favorites"

        // Sync badge
        syncBadge.isHidden = !needsSync

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityValue = dateLabel.text
        accessibilityTraits = .button
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: isFavorited ? "Unfavorite" : "Favorite") { [weak self] _ in
                self?.onFavoriteToggle?()
                return true
            },
        ]
    }

    /// Applies a gradient cover when no image is available.
    func applyCoverGradient(colors: [CGColor]) {
        let gradient = CAGradientLayer()
        gradient.colors = colors
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = coverImageView.bounds
        gradient.cornerRadius = 10
        coverImageView.layer.insertSublayer(gradient, at: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadowContainer.layer.shadowPath = UIBezierPath(
            roundedRect: coverImageView.bounds,
            cornerRadius: 10
        ).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverImageView.image = nil
        coverImageView.layer.sublayers?.filter { $0 is CAGradientLayer }.forEach { $0.removeFromSuperlayer() }
        syncBadge.isHidden = true
        onFavoriteToggle = nil
        onTitleDropdown = nil
    }
}

// MARK: - FoldedCornerView

/// Draws the subtle folded page-corner triangle in the top-right of a cover.
private final class FoldedCornerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.close()

        ctx.setFillColor(UIColor.systemGray4.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }
}
