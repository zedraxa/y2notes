import UIKit

// MARK: - Y2StickerObjectView

/// A `UIView` subclass that renders a sticker on the canvas.
///
/// Built-in stickers are drawn via Core Graphics closures registered in
/// ``BuiltInStickerPack``.  Third-party or imported stickers use cached PNG data.
/// Optional tint colour is applied using `.alwaysTemplate` rendering mode.
final class Y2StickerObjectView: UIView {

    // MARK: - Subviews

    private let imageView = UIImageView()

    // MARK: - State

    private let stickerObject: StickerObject

    // MARK: - Init

    init(stickerObject: StickerObject) {
        self.stickerObject = stickerObject
        super.init(frame: .zero)
        setupView()
        loadSticker()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Sticker: \(stickerObject.stickerID)"
        accessibilityTraits = [.image]
    }

    private func loadSticker() {
        // Try built-in CG-rendered sticker first.
        if stickerObject.isBuiltIn,
           let image = BuiltInStickerPack.shared.render(
               stickerID: stickerObject.stickerID,
               size: CGSize(width: 200, height: 200)
           ) {
            applyImage(image)
            return
        }
        // Fall back to inline PNG data.
        if let data = stickerObject.stickerData, let image = UIImage(data: data) {
            applyImage(image)
        }
    }

    private func applyImage(_ image: UIImage) {
        if let tint = stickerObject.tintColor {
            let color = UIColor(
                red: tint.red, green: tint.green,
                blue: tint.blue, alpha: tint.alpha
            )
            imageView.image = image.withRenderingMode(.alwaysTemplate)
            imageView.tintColor = color
        } else {
            imageView.image = image.withRenderingMode(.alwaysOriginal)
        }
    }
}
