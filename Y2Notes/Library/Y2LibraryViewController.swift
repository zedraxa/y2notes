import UIKit

// MARK: - Library Delegate

/// Delegate for library-level actions that the host (SwiftUI) handles.
protocol Y2LibraryDelegate: AnyObject {
    func libraryDidSelectNotebook(id: UUID)
    func libraryDidRequestNewNotebook()
    func libraryDidToggleFavorite(notebookID: UUID)
    func libraryDidRequestDelete(notebookID: UUID)
    func libraryDidChangeSidebarSection(_ section: Y2SidebarItem.Kind)
}

// MARK: - Notebook Display Model

/// Lightweight display model — decoupled from the persistence layer.
struct NotebookDisplayItem: Hashable {
    let id: UUID
    let title: String
    let modifiedAt: Date
    let coverImage: UIImage?
    let coverGradientColors: [CGColor]?
    let isFavorited: Bool
    let needsSync: Bool
}

// MARK: - Y2LibraryViewController

/// UIKit split-view library controller.
///
/// **LEFT**: Sidebar with navigation items (Documents, Favorites, …).
/// **RIGHT**: Notebook grid (3-column adaptive on iPad) with rich card cells
/// and a dashed "+" new-notebook cell at the end.
///
/// This controller is fully self-contained — it receives display data via
/// `setNotebooks(_:)` and communicates back via `Y2LibraryDelegate`.
final class Y2LibraryViewController: UISplitViewController {

    // MARK: - Properties

    weak var libraryDelegate: Y2LibraryDelegate?

    private let sidebar = Y2SidebarView()
    private var notebooks: [NotebookDisplayItem] = []

    private lazy var gridController = makeGridController()

    // MARK: - Lifecycle

    init() {
        super.init(style: .doubleColumn)
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        preferredPrimaryColumnWidth = 280
        minimumPrimaryColumnWidth = 240
        maximumPrimaryColumnWidth = 320
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let sidebarVC = UIViewController()
        sidebarVC.view = sidebar
        setViewController(sidebarVC, for: .primary)
        setViewController(gridController, for: .secondary)

        configureSidebar()
    }

    // MARK: - Sidebar Configuration

    private func configureSidebar() {
        let items: [Y2SidebarItem] = [
            .init(kind: .documents, title: NSLocalizedString("Documents", comment: ""),
                  iconName: "folder"),
            .init(kind: .favorites, title: NSLocalizedString("Favorites", comment: ""),
                  iconName: "bookmark"),
            .init(kind: .shared, title: NSLocalizedString("Shared", comment: ""),
                  iconName: "person.2"),
            .init(kind: .study, title: NSLocalizedString("Study", comment: ""),
                  iconName: "graduationcap"),
            .init(kind: .marketplace, title: NSLocalizedString("Marketplace", comment: ""),
                  iconName: "storefront"),
        ]
        sidebar.setItems(items, selected: items.first)
        sidebar.onSelect = { [weak self] item in
            self?.libraryDelegate?.libraryDidChangeSidebarSection(item.kind)
        }
    }

    // MARK: - Grid Controller

    private func makeGridController() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground

        // Top bar
        let topBar = makeTopBar()
        vc.view.addSubview(topBar)

        // Collection view
        let cv = makeCollectionView()
        vc.view.addSubview(cv)
        self.collectionView = cv

        topBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 52),

            cv.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            cv.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
        ])

        return vc
    }

    // MARK: - Top Bar

    private func makeTopBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = .systemBackground

        // "+ New" button
        var newConfig = UIButton.Configuration.filled()
        newConfig.title = NSLocalizedString("New", comment: "Create new notebook")
        newConfig.image = UIImage(systemName: "plus")
        newConfig.imagePadding = 4
        newConfig.cornerStyle = .capsule
        newConfig.baseBackgroundColor = .systemBlue
        newConfig.baseForegroundColor = .white
        let newButton = UIButton(configuration: newConfig)
        newButton.addAction(UIAction { [weak self] _ in
            self?.libraryDelegate?.libraryDidRequestNewNotebook()
        }, for: .touchUpInside)
        newButton.translatesAutoresizingMaskIntoConstraints = false
        newButton.accessibilityLabel = NSLocalizedString("Create new notebook", comment: "")
        bar.addSubview(newButton)

        // Search button
        let searchButton = UIButton(type: .system)
        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.accessibilityLabel = NSLocalizedString("Search", comment: "")
        bar.addSubview(searchButton)

        NSLayoutConstraint.activate([
            newButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            newButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            searchButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            searchButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return bar
    }

    // MARK: - Collection View

    private weak var collectionView: UICollectionView?

    private func makeCollectionView() -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, env in
            self?.makeGridSection(environment: env)
        }

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.register(Y2NotebookCardCell.self, forCellWithReuseIdentifier: Y2NotebookCardCell.reuseID)
        cv.register(Y2NewButtonCell.self, forCellWithReuseIdentifier: Y2NewButtonCell.reuseID)
        return cv
    }

    private func makeGridSection(
        environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let width = environment.container.effectiveContentSize.width
        let columns = max(2, Int(width / 200))
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .estimated(260)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(260)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        return section
    }

    // MARK: - Public API

    /// Updates the grid with fresh notebook display data.
    func setNotebooks(_ items: [NotebookDisplayItem]) {
        notebooks = items
        collectionView?.reloadData()
    }

    /// Applies theme colors to sidebar and grid.
    func applyTheme(textColor: UIColor, accentColor: UIColor) {
        sidebar.applyTheme(textColor: textColor, accentColor: accentColor)
        view.tintColor = accentColor
    }
}

// MARK: - UICollectionViewDataSource

extension Y2LibraryViewController: UICollectionViewDataSource {

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        notebooks.count + 1  // +1 for "New" button
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == notebooks.count {
            return cv.dequeueReusableCell(withReuseIdentifier: Y2NewButtonCell.reuseID, for: indexPath)
        }

        let cell = cv.dequeueReusableCell(
            withReuseIdentifier: Y2NotebookCardCell.reuseID, for: indexPath
        ) as! Y2NotebookCardCell

        let item = notebooks[indexPath.item]
        cell.configure(
            coverImage: item.coverImage,
            title: item.title,
            date: item.modifiedAt,
            isFavorited: item.isFavorited,
            needsSync: item.needsSync
        )

        if item.coverImage == nil, let colors = item.coverGradientColors {
            cell.applyCoverGradient(colors: colors)
        }

        cell.onFavoriteToggle = { [weak self] in
            self?.libraryDelegate?.libraryDidToggleFavorite(notebookID: item.id)
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension Y2LibraryViewController: UICollectionViewDelegate {

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == notebooks.count {
            libraryDelegate?.libraryDidRequestNewNotebook()
        } else {
            libraryDelegate?.libraryDidSelectNotebook(id: notebooks[indexPath.item].id)
        }
    }

    func collectionView(
        _ cv: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let first = indexPaths.first, first.item < notebooks.count else { return nil }
        let item = notebooks[first.item]

        return UIContextMenuConfiguration(actionProvider: { _ in
            let fav = UIAction(
                title: item.isFavorited
                    ? NSLocalizedString("Unfavorite", comment: "")
                    : NSLocalizedString("Favorite", comment: ""),
                image: UIImage(systemName: item.isFavorited ? "star.slash" : "star")
            ) { [weak self] _ in
                self?.libraryDelegate?.libraryDidToggleFavorite(notebookID: item.id)
            }

            let delete = UIAction(
                title: NSLocalizedString("Delete", comment: ""),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.libraryDelegate?.libraryDidRequestDelete(notebookID: item.id)
            }

            return UIMenu(children: [fav, delete])
        })
    }
}
