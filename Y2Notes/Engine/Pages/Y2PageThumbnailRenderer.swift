import UIKit
import PencilKit
import os

// MARK: - Y2PageThumbnailRenderer

/// Async page thumbnail renderer with an LRU memory cache.
///
/// Renders `PKDrawing` data to thumbnail `UIImage` on a background queue.
/// Results are cached (up to 50 entries) and delivered on the main queue.
///
/// **Thread safety:** All cache reads/writes are serialized on an internal queue.
/// Render calls are dispatched to a concurrent utility queue.
final class Y2PageThumbnailRenderer {

    // MARK: - Types

    typealias Completion = (UIImage?) -> Void

    // MARK: - Configuration

    /// Default thumbnail size.
    static let defaultSize = CGSize(width: 200, height: 280)

    // MARK: - Cache

    private let cache = NSCache<NSString, UIImage>()
    private let cacheQueue = DispatchQueue(label: "y2notes.thumbnail.cache")
    private let renderQueue = DispatchQueue(label: "y2notes.thumbnail.render", qos: .utility, attributes: .concurrent)
    private let logger = Logger(subsystem: "com.y2notes.app", category: "thumbnail")

    // MARK: - Init

    init(cacheLimit: Int = 50) {
        cache.countLimit = cacheLimit
    }

    // MARK: - Public API

    /// Generates a thumbnail asynchronously.
    ///
    /// - Parameters:
    ///   - drawingData: Serialized `PKDrawing` data.
    ///   - pageIndex: Index used as part of cache key.
    ///   - noteID: Note UUID used as part of cache key.
    ///   - size: Target thumbnail size in points.
    ///   - backgroundColor: Background color for the thumbnail.
    ///   - completion: Called on main thread with the result (nil on failure).
    func renderThumbnail(
        drawingData: Data,
        pageIndex: Int,
        noteID: UUID,
        size: CGSize = defaultSize,
        backgroundColor: UIColor = .white,
        completion: @escaping Completion
    ) {
        let key = cacheKey(noteID: noteID, pageIndex: pageIndex, size: size) as NSString

        // Check cache first
        cacheQueue.async { [weak self] in
            if let cached = self?.cache.object(forKey: key) {
                DispatchQueue.main.async { completion(cached) }
                return
            }
            self?.renderOnBackground(
                drawingData: drawingData,
                key: key,
                size: size,
                backgroundColor: backgroundColor,
                completion: completion
            )
        }
    }

    /// Invalidates a specific page's cached thumbnail.
    func invalidate(noteID: UUID, pageIndex: Int, size: CGSize = defaultSize) {
        let key = cacheKey(noteID: noteID, pageIndex: pageIndex, size: size) as NSString
        cacheQueue.async { [weak self] in
            self?.cache.removeObject(forKey: key)
        }
    }

    /// Clears all cached thumbnails.
    func clearCache() {
        cacheQueue.async { [weak self] in
            self?.cache.removeAllObjects()
        }
    }

    // MARK: - Private

    private func renderOnBackground(
        drawingData: Data,
        key: NSString,
        size: CGSize,
        backgroundColor: UIColor,
        completion: @escaping Completion
    ) {
        renderQueue.async { [weak self] in
            guard let self else { return }

            do {
                let drawing = try PKDrawing(data: drawingData)
                let image = self.renderImage(drawing: drawing, size: size, backgroundColor: backgroundColor)

                self.cacheQueue.async {
                    if let image {
                        self.cache.setObject(image, forKey: key)
                    }
                }

                DispatchQueue.main.async { completion(image) }
            } catch {
                self.logger.error("Thumbnail render failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func renderImage(
        drawing: PKDrawing,
        size: CGSize,
        backgroundColor: UIColor
    ) -> UIImage? {
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: pixelSize)
        return renderer.image { ctx in
            // Background
            backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixelSize))

            // Scale drawing to fit
            let drawingBounds = drawing.bounds
            guard !drawingBounds.isEmpty else { return }

            let scaleX = pixelSize.width / drawingBounds.width
            let scaleY = pixelSize.height / drawingBounds.height
            let fitScale = min(scaleX, scaleY) * 0.9  // 90% to add margin

            let cgCtx = ctx.cgContext
            cgCtx.translateBy(
                x: (pixelSize.width - drawingBounds.width * fitScale) / 2 - drawingBounds.minX * fitScale,
                y: (pixelSize.height - drawingBounds.height * fitScale) / 2 - drawingBounds.minY * fitScale
            )
            cgCtx.scaleBy(x: fitScale, y: fitScale)

            let drawingImage = drawing.image(from: drawingBounds, scale: scale)
            drawingImage.draw(in: drawingBounds)
        }
    }

    private func cacheKey(noteID: UUID, pageIndex: Int, size: CGSize) -> String {
        "\(noteID.uuidString)-\(pageIndex)-\(Int(size.width))x\(Int(size.height))"
    }
}
