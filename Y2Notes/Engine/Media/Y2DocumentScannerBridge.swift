import UIKit
import VisionKit

// MARK: - Y2DocumentScannerDelegate

protocol Y2DocumentScannerDelegate: AnyObject {
    /// Called with processed wrappers when the user completes a scan session.
    func documentScanner(
        _ scanner: Y2DocumentScannerBridge,
        didProduce wrappers: [CanvasObjectWrapper]
    )
    /// Called when the user cancels the scan.
    func documentScannerDidCancel(_ scanner: Y2DocumentScannerBridge)
}

// MARK: - ScanInsertionMode

/// How the scanned pages are placed onto the note.
enum ScanInsertionMode {
    /// Each scan becomes a floating image object on the current page.
    case objectsOnCurrentPage
    /// Each scan becomes a new page background in the note.
    case newPages
}

// MARK: - Y2DocumentScannerBridge

/// Wraps `VNDocumentCameraViewController` and converts scanned pages into
/// `CanvasObjectWrapper` instances or signals that new pages should be created.
final class Y2DocumentScannerBridge: NSObject {

    // MARK: - Dependencies

    weak var delegate: Y2DocumentScannerDelegate?
    private let noteID: UUID
    private let visibleCanvasRect: CGRect
    var insertionMode: ScanInsertionMode = .objectsOnCurrentPage

    // MARK: - Constants

    private enum Constants {
        static let jpegQuality: CGFloat = 0.85
        static let maxLongEdge: CGFloat = 2048
    }

    // MARK: - Init

    init(noteID: UUID, visibleCanvasRect: CGRect) {
        self.noteID = noteID
        self.visibleCanvasRect = visibleCanvasRect
    }

    // MARK: - Public API

    /// Presents the VisionKit document camera.
    func present(from vc: UIViewController) {
        guard VNDocumentCameraViewController.isSupported else {
            showUnsupportedAlert(in: vc)
            return
        }
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        vc.present(scanner, animated: true)
    }

    // MARK: - Processing

    private func processScans(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var wrappers: [CanvasObjectWrapper] = []
            let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Scans", isDirectory: true)
            try? FileManager.default.createDirectory(at: scansDir, withIntermediateDirectories: true)

            for (index, image) in images.enumerated() {
                let objectID = UUID()
                let resized = self.resize(image, maxLongEdge: Constants.maxLongEdge)
                guard let jpeg = resized.jpegData(compressionQuality: Constants.jpegQuality) else { continue }

                // Save full-res to NoteMedia.
                let relativePath = (try? MediaFileManager.shared.saveImage(
                    noteID: self.noteID,
                    objectID: objectID,
                    imageData: jpeg
                )) ?? ""

                // Save scan thumbnail to Documents/Scans.
                let thumbnailData = self.makeThumbnail(image)
                let scanFilename = "\(objectID.uuidString)_scan.jpg"
                try? thumbnailData?.write(to: scansDir.appendingPathComponent(scanFilename))

                let imageObj = ImageObject(
                    relativePath: relativePath,
                    thumbnailData: thumbnailData
                )

                let size = self.displaySize(for: image)
                let offset = CGPoint(
                    x: visibleCanvasRect.midX - size.width / 2 + CGFloat(index) * 10,
                    y: visibleCanvasRect.midY - size.height / 2 + CGFloat(index) * 10
                )
                let wrapper = CanvasObjectWrapper(
                    id: objectID,
                    frame: CGRect(origin: offset, size: size),
                    zIndex: index,
                    objectType: .image(imageObj)
                )
                wrappers.append(wrapper)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.documentScanner(self, didProduce: wrappers)
            }
        }
    }

    // MARK: - Helpers

    private func resize(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let sz = image.size
        let long = max(sz.width, sz.height)
        guard long > maxLongEdge else { return image }
        let scale = maxLongEdge / long
        let newSize = CGSize(width: sz.width * scale, height: sz.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private func makeThumbnail(_ image: UIImage) -> Data? {
        let maxDim: CGFloat = 240
        let sz = image.size
        let long = max(sz.width, sz.height)
        let scale = long > maxDim ? maxDim / long : 1
        let thumbSize = CGSize(width: sz.width * scale, height: sz.height * scale)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumb = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: thumbSize)) }
        return thumb.jpegData(compressionQuality: 0.7)
    }

    private func displaySize(for image: UIImage) -> CGSize {
        let sz = image.size
        let maxDim: CGFloat = 360
        let long = max(sz.width, sz.height)
        guard long > maxDim else { return sz }
        let scale = maxDim / long
        return CGSize(width: sz.width * scale, height: sz.height * scale)
    }

    private func showUnsupportedAlert(in vc: UIViewController) {
        let alert = UIAlertController(
            title: "Scanner Not Available",
            message: "Document scanning is not supported on this device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        vc.present(alert, animated: true)
    }
}

// MARK: - VNDocumentCameraViewControllerDelegate

extension Y2DocumentScannerBridge: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)
        var images: [UIImage] = []
        for i in 0..<scan.pageCount {
            images.append(scan.imageOfPage(at: i))
        }
        processScans(images)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        delegate?.documentScannerDidCancel(self)
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true)
        delegate?.documentScannerDidCancel(self)
    }
}
