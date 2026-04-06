import UIKit

// MARK: - Y2ImageCropDelegate

protocol Y2ImageCropDelegate: AnyObject {
    func cropController(_ controller: Y2ImageCropController, didCrop cropRect: CGRect)
    func cropControllerDidCancel(_ controller: Y2ImageCropController)
}

// MARK: - Y2ImageCropController

/// In-canvas image cropping presented when the user double-taps an image object.
///
/// Displays the full image with a draggable crop rect overlay.  Crop coordinates
/// are returned in normalised space (0…1) so they are resolution-independent.
final class Y2ImageCropController: UIViewController {

    // MARK: - Dependencies

    weak var delegate: Y2ImageCropDelegate?
    private let image: UIImage

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let cropOverlay = CropOverlayView()
    private let toolbar = UIToolbar()

    // MARK: - State

    private var initialCropRect: CGRect?

    // MARK: - Init

    init(image: UIImage, initialCropRect: CGRect? = nil) {
        self.image = image
        self.initialCropRect = initialCropRect
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        setupScrollView()
        setupCropOverlay()
        setupToolbar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cropOverlay.frame = imageView.convert(imageView.bounds, to: view)
        if let initial = initialCropRect {
            cropOverlay.setCropRect(normalised: initial)
            initialCropRect = nil
        }
    }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView.frame = view.bounds.inset(by: UIEdgeInsets(top: 60, left: 0, bottom: 80, right: 0))
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        scrollView.addSubview(imageView)
    }

    private func setupCropOverlay() {
        cropOverlay.isUserInteractionEnabled = true
        view.addSubview(cropOverlay)
    }

    private func setupToolbar() {
        toolbar.frame = CGRect(x: 0, y: view.bounds.height - 80, width: view.bounds.width, height: 80)
        toolbar.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        toolbar.barStyle = .black
        toolbar.isTranslucent = true

        let cancel = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelCrop))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let apply = UIBarButtonItem(title: "Apply", style: .done, target: self, action: #selector(applyCrop))
        let lock = UIBarButtonItem(title: "Aspect Lock", style: .plain, target: self, action: #selector(toggleAspectLock))

        toolbar.items = [cancel, flex, lock, flex, apply]
        view.addSubview(toolbar)
    }

    // MARK: - Actions

    @objc private func applyCrop() {
        let normalised = cropOverlay.currentCropRect(normalisedFor: imageView.convert(imageView.bounds, to: view))
        delegate?.cropController(self, didCrop: normalised)
        dismiss(animated: true)
    }

    @objc private func cancelCrop() {
        delegate?.cropControllerDidCancel(self)
        dismiss(animated: true)
    }

    @objc private func toggleAspectLock() {
        cropOverlay.isAspectLocked.toggle()
    }
}

// MARK: - UIScrollViewDelegate

extension Y2ImageCropController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

// MARK: - CropOverlayView (private)

/// A transparent view that draws and manages the draggable crop rectangle.
private final class CropOverlayView: UIView {

    var isAspectLocked = false
    private(set) var cropRect = CGRect.zero

    private let dimLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var activeHandle: Handle?

    enum Handle { case topLeft, topRight, bottomLeft, bottomRight }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.addSublayer(dimLayer)
        dimLayer.backgroundColor = UIColor.black.withAlphaComponent(0.4).cgColor

        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 1.5
        layer.addSublayer(borderLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCropRect(normalised: CGRect) {
        let r = CGRect(
            x: bounds.width * normalised.origin.x,
            y: bounds.height * normalised.origin.y,
            width: bounds.width * normalised.size.width,
            height: bounds.height * normalised.size.height
        )
        cropRect = r
        setNeedsDisplay()
        updateLayers()
    }

    func currentCropRect(normalisedFor imageFrame: CGRect) -> CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let relX = (cropRect.origin.x - imageFrame.origin.x) / imageFrame.width
        let relY = (cropRect.origin.y - imageFrame.origin.y) / imageFrame.height
        let relW = cropRect.width / imageFrame.width
        let relH = cropRect.height / imageFrame.height
        return CGRect(x: relX, y: relY, width: relW, height: relH)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimLayer.frame = bounds
        if cropRect.isEmpty { cropRect = bounds.insetBy(dx: 40, dy: 40) }
        updateLayers()
    }

    private func updateLayers() {
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(rect: cropRect).reversing())
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        dimLayer.mask = mask

        borderLayer.path = UIBezierPath(rect: cropRect).cgPath
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let loc = g.location(in: self)
        let delta = g.translation(in: self)

        if g.state == .began {
            activeHandle = handle(at: loc)
        }

        guard g.state == .changed else { activeHandle = nil; return }

        switch activeHandle {
        case .topLeft:
            cropRect = CGRect(
                x: cropRect.minX + delta.x, y: cropRect.minY + delta.y,
                width: cropRect.width - delta.x, height: cropRect.height - delta.y
            )
        case .topRight:
            cropRect = CGRect(
                x: cropRect.minX, y: cropRect.minY + delta.y,
                width: cropRect.width + delta.x, height: cropRect.height - delta.y
            )
        case .bottomLeft:
            cropRect = CGRect(
                x: cropRect.minX + delta.x, y: cropRect.minY,
                width: cropRect.width - delta.x, height: cropRect.height + delta.y
            )
        case .bottomRight:
            cropRect = CGRect(
                x: cropRect.minX, y: cropRect.minY,
                width: cropRect.width + delta.x, height: cropRect.height + delta.y
            )
        case nil:
            // Move entire rect.
            cropRect = cropRect.offsetBy(dx: delta.x, dy: delta.y)
        }

        cropRect.size.width = max(50, cropRect.size.width)
        cropRect.size.height = max(50, cropRect.size.height)
        g.setTranslation(.zero, in: self)
        updateLayers()
    }

    private func handle(at point: CGPoint) -> Handle? {
        let tolerance: CGFloat = 24
        if point.distance(to: CGPoint(x: cropRect.minX, y: cropRect.minY)) < tolerance { return .topLeft }
        if point.distance(to: CGPoint(x: cropRect.maxX, y: cropRect.minY)) < tolerance { return .topRight }
        if point.distance(to: CGPoint(x: cropRect.minX, y: cropRect.maxY)) < tolerance { return .bottomLeft }
        if point.distance(to: CGPoint(x: cropRect.maxX, y: cropRect.maxY)) < tolerance { return .bottomRight }
        return nil
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        sqrt((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y))
    }
}
