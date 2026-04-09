import UIKit
import SafariServices

// MARK: - Y2LinkInsertionDelegate

protocol Y2LinkInsertionDelegate: AnyObject {
    /// Called when a link is ready to be placed on the canvas.
    func linkInsertionController(
        _ controller: Y2LinkInsertionController,
        didPrepare wrapper: CanvasObjectWrapper
    )
}

// MARK: - Y2LinkInsertionController

/// Presents a URL-entry popover, fetches link metadata, and produces a
/// `CanvasObjectWrapper` for the overlay controller.
final class Y2LinkInsertionController: UIViewController {

    // MARK: - Dependencies

    weak var delegate: Y2LinkInsertionDelegate?
    private let dropPoint: CGPoint

    // MARK: - Subviews

    private let urlField = UITextField()
    private let insertButton = UIButton(type: .system)
    private let previewCard = UIView()
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    private let faviconView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let styleSegment = UISegmentedControl(items: ["Chip", "Card", "Inline"])

    // MARK: - State

    private var fetchedMetadata: LinkObject?
    private let fetcher = Y2LinkMetadataFetcher()

    // MARK: - Init

    init(dropPoint: CGPoint) {
        self.dropPoint = dropPoint
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        preferredContentSize = CGSize(width: 360, height: 300)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Insert Link"
        view.backgroundColor = .systemBackground

        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissSelf))
        navigationItem.leftBarButtonItem = cancel

        setupURLField()
        setupStyleSegment()
        setupPreviewCard()
        setupInsertButton()
    }

    // MARK: - Setup

    private func setupURLField() {
        urlField.placeholder = "Paste or type URL"
        urlField.borderStyle = .roundedRect
        urlField.keyboardType = .URL
        urlField.autocorrectionType = .no
        urlField.autocapitalizationType = .none
        urlField.clearButtonMode = .whileEditing
        urlField.addTarget(self, action: #selector(urlChanged), for: .editingChanged)
        urlField.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(urlField)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            urlField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            urlField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            urlField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            urlField.heightAnchor.constraint(equalToConstant: 44),

            activityIndicator.centerYAnchor.constraint(equalTo: urlField.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: urlField.trailingAnchor, constant: -8),
        ])
    }

    private func setupStyleSegment() {
        styleSegment.selectedSegmentIndex = 0
        styleSegment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(styleSegment)
        NSLayoutConstraint.activate([
            styleSegment.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 12),
            styleSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            styleSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    private func setupPreviewCard() {
        previewCard.backgroundColor = .secondarySystemBackground
        previewCard.layer.cornerRadius = 12
        previewCard.isHidden = true
        previewCard.translatesAutoresizingMaskIntoConstraints = false

        faviconView.contentMode = .scaleAspectFit
        faviconView.layer.cornerRadius = 4
        faviconView.clipsToBounds = true
        faviconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        domainLabel.font = .systemFont(ofSize: 11)
        domainLabel.textColor = .secondaryLabel
        domainLabel.translatesAutoresizingMaskIntoConstraints = false

        previewCard.addSubview(faviconView)
        previewCard.addSubview(titleLabel)
        previewCard.addSubview(domainLabel)
        view.addSubview(previewCard)

        NSLayoutConstraint.activate([
            previewCard.topAnchor.constraint(equalTo: styleSegment.bottomAnchor, constant: 12),
            previewCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            previewCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            previewCard.heightAnchor.constraint(equalToConstant: 80),

            faviconView.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12),
            faviconView.centerYAnchor.constraint(equalTo: previewCard.centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: 32),
            faviconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 14),

            domainLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            domainLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
        ])
    }

    private func setupInsertButton() {
        insertButton.setTitle("Insert Link", for: .normal)
        insertButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        insertButton.backgroundColor = .systemBlue
        insertButton.setTitleColor(.white, for: .normal)
        insertButton.layer.cornerRadius = 12
        insertButton.isEnabled = false
        insertButton.alpha = 0.5
        insertButton.addTarget(self, action: #selector(insertLink), for: .touchUpInside)
        insertButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(insertButton)
        NSLayoutConstraint.activate([
            insertButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            insertButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            insertButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            insertButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    // MARK: - URL handling

    @objc private func urlChanged() {
        fetchedMetadata = nil
        previewCard.isHidden = true
        insertButton.isEnabled = false
        insertButton.alpha = 0.5

        guard let text = urlField.text, !text.isEmpty else { return }
        let urlString = text.hasPrefix("http") ? text : "https://\(text)"
        guard let url = URL(string: urlString) else { return }

        activityIndicator.startAnimating()
        fetcher.fetch(url: url) { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                switch result {
                case .success(let meta):
                    self?.showPreview(meta)
                case .failure:
                    // Show a basic link even without metadata
                    let basic = LinkObject(urlString: urlString, displayDomain: url.host)
                    self?.fetchedMetadata = basic
                    self?.insertButton.isEnabled = true
                    self?.insertButton.alpha = 1
                }
            }
        }
    }

    private func showPreview(_ link: LinkObject) {
        fetchedMetadata = link
        titleLabel.text = link.title ?? link.urlString
        domainLabel.text = link.displayDomain
        if let data = link.faviconData, let img = UIImage(data: data) {
            faviconView.image = img
        } else {
            faviconView.image = UIImage(systemName: "link")
        }
        previewCard.isHidden = false
        insertButton.isEnabled = true
        insertButton.alpha = 1
    }

    // MARK: - Insert

    @objc private func insertLink() {
        guard var link = fetchedMetadata ?? buildBasicLink() else { return }
        link.displayStyle = displayStyleForSegment()

        let wrapper = CanvasObjectWrapper.makeLink(link, at: dropPoint)
        delegate?.linkInsertionController(self, didPrepare: wrapper)
        dismiss(animated: true)
    }

    private func buildBasicLink() -> LinkObject? {
        guard let text = urlField.text, !text.isEmpty else { return nil }
        let urlString = text.hasPrefix("http") ? text : "https://\(text)"
        guard let url = URL(string: urlString) else { return nil }
        return LinkObject(urlString: urlString, displayDomain: url.host)
    }

    private func displayStyleForSegment() -> LinkDisplayStyle {
        switch styleSegment.selectedSegmentIndex {
        case 0: return .chip
        case 1: return .card
        case 2: return .inline
        default: return .chip
        }
    }

    @objc private func dismissSelf() { dismiss(animated: true) }
}
