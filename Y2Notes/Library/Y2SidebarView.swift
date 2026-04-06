import UIKit

// MARK: - Sidebar Item Model

/// Describes a single row in the library sidebar.
struct Y2SidebarItem: Hashable {
    enum Kind: Hashable {
        case documents, favorites, shared, study, marketplace, notebook(UUID)
    }
    let kind: Kind
    let title: String
    let iconName: String          // SF Symbol name
    var badgeCount: Int = 0
}

// MARK: - Y2SidebarView

/// UIKit sidebar for the library screen.
///
/// Shows a logo header, navigation items (Documents, Favorites, Shared, Study,
/// Marketplace), and a dynamic notebooks list.  Selection is communicated via
/// a delegate callback.
///
/// **Design notes (from reference screenshots):**
/// - Narrow width (~280 pt) with minimal visual weight.
/// - Selected item uses filled icon + tinted background.
/// - Notebook rows show cover color dot.
final class Y2SidebarView: UIView {

    // MARK: - Delegate

    /// Callback when the user selects a sidebar item.
    var onSelect: ((Y2SidebarItem) -> Void)?

    // MARK: - Data

    private var items: [Y2SidebarItem] = []
    private var selectedItem: Y2SidebarItem?

    // MARK: - Subviews

    private let logoLabel: UILabel = {
        let label = UILabel()
        label.text = "Y2Notes"
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityTraits = .header
        return label
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        tv.register(SidebarCell.self, forCellReuseIdentifier: SidebarCell.reuseID)
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.rowHeight = 44
        return tv
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    // MARK: - Layout

    private func setupLayout() {
        backgroundColor = .systemGroupedBackground
        addSubview(logoLabel)
        addSubview(tableView)

        NSLayoutConstraint.activate([
            logoLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            logoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            logoLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public API

    /// Replaces sidebar items and reloads.
    func setItems(_ newItems: [Y2SidebarItem], selected: Y2SidebarItem? = nil) {
        items = newItems
        selectedItem = selected ?? newItems.first
        tableView.reloadData()
    }

    /// Programmatically selects an item.
    func select(_ item: Y2SidebarItem) {
        selectedItem = item
        tableView.reloadData()
        onSelect?(item)
    }

    /// Updates the theme text color.
    func applyTheme(textColor: UIColor, accentColor: UIColor) {
        logoLabel.textColor = textColor
        tintColor = accentColor
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource & Delegate

extension Y2SidebarView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: SidebarCell.reuseID, for: indexPath) as! SidebarCell
        let item = items[indexPath.row]
        let isSelected = item == selectedItem
        cell.configure(item: item, isSelected: isSelected, accent: tintColor)
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt indexPath: IndexPath) {
        tv.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        selectedItem = item
        tv.reloadData()
        onSelect?(item)
    }
}

// MARK: - SidebarCell

private final class SidebarCell: UITableViewCell {
    static let reuseID = "Y2SidebarCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let badgeLabel = UILabel()
    private let selectionPill = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none

        selectionPill.layer.cornerRadius = 8
        selectionPill.layer.cornerCurve = .continuous
        selectionPill.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionPill)

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(iconView)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 9
        badgeLabel.layer.masksToBounds = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            selectionPill.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            selectionPill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            selectionPill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            selectionPill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),

            iconView.leadingAnchor.constraint(equalTo: selectionPill.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -6),

            badgeLabel.trailingAnchor.constraint(equalTo: selectionPill.trailingAnchor, constant: -10),
            badgeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    func configure(item: Y2SidebarItem, isSelected: Bool, accent: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: isSelected ? .semibold : .regular)
        let symbolName = isSelected ? (item.iconName + ".fill") : item.iconName
        iconView.image = UIImage(systemName: symbolName, withConfiguration: config)
            ?? UIImage(systemName: item.iconName, withConfiguration: config)

        titleLabel.text = item.title
        titleLabel.font = isSelected
            ? .preferredFont(forTextStyle: .body).withTraits(.traitBold)
            : .preferredFont(forTextStyle: .body)

        let tint = isSelected ? accent : .label
        iconView.tintColor = tint
        titleLabel.textColor = tint

        selectionPill.backgroundColor = isSelected ? accent.withAlphaComponent(0.12) : .clear

        if item.badgeCount > 0 {
            badgeLabel.isHidden = false
            badgeLabel.text = "\(item.badgeCount)"
            badgeLabel.backgroundColor = accent
        } else {
            badgeLabel.isHidden = true
        }

        // Accessibility
        accessibilityLabel = item.title
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        if item.badgeCount > 0 {
            accessibilityValue = "\(item.badgeCount) new"
        }
    }
}

// MARK: - UIFont helper

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
