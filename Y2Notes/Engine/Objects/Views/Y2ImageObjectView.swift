import UIKit

// MARK: - Y2ImageObjectView

/// A `UIView` subclass that displays an embedded image on the canvas.
///
/// Loads full-resolution data from ``MediaFileManager`` lazily on first display
/// and falls back to the inline thumbnail for immediate rendering.
/// Supports border styles (none, thin, rounded, shadow) and opacity.
final class Y2ImageObjectView: UIView {

    // MARK: - Subviews

    private let imageView = UIImageView()
    private let borderLayer = CALayer()

    // MARK: - State

    private let imageObject: ImageObject
    private var isLoadingFull = false

    // MARK: - Init

    init(imageObject: ImageObject) {
        self.imageObject = imageObject
        super.init(frame: .zero)
        setupView()
        applyBorderStyle()
        loadThumbnail()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear
        alpha = imageObject.opacity

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = imageObject.originalFilename ?? "Image"
        accessibilityTraits = [.image]
        accessibilityHint = "Double-tap and hold to move or resize"
    }

    private func applyBorderStyle() {
        layer.masksToBounds = false
        switch imageObject.borderStyle {
        case .none:
            layer.borderWidth = 0
            layer.shadowOpacity = 0
        case .thin:
            layer.borderWidth = 1
            layer.borderColor = UIColor.separator.cgColor
            imageView.layer.cornerRadius = 0
        case .rounded:
            layer.borderWidth = 1.5
            layer.borderColor = UIColor.separator.cgColor
            imageView.layer.cornerRadius = 8
            imageView.clipsToBounds = true
        case .shadow:
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.25
            layer.shadowOffset = CGSize(width: 0, height: 2)
            layer.shadowRadius = 6
        }
    }

    // MARK: - Image loading

    private func loadThumbnail() {
        if let data = imageObject.thumbnailData, let img = UIImage(data: data) {
            imageView.image = img
        }
        loadFullResolution()
    }

    private func loadFullResolution() {
        guard !isLoadingFull else { return }
        isLoadingFull = true
        let path = imageObject.relativePath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = MediaFileManager.shared.loadImage(relativePath: path)
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async {
                if let img = image {
                    self?.imageView.image = img
                }
                self?.isLoadingFull = false
            }
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if imageObject.borderStyle == .shadow {
            layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        }
    }
}
