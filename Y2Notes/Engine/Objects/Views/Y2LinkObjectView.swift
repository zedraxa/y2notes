import UIKit
import SafariServices

// MARK: - Y2LinkObjectView

/// A canvas view that displays an embedded web or in-app link.
///
/// Three visual styles:
/// - **Chip**: compact pill with favicon + truncated title (default)
/// - **Card**: expanded tile with preview image, title, and domain
/// - **Inline**: plain underlined text label
///
/// Tapping the view opens the URL in `SFSafariViewController`.
final class Y2LinkObjectView: UIView {

    // MARK: - Subviews

    private let backgroundView = UIView()
    private let faviconView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let domainLabel = UILabel()
    private let previewImageView = UIImageView()

    // MARK: - State

    let linkObject: LinkObject

    // MARK: - Init

    init(linkObject: LinkObject) {
        self.linkObject = linkObject
        super.init(frame: .zero)
        setupForStyle(linkObject.displayStyle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Style setup

    private func setupForStyle(_ style: LinkDisplayStyle) {
        subviews.forEach { $0.removeFromSuperview() }

        switch style {
        case .chip:  setupChip()
        case .card:  setupCard()
        case .inline: setupInline()
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(openLink))
        addGestureRecognizer(tap)

        isAccessibilityElement = true
        accessibilityLabel = "\(linkObject.title ?? linkObject.urlString) — Link"
        accessibilityTraits = [.link]
        accessibilityHint = "Double-tap to open in Safari"
    }

    // MARK: Chip

    private func setupChip() {
        backgroundView.backgroundColor = .secondarySystemBackground
        backgroundView.layer.cornerRadius = 16
        backgroundView.clipsToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        faviconView.contentMode = .scaleAspectFit
        faviconView.layer.cornerRadius = 4
        faviconView.clipsToBounds = true
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(faviconView)

        titleLabel.text = linkObject.title ?? linkObject.displayDomain ?? linkObject.urlString
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .systemBlue
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            faviconView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
            faviconView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: 18),
            faviconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
        ])

        loadFavicon()
    }

    // MARK: Card

    private func setupCard() {
        backgroundView.backgroundColor = .secondarySystemBackground
        backgroundView.layer.cornerRadius = 12
        backgroundView.clipsToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.backgroundColor = .tertiarySystemBackground
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(previewImageView)

        titleLabel.text = linkObject.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(titleLabel)

        if let desc = linkObject.linkDescription, !desc.isEmpty {
            descriptionLabel.text = desc
            descriptionLabel.font = .systemFont(ofSize: 11)
            descriptionLabel.textColor = .secondaryLabel
            descriptionLabel.numberOfLines = 2
            descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(descriptionLabel)
        }

        domainLabel.text = linkObject.displayDomain
        domainLabel.font = .systemFont(ofSize: 11)
        domainLabel.textColor = .tertiaryLabel
        domainLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(domainLabel)

        let hasDescription = linkObject.linkDescription?.isEmpty == false
        let descAnchor = hasDescription ? descriptionLabel : titleLabel

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            previewImageView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            previewImageView.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),

            domainLabel.topAnchor.constraint(equalTo: descAnchor.bottomAnchor, constant: 4),
            domainLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            domainLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        if hasDescription {
            NSLayoutConstraint.activate([
                descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            ])
        }

        loadFavicon()
        loadPreviewImage()
    }

    // MARK: Inline

    private func setupInline() {
        let url = linkObject.url?.absoluteString ?? linkObject.urlString
        let text = NSAttributedString(
            string: linkObject.title ?? url,
            attributes: [
                .foregroundColor: UIColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: UIFont.systemFont(ofSize: 14),
            ]
        )
        titleLabel.attributedText = text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Asset loading

    private func loadFavicon() {
        guard let data = linkObject.faviconData,
              let img = UIImage(data: data) else {
            faviconView.image = UIImage(systemName: "link")
            return
        }
        faviconView.image = img
    }

    private func loadPreviewImage() {
        guard let data = linkObject.previewImageData,
              let img = UIImage(data: data) else { return }
        previewImageView.image = img
    }

    // MARK: - Tap action

    @objc private func openLink() {
        guard let url = linkObject.url else { return }
        let safari = SFSafariViewController(url: url)
        let topVC = topViewController()
        topVC?.present(safari, animated: true)
    }

    override func accessibilityActivate() -> Bool {
        openLink()
        return true
    }

    private func topViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
