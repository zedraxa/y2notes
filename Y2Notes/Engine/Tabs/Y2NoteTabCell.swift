import UIKit

// MARK: - Y2NoteTabCell

/// UICollectionViewCell for a single tab in the note tab bar.
///
/// **Design (from reference):**
/// - Color indicator dot (current ink color of that note).
/// - Note title (truncated to fit).
/// - Dropdown chevron on active tab.
/// - Close (✕) button.
/// - Active tab: bold font, underline accent bar.
final class Y2NoteTabCell: UICollectionViewCell {

    static let reuseID = "Y2NoteTabCell"

    // MARK: - Callbacks

    var onClose: (() -> Void)?
    var onDropdown: (() -> Void)?

    // MARK: - Subviews

    private let colorDot: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.adjustsFontForContentSizeCategory = true
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let chevronButton: UIButton = {
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.down", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.tintColor = .secondaryLabel
        btn.isHidden = true
        return btn
    }()

    private let closeButton: UIButton = {
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        btn.tintColor = .tertiaryLabel
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let underlineBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

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
        let stack = UIStackView(arrangedSubviews: [colorDot, titleLabel, chevronButton, closeButton])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        contentView.addSubview(underlineBar)

        NSLayoutConstraint.activate([
            colorDot.widthAnchor.constraint(equalToConstant: 10),
            colorDot.heightAnchor.constraint(equalToConstant: 10),

            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            underlineBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            underlineBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            underlineBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            underlineBar.heightAnchor.constraint(equalToConstant: 2.5),
        ])
    }

    private func setupActions() {
        closeButton.addAction(UIAction { [weak self] _ in
            self?.onClose?()
        }, for: .touchUpInside)

        chevronButton.addAction(UIAction { [weak self] _ in
            self?.onDropdown?()
        }, for: .touchUpInside)
    }

    // MARK: - Configuration

    func configure(
        title: String,
        inkColor: UIColor,
        isActive: Bool,
        accentColor: UIColor
    ) {
        titleLabel.text = title
        colorDot.backgroundColor = inkColor

        // Active vs inactive styling
        if isActive {
            titleLabel.font = .preferredFont(forTextStyle: .subheadline).withTraits(.traitBold)
            titleLabel.textColor = .label
            chevronButton.isHidden = false
            underlineBar.isHidden = false
            underlineBar.backgroundColor = accentColor
            closeButton.tintColor = .secondaryLabel
        } else {
            titleLabel.font = .preferredFont(forTextStyle: .subheadline)
            titleLabel.textColor = .secondaryLabel
            chevronButton.isHidden = true
            underlineBar.isHidden = true
            closeButton.tintColor = .tertiaryLabel
        }

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = isActive ? [.button, .selected] : .button
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Close tab") { [weak self] _ in
                self?.onClose?()
                return true
            },
        ]
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        onClose = nil
        onDropdown = nil
        chevronButton.isHidden = true
        underlineBar.isHidden = true
    }
}

// MARK: - UIFont helper

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
