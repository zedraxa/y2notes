import UIKit

// MARK: - Y2ScannedDocObjectView

/// A `UIView` subclass that displays a scanned document page on the canvas.
///
/// Shows the scan thumbnail with a subtle page-badge overlay indicating the
/// original page index within the scan session.  Loads the full-resolution
/// scan image from Documents/Scans/ when available.
final class Y2ScannedDocObjectView: UIView {

    // MARK: - Subviews

    private let imageView = UIImageView()
    private let pageBadge = UILabel()

    // MARK: - State

    private let scannedDoc: ScannedDocObject

    // MARK: - Init

    init(scannedDoc: ScannedDocObject) {
        self.scannedDoc = scannedDoc
        super.init(frame: .zero)
        setupView()
        loadThumbnail()
        loadFullScan()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 6
        clipsToBounds = true
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor

        // Image
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        // Page badge
        pageBadge.text = "Page \(scannedDoc.pageIndex + 1)"
        pageBadge.font = .systemFont(ofSize: 10, weight: .medium)
        pageBadge.textColor = .white
        pageBadge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        pageBadge.textAlignment = .center
        pageBadge.layer.cornerRadius = 4
        pageBadge.clipsToBounds = true
        pageBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageBadge)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            pageBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            pageBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            pageBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            pageBadge.heightAnchor.constraint(equalToConstant: 18),
        ])

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "Scanned document, page \(scannedDoc.pageIndex + 1)"
        accessibilityTraits = [.image]
        accessibilityHint = "Double-tap to view full scan"
    }

    // MARK: - Image loading

    private func loadThumbnail() {
        if let data = scannedDoc.thumbnailData, let img = UIImage(data: data) {
            imageView.image = img
        }
    }

    private func loadFullScan() {
        let filename = scannedDoc.filename
        guard !filename.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Scans", isDirectory: true)
            let url = scansDir.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.imageView.image = image
            }
        }
    }
}
