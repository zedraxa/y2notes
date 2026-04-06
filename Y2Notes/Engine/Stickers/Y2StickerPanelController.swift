import UIKit

// MARK: - Y2StickerPanelDelegate

protocol Y2StickerPanelDelegate: AnyObject {
    /// Called when the user selects a sticker to place on the canvas.
    func stickerPanel(_ panel: Y2StickerPanelController, didSelect sticker: StickerObject)
}

// MARK: - Y2StickerPanelController

/// Popover/panel showing all sticker categories and their stickers.
///
/// Tapping a sticker immediately calls the delegate; drag-to-place is handled
/// by the overlay controller.
final class Y2StickerPanelController: UIViewController {

    // MARK: - Layout constants

    private enum Metrics {
        static let columnCount = 4
        static let itemSpacing: CGFloat = 8
        static let sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        static let stickerSize = CGSize(width: 68, height: 68)
    }

    // MARK: - Dependencies

    weak var delegate: Y2StickerPanelDelegate?

    // MARK: - Subviews

    private var collectionView: UICollectionView!
    private let searchBar = UISearchBar()

    // MARK: - State

    private var allCategories: [String] = []
    private var filteredCategories: [String] = []
    private var stickersByCategory: [String: [StickerDefinition]] = [:]
    private var allStickers: [StickerDefinition] = []
    private var filteredStickers: [StickerDefinition] = []
    private var isSearching = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Elements"
        view.backgroundColor = .systemBackground
        loadStickers()
        setupSearch()
        setupCollectionView()
    }

    // MARK: - Data loading

    private func loadStickers() {
        allStickers = StickerRegistry.shared.allPacks.flatMap { $0.stickers }
        var categoryMap: [String: [StickerDefinition]] = [:]
        for sticker in allStickers {
            categoryMap[sticker.category, default: []].append(sticker)
        }
        stickersByCategory = categoryMap
        allCategories = categoryMap.keys.sorted()
        filteredCategories = allCategories
    }

    // MARK: - Search

    private func setupSearch() {
        searchBar.placeholder = "Search stickers"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Collection view

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Metrics.itemSpacing
        layout.minimumLineSpacing = Metrics.itemSpacing
        layout.sectionInset = Metrics.sectionInset
        layout.headerReferenceSize = CGSize(width: 0, height: 36)
        layout.itemSize = Metrics.stickerSize

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.register(StickerCell.self, forCellWithReuseIdentifier: "StickerCell")
        collectionView.register(
            StickerCategoryHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: "StickerCategoryHeader"
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchBar)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: 44),

            collectionView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - UICollectionViewDataSource

extension Y2StickerPanelController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        isSearching ? 1 : filteredCategories.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isSearching { return filteredStickers.count }
        let cat = filteredCategories[section]
        return stickersByCategory[cat]?.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "StickerCell", for: indexPath
        ) as! StickerCell
        let def = stickerDefinition(at: indexPath)
        cell.configure(with: def)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: "StickerCategoryHeader", for: indexPath
        ) as! StickerCategoryHeader
        let title = isSearching ? "Results" : filteredCategories[indexPath.section]
        header.titleLabel.text = title
        return header
    }

    private func stickerDefinition(at indexPath: IndexPath) -> StickerDefinition {
        if isSearching { return filteredStickers[indexPath.item] }
        let cat = filteredCategories[indexPath.section]
        return stickersByCategory[cat]![indexPath.item]
    }
}

// MARK: - UICollectionViewDelegate

extension Y2StickerPanelController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let def = stickerDefinition(at: indexPath)
        let sticker = StickerObject(
            stickerID: def.id,
            category: def.category,
            isBuiltIn: true
        )
        delegate?.stickerPanel(self, didSelect: sticker)
        dismiss(animated: true)
    }
}

// MARK: - UISearchBarDelegate

extension Y2StickerPanelController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            isSearching = false
            filteredCategories = allCategories
        } else {
            isSearching = true
            let query = searchText.lowercased()
            filteredStickers = allStickers.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.category.lowercased().contains(query) ||
                $0.id.lowercased().contains(query)
            }
        }
        collectionView.reloadData()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        isSearching = false
        filteredCategories = allCategories
        collectionView.reloadData()
    }
}

// MARK: - StickerCell (private)

private final class StickerCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 9)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.75),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = [.button, .image]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with def: StickerDefinition) {
        label.text = def.displayName
        accessibilityLabel = def.displayName

        // Attempt CG-rendered sticker; fall back to SF Symbol
        if let image = BuiltInStickerPack.shared.render(
            stickerID: def.id,
            size: CGSize(width: 52, height: 52)
        ) {
            imageView.image = image
        } else {
            imageView.image = UIImage(systemName: def.symbolFallback)?
                .withTintColor(.label, renderingMode: .alwaysOriginal)
        }
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.6 : 1 }
    }
}

// MARK: - StickerCategoryHeader (private)

private final class StickerCategoryHeader: UICollectionReusableView {
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
