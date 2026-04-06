import UIKit

// MARK: - Tab Bar Delegate

/// Delegate protocol for tab bar actions.
protocol Y2NoteTabBarDelegate: AnyObject {
    func tabBarDidSelectTab(noteID: UUID)
    func tabBarDidCloseTab(noteID: UUID)
    func tabBarDidRequestNewTab()
    func tabBarDidRequestTabOptions(noteID: UUID, sourceView: UIView)
}

// MARK: - Tab Display Model

/// Lightweight display model for a single tab.
struct TabDisplayItem: Hashable {
    let noteID: UUID
    let title: String
    let inkColor: UIColor

    func hash(into hasher: inout Hasher) { hasher.combine(noteID) }
    static func == (lhs: TabDisplayItem, rhs: TabDisplayItem) -> Bool { lhs.noteID == rhs.noteID }
}

// MARK: - Y2NoteTabBar

/// Horizontally scrollable tab bar for multiple open notes.
///
/// **Design (from reference):**
/// - Each tab: color dot + title + chevron (active) + close ✕.
/// - Active tab: bold, underline accent bar.
/// - "+" button at trailing edge to open new note.
/// - Maximum ~10 open tabs.
/// - Drag to reorder supported.
final class Y2NoteTabBar: UIView {

    // MARK: - Properties

    weak var tabDelegate: Y2NoteTabBarDelegate?
    var accentColor: UIColor = .systemBlue { didSet { collectionView.reloadData() } }

    private var tabs: [TabDisplayItem] = []
    private var activeNoteID: UUID?

    // MARK: - Subviews

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.estimatedItemSize = CGSize(width: 150, height: 36)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.delegate = self
        cv.dataSource = self
        cv.register(Y2NoteTabCell.self, forCellWithReuseIdentifier: Y2NoteTabCell.reuseID)
        return cv
    }()

    private let addButton: UIButton = {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        btn.tintColor = .secondaryLabel
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityLabel = NSLocalizedString("Open new note", comment: "Tab bar add button")
        return btn
    }()

    private let bottomSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
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
        backgroundColor = .systemBackground

        addSubview(collectionView)
        addSubview(addButton)
        addSubview(bottomSeparator)

        addButton.addAction(UIAction { [weak self] _ in
            self?.tabDelegate?.tabBarDidRequestNewTab()
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),
            collectionView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            addButton.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 30),

            bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 40)
    }

    // MARK: - Public API

    /// Updates the tab bar with fresh tab data.
    func setTabs(_ items: [TabDisplayItem], activeID: UUID?) {
        tabs = items
        activeNoteID = activeID
        collectionView.reloadData()

        // Scroll to active tab
        if let activeID, let idx = tabs.firstIndex(where: { $0.noteID == activeID }) {
            collectionView.scrollToItem(
                at: IndexPath(item: idx, section: 0),
                at: .centeredHorizontally,
                animated: true
            )
        }
    }

    /// Returns whether tabs are empty (no notes open).
    var isEmpty: Bool { tabs.isEmpty }
}

// MARK: - UICollectionViewDataSource

extension Y2NoteTabBar: UICollectionViewDataSource {

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabs.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(
            withReuseIdentifier: Y2NoteTabCell.reuseID, for: indexPath
        ) as! Y2NoteTabCell

        let tab = tabs[indexPath.item]
        let isActive = tab.noteID == activeNoteID

        cell.configure(
            title: tab.title,
            inkColor: tab.inkColor,
            isActive: isActive,
            accentColor: accentColor
        )

        cell.onClose = { [weak self] in
            self?.tabDelegate?.tabBarDidCloseTab(noteID: tab.noteID)
        }

        cell.onDropdown = { [weak self] in
            self?.tabDelegate?.tabBarDidRequestTabOptions(noteID: tab.noteID, sourceView: cell)
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension Y2NoteTabBar: UICollectionViewDelegate {

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tab = tabs[indexPath.item]
        activeNoteID = tab.noteID
        tabDelegate?.tabBarDidSelectTab(noteID: tab.noteID)
        cv.reloadData()
    }
}
