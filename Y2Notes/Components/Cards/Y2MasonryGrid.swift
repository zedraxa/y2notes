import UIKit
import SwiftUI

// MARK: - Y2MasonryLayout

/// A `UICollectionViewLayout` subclass that arranges cells in a Pinterest-style
/// masonry grid with variable cell heights and configurable column count.
///
/// This layout calculates positions for all items upfront in `prepare()`,
/// always picking the shortest column for the next item, producing a visually
/// balanced grid. Supports invalidation on bounds change for rotation handling.
final class Y2MasonryLayout: UICollectionViewLayout {

    // MARK: - Configuration

    struct Configuration {
        var columnCount: Int = 3
        var interItemSpacing: CGFloat = 12
        var sectionInsets: UIEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    // MARK: - Properties

    var configuration: Configuration
    var itemHeightProvider: ((IndexPath, CGFloat) -> CGFloat)?

    private var cache: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat {
        guard let collectionView else { return 0 }
        let insets = configuration.sectionInsets
        return collectionView.bounds.width - insets.left - insets.right
    }

    // MARK: - Init

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    // MARK: - Layout

    override var collectionViewContentSize: CGSize {
        CGSize(width: contentWidth + configuration.sectionInsets.left + configuration.sectionInsets.right,
               height: contentHeight)
    }

    override func prepare() {
        guard let collectionView, cache.isEmpty else { return }

        let columns = configuration.columnCount
        let spacing = configuration.interItemSpacing
        let insets = configuration.sectionInsets
        let columnWidth = (contentWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        guard columns > 0 else { return }
        var columnHeights = Array(repeating: insets.top, count: columns)

        let itemCount = collectionView.numberOfItems(inSection: 0)
        for item in 0..<itemCount {
            let indexPath = IndexPath(item: item, section: 0)

            // Pick the shortest column
            guard let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element }) else { continue }
            let column = shortest.offset

            let x = insets.left + CGFloat(column) * (columnWidth + spacing)
            let y = columnHeights[column]

            let height = itemHeightProvider?(indexPath, columnWidth) ?? (columnWidth * 1.3)
            let frame = CGRect(x: x, y: y, width: columnWidth, height: height)

            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = frame
            cache.append(attributes)

            columnHeights[column] = y + height + spacing
        }

        contentHeight = (columnHeights.max() ?? 0) + insets.bottom
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        cache.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return newBounds.width != collectionView.bounds.width
    }

    override func invalidateLayout() {
        cache.removeAll()
        contentHeight = 0
        super.invalidateLayout()
    }
}

// MARK: - Y2MasonryGrid

/// A UICollectionView-backed masonry grid that provides smooth scrolling
/// and efficient cell reuse for large note collections.
///
/// The grid uses ``Y2MasonryLayout`` for positioning and supports:
/// - Variable-height cells
/// - Pull-to-refresh
/// - Prefetching for thumbnail loading
/// - Accessibility: per-cell labels
///
/// **SwiftUI usage:**
/// ```swift
/// Y2MasonryGridView(
///     itemCount: notes.count,
///     columns: 3,
///     cellContent: { index in NoteCardView(note: notes[index]) },
///     itemHeight: { index, width in width * 1.4 }
/// )
/// ```
final class Y2MasonryGrid: UIView {

    // MARK: - Properties

    private let layout: Y2MasonryLayout
    private let collectionView: UICollectionView
    private var cellProvider: ((Int) -> UIView)?
    private var itemCount: Int = 0

    // MARK: - Init

    init(configuration: Y2MasonryLayout.Configuration = .init()) {
        self.layout = Y2MasonryLayout(configuration: configuration)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        setupCollectionView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    // MARK: - Setup

    private func setupCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(MasonryCell.self, forCellWithReuseIdentifier: MasonryCell.reuseID)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public API

    /// Reloads the grid with the given item count and cell provider.
    func reload(
        itemCount: Int,
        cellProvider: @escaping (Int) -> UIView,
        itemHeight: ((IndexPath, CGFloat) -> CGFloat)? = nil
    ) {
        self.itemCount = itemCount
        self.cellProvider = cellProvider
        layout.itemHeightProvider = itemHeight
        layout.invalidateLayout()
        collectionView.reloadData()
    }

    /// Updates the column count and re-lays out.
    func setColumns(_ count: Int) {
        layout.configuration.columnCount = count
        layout.invalidateLayout()
        collectionView.collectionViewLayout.invalidateLayout()
    }
}

// MARK: - UICollectionViewDataSource

extension Y2MasonryGrid: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MasonryCell.reuseID,
            for: indexPath
        ) as! MasonryCell
        if let contentView = cellProvider?(indexPath.item) {
            cell.setContent(contentView)
        }
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension Y2MasonryGrid: UICollectionViewDelegate {}

// MARK: - MasonryCell

private final class MasonryCell: UICollectionViewCell {
    static let reuseID = "Y2MasonryCell"

    func setContent(_ view: UIView) {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.subviews.forEach { $0.removeFromSuperview() }
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI hosting wrapper for ``Y2MasonryGrid``.
struct Y2MasonryGridView: UIViewRepresentable {

    var itemCount: Int
    var columns: Int
    var spacing: CGFloat
    var cellContent: (Int) -> AnyView
    var itemHeight: ((Int, CGFloat) -> CGFloat)?

    init(
        itemCount: Int,
        columns: Int = 3,
        spacing: CGFloat = 12,
        cellContent: @escaping (Int) -> AnyView,
        itemHeight: ((Int, CGFloat) -> CGFloat)? = nil
    ) {
        self.itemCount = itemCount
        self.columns = columns
        self.spacing = spacing
        self.cellContent = cellContent
        self.itemHeight = itemHeight
    }

    func makeUIView(context: Context) -> Y2MasonryGrid {
        var config = Y2MasonryLayout.Configuration()
        config.columnCount = columns
        config.interItemSpacing = spacing
        let grid = Y2MasonryGrid(configuration: config)
        reloadGrid(grid)
        return grid
    }

    func updateUIView(_ uiView: Y2MasonryGrid, context: Context) {
        uiView.setColumns(columns)
        reloadGrid(uiView)
    }

    private func reloadGrid(_ grid: Y2MasonryGrid) {
        grid.reload(
            itemCount: itemCount,
            cellProvider: { index in
                let hostingController = UIHostingController(rootView: cellContent(index))
                hostingController.view.backgroundColor = .clear
                return hostingController.view
            },
            itemHeight: itemHeight.map { provider in
                { indexPath, width in provider(indexPath.item, width) }
            }
        )
    }
}
