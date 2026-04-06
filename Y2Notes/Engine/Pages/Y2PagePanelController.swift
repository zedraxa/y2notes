import UIKit

// MARK: - Page Panel Delegate

/// Delegate protocol for page panel actions.
protocol Y2PagePanelDelegate: AnyObject {
    func pagePanelDidSelectPage(at index: Int)
    func pagePanelDidRequestAddPage()
    func pagePanelDidRequestDeletePage(at index: Int)
    func pagePanelDidReorderPage(from sourceIndex: Int, to destinationIndex: Int)
    func pagePanelDidToggleBookmark(at index: Int)
    func pagePanelDidRequestClose()
}

// MARK: - Page Display Item

/// Lightweight display model for a single page in the panel.
struct PageDisplayItem {
    let index: Int
    let thumbnail: UIImage?
    let isBookmarked: Bool
    let isLoading: Bool
}

// MARK: - Y2PagePanelController

/// Slide-in page management panel shown alongside the editor canvas.
///
/// **Design (from reference):**
/// - Header: "…" more button, "Pages" title, "✕" close button.
/// - View mode segmented control: Grid / List / Outline.
/// - Filter dropdown: "All pages ▼".
/// - 2-column page grid with thumbnail cells.
/// - "+" add page button (dashed blue border) at bottom.
/// - Selected page highlighted with blue border.
///
/// The panel communicates with the editor via `Y2PagePanelDelegate`.
final class Y2PagePanelController: UIViewController {

    // MARK: - Properties

    weak var panelDelegate: Y2PagePanelDelegate?
    var selectedPageIndex: Int = 0

    private var pages: [PageDisplayItem] = []
    private let thumbnailRenderer = Y2PageThumbnailRenderer()

    // MARK: - Preferred Width

    /// The panel occupies this width when presented alongside the canvas.
    static let preferredWidth: CGFloat = 280

    // MARK: - Subviews

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.register(Y2PageCell.self, forCellWithReuseIdentifier: Y2PageCell.reuseID)
        cv.register(AddPageCell.self, forCellWithReuseIdentifier: AddPageCell.reuseID)
        return cv
    }()

    private let headerView = UIView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        setupHeader()
        setupCollectionView()
    }

    // MARK: - Header

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        // More button (…)
        let moreButton = UIButton(type: .system)
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.accessibilityLabel = NSLocalizedString("More options", comment: "")
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(moreButton)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Pages", comment: "Page panel title")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.accessibilityTraits = .header
        headerView.addSubview(titleLabel)

        // Close button (✕)
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = NSLocalizedString("Close page panel", comment: "")
        closeButton.addAction(UIAction { [weak self] _ in
            self?.panelDelegate?.pagePanelDidRequestClose()
        }, for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)

        // View mode segmented control
        let segmented = UISegmentedControl(items: [
            UIImage(systemName: "square.grid.2x2")!,
            UIImage(systemName: "list.bullet")!,
            UIImage(systemName: "list.number")!,
        ])
        segmented.selectedSegmentIndex = 0
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.accessibilityLabel = NSLocalizedString("View mode", comment: "")
        headerView.addSubview(segmented)

        // Separator
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(separator)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 96),

            moreButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            moreButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 12),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),

            segmented.topAnchor.constraint(equalTo: moreButton.bottomAnchor, constant: 12),
            segmented.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            segmented.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),

            separator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    // MARK: - Collection View

    private func setupCollectionView() {
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, env in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .estimated(180)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(180)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            return section
        }
    }

    // MARK: - Public API

    /// Updates the page grid with new display data.
    func setPages(_ items: [PageDisplayItem], selectedIndex: Int) {
        pages = items
        selectedPageIndex = selectedIndex
        collectionView.reloadData()
    }

    /// Scrolls to ensure the selected page is visible.
    func scrollToSelectedPage(animated: Bool = true) {
        guard selectedPageIndex < pages.count else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: selectedPageIndex, section: 0),
            at: .centeredVertically,
            animated: animated
        )
    }

    /// Invalidates a thumbnail in the renderer cache.
    func invalidateThumbnail(noteID: UUID, pageIndex: Int) {
        thumbnailRenderer.invalidate(noteID: noteID, pageIndex: pageIndex)
    }
}

// MARK: - UICollectionViewDataSource

extension Y2PagePanelController: UICollectionViewDataSource {

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages.count + 1  // +1 for "Add Page" cell
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == pages.count {
            return cv.dequeueReusableCell(withReuseIdentifier: AddPageCell.reuseID, for: indexPath)
        }

        let cell = cv.dequeueReusableCell(
            withReuseIdentifier: Y2PageCell.reuseID, for: indexPath
        ) as! Y2PageCell

        let page = pages[indexPath.item]
        cell.configure(
            thumbnailImage: page.thumbnail,
            pageNumber: page.index + 1,
            isBookmarked: page.isBookmarked,
            isSelected: page.index == selectedPageIndex,
            isLoading: page.isLoading
        )

        cell.onBookmarkToggle = { [weak self] in
            self?.panelDelegate?.pagePanelDidToggleBookmark(at: page.index)
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension Y2PagePanelController: UICollectionViewDelegate {

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == pages.count {
            panelDelegate?.pagePanelDidRequestAddPage()
        } else {
            let page = pages[indexPath.item]
            selectedPageIndex = page.index
            panelDelegate?.pagePanelDidSelectPage(at: page.index)
            cv.reloadData()
        }
    }
}

// MARK: - AddPageCell

/// Dashed "+" cell at the bottom of the page grid.
private final class AddPageCell: UICollectionViewCell {
    static let reuseID = "Y2AddPageCell"

    private let dashedBorder = CAShapeLayer()
    private let plusIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        dashedBorder.strokeColor = UIColor.systemBlue.cgColor
        dashedBorder.fillColor = UIColor.clear.cgColor
        dashedBorder.lineWidth = 1.5
        dashedBorder.lineDashPattern = [5, 3]
        dashedBorder.lineJoin = .round
        contentView.layer.addSublayer(dashedBorder)

        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        plusIcon.image = UIImage(systemName: "plus", withConfiguration: config)
        plusIcon.tintColor = .systemBlue
        plusIcon.contentMode = .scaleAspectFit
        plusIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(plusIcon)

        NSLayoutConstraint.activate([
            plusIcon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("Add page", comment: "")
        accessibilityTraits = .button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashedBorder.path = UIBezierPath(
            roundedRect: contentView.bounds.insetBy(dx: 1, dy: 1), cornerRadius: 6
        ).cgPath
        dashedBorder.frame = contentView.bounds
    }
}
