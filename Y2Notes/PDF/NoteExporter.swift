import PencilKit
import PDFKit
import UIKit

// MARK: - NoteExporter

/// Renders notes as multi-page PDFs and single-page images for sharing or archiving.
///
/// All rendering is performed off the main thread via `Task.detached` with
/// `.userInitiated` priority so the UI stays responsive during export.
///
/// ## Usage
/// ```swift
/// let url = await NoteExporter.exportAsPDF(title: note.title,
///                                          pages: note.pages,
///                                          backgroundColor: canvasBackground,
///                                          pageTypes: resolvedPageTypes)
/// if let url { /* present share sheet */ }
/// ```
final class NoteExporter {

    // MARK: - Paper dimensions

    /// Standard US Letter paper at 72 pt/in.  Matches the default page size in
    /// most iOS PDF viewers and is the most common size for printed notes.
    static let pdfPageSize = CGSize(width: 612, height: 792)

    // MARK: - Multi-page PDF export

    /// Renders all supplied pages into a single multi-page PDF file.
    ///
    /// Each page is drawn as: background fill → optional ruling lines → attachments → PKDrawing.
    /// The PKDrawing is scaled from the app's on-screen canvas dimensions to the
    /// standard PDF page size while preserving the aspect ratio.
    ///
    /// - Parameters:
    ///   - title:            Display name used as the PDF filename (special characters sanitised).
    ///   - pages:            Serialised `PKDrawing` data — one element per note page.
    ///   - attachmentLayers: Per-page attachment arrays (parallel to `pages`), or empty for no attachments.
    ///   - noteID:           Note identifier used to resolve attachment file paths.
    ///   - backgroundColor:  Canvas background colour (theme + paper-material blend).
    ///   - pageTypes:        Ruling style per page.  Element *i* is used for `pages[i]`.
    ///                       If `pageTypes` is shorter than `pages`, remaining pages are blank.
    /// - Returns: A temporary file URL pointing at the rendered PDF, or `nil` on failure.
    static func exportAsPDF(
        title: String,
        pages: [Data],
        attachmentLayers: [[AttachmentObject]?] = [],
        noteID: UUID? = nil,
        backgroundColor: UIColor,
        pageTypes: [PageType]
    ) async -> URL? {
        // Pre-load attachment images on a background thread so the render is fast.
        let resolvedImages = resolveAttachmentImages(
            attachmentLayers: attachmentLayers,
            noteID: noteID
        )

        return await Task.detached(priority: .userInitiated) {
            let pageRect = CGRect(origin: .zero, size: pdfPageSize)
            let format = UIGraphicsPDFRendererFormat()
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

            let safeName = title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = safeName.isEmpty ? "Note" : safeName
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(fileName).pdf")

            do {
                try renderer.writePDF(to: tempURL) { pdfCtx in
                    for (pageIndex, pageData) in pages.enumerated() {
                        pdfCtx.beginPage()
                        let ctx = pdfCtx.cgContext
                        let pt = pageIndex < pageTypes.count ? pageTypes[pageIndex] : .blank
                        let attachments = pageIndex < attachmentLayers.count
                            ? attachmentLayers[pageIndex] : nil
                        renderPage(
                            data: pageData,
                            attachments: attachments,
                            images: resolvedImages,
                            pageSize: pdfPageSize,
                            backgroundColor: backgroundColor,
                            pageType: pt,
                            into: ctx
                        )
                    }
                }
                return tempURL
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Single-page image export

    /// Renders a single page as a `UIImage` at 2× Retina quality.
    ///
    /// - Parameters:
    ///   - pageData:         Serialised `PKDrawing` data for the page.
    ///   - attachments:      Attachments placed on this page, or `nil` for none.
    ///   - noteID:           Note identifier used to resolve attachment file paths.
    ///   - backgroundColor:  Canvas background colour.
    ///   - pageType:         Ruling style drawn behind the strokes.
    ///   - scale:            Rendering scale factor (default 2× for Retina).
    /// - Returns: A rendered `UIImage`, or `nil` when the page data cannot be decoded.
    static func exportPageAsImage(
        pageData: Data,
        attachments: [AttachmentObject]? = nil,
        noteID: UUID? = nil,
        backgroundColor: UIColor,
        pageType: PageType,
        scale: CGFloat = 2.0
    ) async -> UIImage? {
        let resolvedImages = resolveAttachmentImages(
            attachmentLayers: [attachments],
            noteID: noteID
        )

        return await Task.detached(priority: .userInitiated) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: pdfPageSize, format: format)
            return renderer.image { rendererCtx in
                renderPage(
                    data: pageData,
                    attachments: attachments,
                    images: resolvedImages,
                    pageSize: pdfPageSize,
                    backgroundColor: backgroundColor,
                    pageType: pageType,
                    into: rendererCtx.cgContext
                )
            }
        }.value
    }

    // MARK: - Core page renderer

    /// Draws one note page into `ctx`:
    ///   1. Background fill
    ///   2. Page ruling (if not `.blank`)
    ///   3. Flattened attachment images (below strokes)
    ///   4. `PKDrawing` strokes scaled to fit the destination `pageSize`
    ///
    /// - Parameters:
    ///   - data:            Serialised `PKDrawing`.  Empty data → blank page, no strokes.
    ///   - attachments:     Attachments on this page, or `nil`.
    ///   - images:          Pre-loaded attachment images keyed by attachment ID.
    ///   - pageSize:        Destination canvas size (PDF or image).
    ///   - backgroundColor: Fill colour for the page background.
    ///   - pageType:        Ruling style.
    ///   - ctx:             Core Graphics context already prepared by the caller.
    private static func renderPage(
        data: Data,
        attachments: [AttachmentObject]?,
        images: [UUID: UIImage],
        pageSize: CGSize,
        backgroundColor: UIColor,
        pageType: PageType,
        into ctx: CGContext
    ) {
        let rect = CGRect(origin: .zero, size: pageSize)

        // 1. Background fill
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fill(rect)

        // 2. Ruling
        let lineColor = rulingLineColor(for: backgroundColor)
        switch pageType {
        case .blank: break
        case .ruled: drawRuledLines(ctx: ctx, rect: rect, color: lineColor)
        case .dot:   drawDotGrid(ctx: ctx, rect: rect, color: lineColor)
        case .grid:  drawSquareGrid(ctx: ctx, rect: rect, color: lineColor)
        }

        // Canvas scale factor for coordinate mapping
        let screenBounds = UIScreen.main.bounds
        let screenW = max(screenBounds.width, screenBounds.height)
        let canvasPageSize = CGSize(width: screenW, height: ceil(screenW * 1.414))

        let scaleX = pageSize.width  / canvasPageSize.width
        let scaleY = pageSize.height / canvasPageSize.height
        let drawingScale = min(scaleX, scaleY)

        // 3. Flatten attachments (drawn below strokes so ink appears on top)
        if let attachments = attachments, !attachments.isEmpty {
            renderAttachments(
                attachments,
                images: images,
                canvasPageSize: canvasPageSize,
                drawingScale: drawingScale,
                backgroundColor: backgroundColor,
                into: ctx
            )
        }

        // 4. PKDrawing — scale from the on-screen canvas dimensions to `pageSize`
        guard !data.isEmpty,
              let drawing = try? PKDrawing(data: data),
              !drawing.strokes.isEmpty else { return }

        let drawingImage = drawing.image(
            from: CGRect(origin: .zero, size: canvasPageSize),
            scale: drawingScale
        )
        let drawRect = CGRect(
            origin: .zero,
            size: CGSize(
                width:  canvasPageSize.width  * drawingScale,
                height: canvasPageSize.height * drawingScale
            )
        )
        drawingImage.draw(in: drawRect)
    }

    // MARK: - Attachment rendering for export

    /// Pre-loads full-resolution (or thumbnail fallback) images for all attachments.
    /// Called on the main thread before the detached render task so file I/O is done once.
    static func resolveAttachmentImages(
        attachmentLayers: [[AttachmentObject]?],
        noteID: UUID?
    ) -> [UUID: UIImage] {
        guard let noteID else { return [:] }
        let store = AttachmentStore.shared
        var result: [UUID: UIImage] = [:]
        for layer in attachmentLayers {
            guard let attachments = layer else { continue }
            for attachment in attachments {
                guard attachment.type != .link else { continue }
                // Prefer full-res content file for export quality
                let contentURL = store.contentURL(
                    noteID: noteID,
                    attachmentID: attachment.id,
                    ext: attachment.fileExtension
                )
                if attachment.type == .pdf {
                    // Render first page of embedded PDF at export resolution
                    if let pdfImage = renderEmbeddedPDFPage(at: contentURL) {
                        result[attachment.id] = pdfImage
                    }
                } else if let data = try? Data(contentsOf: contentURL),
                          let image = UIImage(data: data) {
                    result[attachment.id] = image
                } else if let thumb = store.thumbnail(for: attachment.id, noteID: noteID) {
                    // Fallback to thumbnail if full-res unavailable
                    result[attachment.id] = thumb
                }
            }
        }
        return result
    }

    /// Renders the first page of an embedded PDF file as a UIImage at export quality.
    private static func renderEmbeddedPDFPage(at url: URL) -> UIImage? {
        guard let pdfDoc = CGPDFDocument(url as CFURL),
              let page = pdfDoc.page(at: 1) else { return nil }
        let mediaBox = page.getBoxRect(.mediaBox)
        // Render at 2× for crisp output
        let scale: CGFloat = 2.0
        let targetSize = CGSize(
            width: ceil(mediaBox.width * scale),
            height: ceil(mediaBox.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { imgCtx in
            let cgCtx = imgCtx.cgContext
            cgCtx.setFillColor(UIColor.white.cgColor)
            cgCtx.fill(CGRect(origin: .zero, size: targetSize))
            cgCtx.saveGState()
            cgCtx.translateBy(x: 0, y: targetSize.height)
            cgCtx.scaleBy(x: scale, y: -scale)
            cgCtx.drawPDFPage(page)
            cgCtx.restoreGState()
        }
    }

    /// Draws all attachments for a page into the export context, scaled from canvas
    /// coordinates to the destination page size.
    static func renderAttachments(
        _ attachments: [AttachmentObject],
        images: [UUID: UIImage],
        canvasPageSize: CGSize,
        drawingScale: CGFloat,
        backgroundColor: UIColor,
        into ctx: CGContext
    ) {
        let sorted = attachments.sorted { $0.zIndex < $1.zIndex }
        for attachment in sorted {
            let canvasRect = attachment.frame.boundingRect
            let exportRect = CGRect(
                x: canvasRect.origin.x * drawingScale,
                y: canvasRect.origin.y * drawingScale,
                width: canvasRect.width * drawingScale,
                height: canvasRect.height * drawingScale
            )

            let cornerRadius = AttachmentConstants.cardCornerRadius * drawingScale
            let path = UIBezierPath(roundedRect: exportRect, cornerRadius: cornerRadius)

            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.clip()

            if let image = images[attachment.id] {
                // Flatten image content into the export
                image.draw(in: exportRect)
            } else if attachment.type == .link {
                // Link fallback: light card with URL text
                renderLinkPlaceholder(
                    attachment,
                    in: exportRect,
                    drawingScale: drawingScale,
                    into: ctx
                )
            } else {
                // Unsupported / missing content fallback: gray card with type icon
                renderMissingPlaceholder(
                    attachment,
                    in: exportRect,
                    drawingScale: drawingScale,
                    into: ctx
                )
            }
            ctx.restoreGState()

            // Card border
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.separator.cgColor)
            ctx.setLineWidth(max(0.5, 0.5 * drawingScale))
            ctx.addPath(path.cgPath)
            ctx.strokePath()
            ctx.restoreGState()

            // Label below card (if present and not a link)
            if !attachment.label.isEmpty && attachment.type != .link {
                let labelY = exportRect.maxY + 2 * drawingScale
                let labelRect = CGRect(
                    x: exportRect.origin.x,
                    y: labelY,
                    width: exportRect.width,
                    height: 14 * drawingScale
                )
                let fontSize = max(8, 10 * drawingScale)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let nsLabel = attachment.label as NSString
                nsLabel.draw(
                    with: labelRect,
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: attrs,
                    context: nil
                )
            }
        }
    }

    /// Renders a link-type attachment as a styled card with URL text.
    private static func renderLinkPlaceholder(
        _ attachment: AttachmentObject,
        in rect: CGRect,
        drawingScale: CGFloat,
        into ctx: CGContext
    ) {
        // Light background
        ctx.setFillColor(UIColor.systemGray6.cgColor)
        ctx.fill(rect)

        // Link icon
        let iconConfig = UIImage.SymbolConfiguration(pointSize: max(14, 20 * drawingScale), weight: .light)
        if let icon = UIImage(systemName: "link", withConfiguration: iconConfig) {
            let iconSize = icon.size
            let iconRect = CGRect(
                x: rect.midX - iconSize.width / 2,
                y: rect.midY - iconSize.height / 2 - 8 * drawingScale,
                width: iconSize.width,
                height: iconSize.height
            )
            icon.withTintColor(.systemBlue).draw(in: iconRect)
        }

        // URL or label text
        let displayText = attachment.linkURL ?? attachment.label
        if !displayText.isEmpty {
            let fontSize = max(6, 8 * drawingScale)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let textRect = CGRect(
                x: rect.origin.x + 4 * drawingScale,
                y: rect.midY + 4 * drawingScale,
                width: rect.width - 8 * drawingScale,
                height: 12 * drawingScale
            )
            (displayText as NSString).draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attrs,
                context: nil
            )
        }
    }

    /// Renders a placeholder for attachments whose content is missing or unreadable.
    private static func renderMissingPlaceholder(
        _ attachment: AttachmentObject,
        in rect: CGRect,
        drawingScale: CGFloat,
        into ctx: CGContext
    ) {
        ctx.setFillColor(UIColor.systemGray6.cgColor)
        ctx.fill(rect)

        let iconName: String
        switch attachment.type {
        case .image:   iconName = "photo"
        case .pdf:     iconName = "doc.richtext"
        case .link:    iconName = "link"
        default:       iconName = "doc.questionmark"
        }
        let iconConfig = UIImage.SymbolConfiguration(pointSize: max(14, 20 * drawingScale), weight: .light)
        if let icon = UIImage(systemName: iconName, withConfiguration: iconConfig) {
            let iconSize = icon.size
            let iconRect = CGRect(
                x: rect.midX - iconSize.width / 2,
                y: rect.midY - iconSize.height / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            icon.withTintColor(.systemGray3).draw(in: iconRect)
        }
    }

    // MARK: - Ruling helpers (mirrors PageBackgroundView's CGContext drawing)

    /// Returns a ruling line colour that contrasts against `background`.
    /// Light backgrounds get a dark 10%-opacity line; dark backgrounds get a light 12%-opacity line.
    private static func rulingLineColor(for background: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        background.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.5
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.10)
    }

    private static func drawRuledLines(ctx: CGContext, rect: CGRect, color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5)
        var y: CGFloat = 28
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += 28
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawDotGrid(ctx: CGContext, rect: CGRect, color: UIColor) {
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        let dotRadius: CGFloat = 1.5
        let spacing: CGFloat = 24
        var y: CGFloat = spacing
        while y <= rect.maxY {
            var x: CGFloat = spacing
            while x <= rect.maxX {
                ctx.fillEllipse(in: CGRect(
                    x: x - dotRadius, y: y - dotRadius,
                    width: dotRadius * 2, height: dotRadius * 2
                ))
                x += spacing
            }
            y += spacing
        }
        ctx.restoreGState()
    }

    private static func drawSquareGrid(ctx: CGContext, rect: CGRect, color: UIColor) {
        ctx.saveGState()
        let gridColor = color.withAlphaComponent(color.cgColor.alpha * 0.7)
        ctx.setStrokeColor(gridColor.cgColor)
        ctx.setLineWidth(0.5)
        var y: CGFloat = 24
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += 24
        }
        var x: CGFloat = 24
        while x <= rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += 24
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
