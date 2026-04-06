import UIKit

// MARK: - Y2NewButtonView

/// Dashed-border "+" cell shown at the end of the notebook grid.
///
/// **Design (from reference):** Dashed blue border rectangle with a "+" icon
/// and "New" label, clearly distinguished from filled notebook cards.
final class Y2NewButtonCell: UICollectionViewCell {

    static let reuseID = "Y2NewButtonCell"

    // MARK: - Subviews

    private let dashedBorder = CAShapeLayer()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let plusIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "plus", withConfiguration: config))
        iv.tintColor = .systemBlue
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let newLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("New", comment: "New notebook button label")
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .systemBlue
        label.textAlignment = .center
        return label
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        setupAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupLayout() {
        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous

        // Dashed border
        dashedBorder.strokeColor = UIColor.systemBlue.cgColor
        dashedBorder.fillColor = UIColor.clear.cgColor
        dashedBorder.lineWidth = 2
        dashedBorder.lineDashPattern = [6, 4]
        dashedBorder.lineJoin = .round
        contentView.layer.addSublayer(dashedBorder)

        stackView.addArrangedSubview(plusIcon)
        stackView.addArrangedSubview(newLabel)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("Create new notebook", comment: "New notebook button a11y")
        accessibilityTraits = .button
    }

    // MARK: - Dashed border path update

    override func layoutSubviews() {
        super.layoutSubviews()
        dashedBorder.path = UIBezierPath(
            roundedRect: contentView.bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: 10
        ).cgPath
        dashedBorder.frame = contentView.bounds
    }

    /// Updates the accent color used for the dashed border and icons.
    func applyAccent(_ color: UIColor) {
        dashedBorder.strokeColor = color.cgColor
        plusIcon.tintColor = color
        newLabel.textColor = color
    }
}
