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
        widgetLayers: [[NoteWidget]?] = [],
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
                        let widgets = pageIndex < widgetLayers.count
                            ? widgetLayers[pageIndex] : nil
                        renderPage(
                            data: pageData,
                            attachments: attachments,
                            images: resolvedImages,
                            widgets: widgets,
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

    // MARK: - Multi-page PDF export with expansion regions

    /// Renders all supplied pages into a single multi-page PDF file, including
    /// visible (non-collapsed) expansion regions as additional pages immediately
    /// following each main page.
    ///
    /// Expansion pages carry a "← continued from page N" label and a thin dotted
    /// boundary line showing where the original page ended.
    static func exportAsPDFWithExpansions(
        title: String,
        pages: [Data],
        attachmentLayers: [[AttachmentObject]?] = [],
        widgetLayers: [[NoteWidget]?] = [],
        expansionRegions: [PageRegion] = [],
        noteID: UUID? = nil,
        backgroundColor: UIColor,
        pageTypes: [PageType]
    ) async -> URL? {
        let resolvedImages = resolveAttachmentImages(
            attachmentLayers: attachmentLayers,
            noteID: noteID
        )

        return await Task.detached(priority: .userInitiated) {
            let safeName = title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = safeName.isEmpty ? "Note" : safeName
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(fileName).pdf")

            do {
                // Use a mutable PDF context so we can set variable page sizes.
                var mediaBox = CGRect(origin: .zero, size: pdfPageSize)
                guard let pdfCtx = CGContext(tempURL as CFURL, mediaBox: &mediaBox, nil) else {
                    return nil
                }

                for (pageIndex, pageData) in pages.enumerated() {
                    // --- Main page (standard US Letter) ---
                    var mainBox = CGRect(origin: .zero, size: pdfPageSize)
                    pdfCtx.beginPage(mediaBox: &mainBox)
                    let pt = pageIndex < pageTypes.count ? pageTypes[pageIndex] : .blank
                    let attachments = pageIndex < attachmentLayers.count
                        ? attachmentLayers[pageIndex] : nil
                    let widgets = pageIndex < widgetLayers.count
                        ? widgetLayers[pageIndex] : nil
                    renderPage(
                        data: pageData,
                        attachments: attachments,
                        images: resolvedImages,
                        widgets: widgets,
                        pageSize: pdfPageSize,
                        backgroundColor: backgroundColor,
                        pageType: pt,
                        into: pdfCtx
                    )
                    pdfCtx.endPage()

                    // --- Expansion region pages ---
                    let visibleRegions = expansionRegions.filter { $0.pageIndex == pageIndex && !$0.isCollapsed }
                    for region in visibleRegions {
                        switch region.edge {
                        case .right:
                            let expWidth = min(region.size.width, pdfPageSize.width * PageRegionConstants.maxWidthMultiplier)
                            var expBox = CGRect(origin: .zero, size: CGSize(width: expWidth, height: pdfPageSize.height))
                            pdfCtx.beginPage(mediaBox: &expBox)
                            renderExpansionPage(
                                region: region,
                                pageSize: expBox.size,
                                mainPageNumber: pageIndex + 1,
                                backgroundColor: backgroundColor,
                                images: resolvedImages,
                                into: pdfCtx
                            )
                            pdfCtx.endPage()

                        case .bottom:
                            let expHeight = min(region.size.height, pdfPageSize.height * PageRegionConstants.maxHeightMultiplier)
                            var expBox = CGRect(origin: .zero, size: CGSize(width: pdfPageSize.width, height: expHeight))
                            pdfCtx.beginPage(mediaBox: &expBox)
                            renderExpansionPage(
                                region: region,
                                pageSize: expBox.size,
                                mainPageNumber: pageIndex + 1,
                                backgroundColor: backgroundColor,
                                images: resolvedImages,
                                into: pdfCtx
                            )
                            pdfCtx.endPage()

                        case .rightBottom:
                            let expWidth = min(region.size.width, pdfPageSize.width * PageRegionConstants.maxWidthMultiplier)
                            let expHeight = min(region.size.height, pdfPageSize.height * PageRegionConstants.maxHeightMultiplier)
                            var expBox = CGRect(origin: .zero, size: CGSize(width: expWidth, height: expHeight))
                            pdfCtx.beginPage(mediaBox: &expBox)
                            renderExpansionPage(
                                region: region,
                                pageSize: expBox.size,
                                mainPageNumber: pageIndex + 1,
                                backgroundColor: backgroundColor,
                                images: resolvedImages,
                                into: pdfCtx
                            )
                            pdfCtx.endPage()
                        }
                    }
                }

                pdfCtx.closePDF()
                return tempURL
            }
        }.value
    }

    /// Renders a single expansion region page into the PDF context.
    private static func renderExpansionPage(
        region: PageRegion,
        pageSize: CGSize,
        mainPageNumber: Int,
        backgroundColor: UIColor,
        images: [UUID: UIImage],
        into ctx: CGContext
    ) {
        let rect = CGRect(origin: .zero, size: pageSize)

        // 1. Background fill
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fill(rect)

        // 2. "← continued from page N" label
        let labelText = "← continued from page \(mainPageNumber)" as NSString
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let labelRect = CGRect(x: 8, y: 6, width: pageSize.width - 16, height: 14)
        labelText.draw(
            with: labelRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: labelAttrs,
            context: nil
        )

        // 3. Dotted boundary line showing where the original page edge was
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.separator.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        switch region.edge {
        case .right:
            // Vertical line at x=0 (left edge = original page right boundary)
            ctx.move(to: CGPoint(x: 0.5, y: 0))
            ctx.addLine(to: CGPoint(x: 0.5, y: pageSize.height))
        case .bottom:
            // Horizontal line at y=0 (top edge = original page bottom boundary)
            ctx.move(to: CGPoint(x: 0, y: 0.5))
            ctx.addLine(to: CGPoint(x: pageSize.width, y: 0.5))
        case .rightBottom:
            // Both edges
            ctx.move(to: CGPoint(x: 0.5, y: 0))
            ctx.addLine(to: CGPoint(x: 0.5, y: pageSize.height))
            ctx.move(to: CGPoint(x: 0, y: 0.5))
            ctx.addLine(to: CGPoint(x: pageSize.width, y: 0.5))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 4. Draw expansion PKDrawing
        if !region.drawingData.isEmpty,
           let drawing = try? PKDrawing(data: region.drawingData),
           !drawing.strokes.isEmpty {
            let sourceRect = CGRect(origin: .zero, size: region.size)
            let scaleX = pageSize.width / max(region.size.width, 1)
            let scaleY = pageSize.height / max(region.size.height, 1)
            let drawingScale = min(scaleX, scaleY)
            let drawingImage = drawing.image(from: sourceRect, scale: drawingScale)
            let drawRect = CGRect(
                origin: .zero,
                size: CGSize(
                    width: region.size.width * drawingScale,
                    height: region.size.height * drawingScale
                )
            )
            drawingImage.draw(in: drawRect)
        }

        // 5. Render expansion widgets
        if !region.widgetLayers.isEmpty {
            let scaleX = pageSize.width / max(region.size.width, 1)
            let scaleY = pageSize.height / max(region.size.height, 1)
            let drawingScale = min(scaleX, scaleY)
            renderWidgets(region.widgetLayers, drawingScale: drawingScale, into: ctx)
        }

        // 6. Render expansion attachments
        if !region.attachmentLayers.isEmpty {
            let screenBounds = UIScreen.main.bounds
            let screenW = max(screenBounds.width, screenBounds.height)
            let canvasPageSize = CGSize(width: screenW, height: ceil(screenW * 1.414))
            let scaleX = pageSize.width / max(region.size.width, 1)
            let scaleY = pageSize.height / max(region.size.height, 1)
            let drawingScale = min(scaleX, scaleY)
            renderAttachments(
                region.attachmentLayers,
                images: images,
                canvasPageSize: canvasPageSize,
                drawingScale: drawingScale,
                backgroundColor: backgroundColor,
                into: ctx
            )
        }
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
        widgets: [NoteWidget]? = nil,
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
                    widgets: widgets,
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
        widgets: [NoteWidget]?,
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
        case .cornell:   drawCornellRuling(ctx: ctx, rect: rect, color: lineColor)
        case .hexagonal: drawHexGrid(ctx: ctx, rect: rect, color: lineColor)
        case .music:     drawMusicStaff(ctx: ctx, rect: rect, color: lineColor)
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

        // 3b. Flatten widgets (drawn below strokes, above attachments)
        if let widgets = widgets, !widgets.isEmpty {
            renderWidgets(
                widgets,
                drawingScale: drawingScale,
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
                    } else if let thumb = store.thumbnail(for: attachment.id, noteID: noteID) {
                        // Fallback to thumbnail if PDF render fails
                        result[attachment.id] = thumb
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

    // MARK: - Widget rendering for export

    /// Renders widget cards as static snapshots into the PDF/image export context.
    /// Each widget is drawn as a bordered card with type-specific body content.
    private static func renderWidgets(
        _ widgets: [NoteWidget],
        drawingScale: CGFloat,
        into ctx: CGContext
    ) {
        let sorted = widgets.sorted(by: { $0.zIndex < $1.zIndex })
        for widget in sorted {
            let bounds = widget.frame.boundingRect
            let exportRect = CGRect(
                x: bounds.origin.x * drawingScale,
                y: bounds.origin.y * drawingScale,
                width: bounds.size.width * drawingScale,
                height: bounds.size.height * drawingScale
            )
            let cr = WidgetConstants.cardCornerRadius * drawingScale
            let pad = WidgetConstants.containerPadding * drawingScale
            let titleSize = WidgetConstants.titleFontSize * drawingScale
            let bodySize = WidgetConstants.bodyFontSize * drawingScale

            // Card background
            let cardPath = UIBezierPath(roundedRect: exportRect, cornerRadius: cr)
            ctx.saveGState()
            let bgColor: UIColor = widget.kind == .referenceCard
                ? UIColor.systemGray6.withAlphaComponent(0.9)
                : UIColor.systemBackground.withAlphaComponent(0.85)
            ctx.setFillColor(bgColor.cgColor)
            ctx.addPath(cardPath.cgPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Border
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.separator.withAlphaComponent(WidgetConstants.borderOpacity).cgColor)
            ctx.setLineWidth(WidgetConstants.borderWidth * drawingScale)
            ctx.addPath(cardPath.cgPath)
            ctx.strokePath()
            ctx.restoreGState()

            // Clip body content
            ctx.saveGState()
            ctx.addPath(cardPath.cgPath)
            ctx.clip()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: titleSize, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: bodySize),
                .foregroundColor: UIColor.label
            ]

            switch widget.payload {
            case .checklist(let title, let items):
                var y = exportRect.minY + pad
                if !title.isEmpty {
                    let textRect = CGRect(x: exportRect.minX + pad, y: y,
                                          width: exportRect.width - pad * 2, height: titleSize + 4 * drawingScale)
                    (title as NSString).draw(in: textRect, withAttributes: titleAttrs)
                    y += titleSize + 8 * drawingScale
                }
                let cbSize = WidgetConstants.checkboxSize * drawingScale
                for item in items {
                    guard y + cbSize <= exportRect.maxY - pad else { break }
                    let cbRect = CGRect(x: exportRect.minX + pad, y: y, width: cbSize, height: cbSize)
                        .insetBy(dx: 2 * drawingScale, dy: 2 * drawingScale)
                    if item.isChecked {
                        ctx.setFillColor(UIColor.tintColor.cgColor)
                        ctx.fill(cbRect)
                    } else {
                        ctx.setStrokeColor(UIColor.secondaryLabel.cgColor)
                        ctx.setLineWidth(1.5 * drawingScale)
                        ctx.stroke(cbRect)
                    }
                    let textX = exportRect.minX + pad + cbSize + 6 * drawingScale
                    (item.text as NSString).draw(
                        in: CGRect(x: textX, y: y,
                                   width: exportRect.maxX - textX - pad, height: cbSize),
                        withAttributes: bodyAttrs
                    )
                    y += cbSize + 4 * drawingScale
                }

            case .quickTable(let title, let columns, let rows, let cells, _):
                var y = exportRect.minY + pad
                if !title.isEmpty {
                    let textRect = CGRect(x: exportRect.minX + pad, y: y,
                                          width: exportRect.width - pad * 2, height: titleSize + 4 * drawingScale)
                    (title as NSString).draw(in: textRect, withAttributes: titleAttrs)
                    y += titleSize + 8 * drawingScale
                }
                guard columns > 0, rows > 0 else { break }
                let tableW = exportRect.width - pad * 2
                let tableH = exportRect.maxY - y - pad
                let colW = tableW / CGFloat(columns)
                let rowH = tableH / CGFloat(rows)
                let tableX = exportRect.minX + pad
                ctx.saveGState()
                ctx.setStrokeColor(UIColor.separator.cgColor)
                ctx.setLineWidth(0.5 * drawingScale)
                for r in 0...rows {
                    let ly = y + CGFloat(r) * rowH
                    ctx.move(to: CGPoint(x: tableX, y: ly))
                    ctx.addLine(to: CGPoint(x: tableX + tableW, y: ly))
                }
                for c in 0...columns {
                    let lx = tableX + CGFloat(c) * colW
                    ctx.move(to: CGPoint(x: lx, y: y))
                    ctx.addLine(to: CGPoint(x: lx, y: y + tableH))
                }
                ctx.strokePath()
                ctx.restoreGState()
                let cp = WidgetConstants.cellPadding * drawingScale
                for r in 0..<rows {
                    for c in 0..<columns {
                        let idx = r * columns + c
                        guard idx < cells.count, !cells[idx].text.isEmpty else { continue }
                        let cellRect = CGRect(x: tableX + CGFloat(c) * colW + cp,
                                              y: y + CGFloat(r) * rowH + cp,
                                              width: colW - cp * 2, height: rowH - cp * 2)
                        let sz = (cells[idx].text as NSString).size(withAttributes: bodyAttrs)
                        (cells[idx].text as NSString).draw(
                            in: CGRect(x: cellRect.midX - sz.width / 2,
                                       y: cellRect.midY - sz.height / 2,
                                       width: sz.width, height: sz.height),
                            withAttributes: bodyAttrs
                        )
                    }
                }

            case .calloutBox(let title, let body, let style):
                let accentColor: UIColor
                switch style {
                case .note:      accentColor = UIColor.systemBlue.withAlphaComponent(0.5)
                case .important: accentColor = UIColor.systemOrange.withAlphaComponent(0.5)
                case .tip:       accentColor = UIColor.systemGreen.withAlphaComponent(0.5)
                case .warning:   accentColor = UIColor.systemRed.withAlphaComponent(0.5)
                }
                let barW = 4 * drawingScale
                ctx.setFillColor(accentColor.cgColor)
                ctx.fill(CGRect(x: exportRect.minX, y: exportRect.minY, width: barW, height: exportRect.height))
                let contentX = exportRect.minX + barW + pad
                let contentW = exportRect.width - barW - pad * 2
                var y = exportRect.minY + pad
                if !title.isEmpty {
                    (title as NSString).draw(
                        in: CGRect(x: contentX, y: y, width: contentW, height: titleSize + 4 * drawingScale),
                        withAttributes: titleAttrs
                    )
                    y += titleSize + 8 * drawingScale
                }
                if !body.isEmpty {
                    (body as NSString).draw(
                        in: CGRect(x: contentX, y: y, width: contentW, height: exportRect.maxY - y - pad),
                        withAttributes: bodyAttrs
                    )
                }

            case .referenceCard(let title, let body):
                var y = exportRect.minY + pad
                if !title.isEmpty {
                    (title as NSString).draw(
                        in: CGRect(x: exportRect.minX + pad, y: y,
                                   width: exportRect.width - pad * 2, height: titleSize + 4 * drawingScale),
                        withAttributes: titleAttrs
                    )
                    y += titleSize + 8 * drawingScale
                }
                if !body.isEmpty {
                    (body as NSString).draw(
                        in: CGRect(x: exportRect.minX + pad, y: y,
                                   width: exportRect.width - pad * 2, height: exportRect.maxY - y - pad),
                        withAttributes: bodyAttrs
                    )
                }
            }

            ctx.restoreGState()
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

    private static func drawCornellRuling(ctx: CGContext, rect: CGRect, color: UIColor) {
        let ruledSpacing: CGFloat = 28
        let cornellCueX: CGFloat = 224
        let cornellHeaderY: CGFloat = 56
        let summaryY = rect.height * 0.82

        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5)
        var y = cornellHeaderY + ruledSpacing
        while y < summaryY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += ruledSpacing
        }
        ctx.strokePath()

        let accentAlpha = color.cgColor.alpha * 2.2   // slightly stronger accent
        let accentColor = color.withAlphaComponent(min(accentAlpha, 0.30))
        ctx.setStrokeColor(accentColor.cgColor)
        ctx.setLineWidth(0.75)
        ctx.move(to: CGPoint(x: rect.minX, y: cornellHeaderY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: cornellHeaderY))
        ctx.move(to: CGPoint(x: cornellCueX, y: cornellHeaderY))
        ctx.addLine(to: CGPoint(x: cornellCueX, y: summaryY))
        ctx.move(to: CGPoint(x: rect.minX, y: summaryY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: summaryY))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawHexGrid(ctx: CGContext, rect: CGRect, color: UIColor) {
        let r: CGFloat = 22
        let w = r * sqrt(3.0)
        let gridColor = color.withAlphaComponent(color.cgColor.alpha * 0.80)
        ctx.saveGState()
        ctx.setStrokeColor(gridColor.cgColor)
        ctx.setLineWidth(0.5)
        let cols = Int(ceil(rect.width  / w)) + 2
        let rows = Int(ceil(rect.height / (r * 1.5))) + 2
        for col in -1..<cols {
            let cx = rect.minX + CGFloat(col) * w + w * 0.5
            let offset: CGFloat = (col % 2 == 0) ? 0 : r
            for row in -1..<rows {
                let cy = rect.minY + CGFloat(row) * r * 1.5 + offset
                ctx.move(to: hexVertexExport(cx: cx, cy: cy, r: r, index: 0))
                for i in 1...5 { ctx.addLine(to: hexVertexExport(cx: cx, cy: cy, r: r, index: i)) }
                ctx.closePath()
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func hexVertexExport(cx: CGFloat, cy: CGFloat, r: CGFloat, index: Int) -> CGPoint {
        let angle = (60.0 * Double(index) - 30.0) * .pi / 180.0
        return CGPoint(x: cx + r * CGFloat(cos(angle)), y: cy + r * CGFloat(sin(angle)))
    }

    private static func drawMusicStaff(ctx: CGContext, rect: CGRect, color: UIColor) {
        let staffLineSpacing: CGFloat = 8
        let staffGroupGap: CGFloat = 32
        let linesPerGroup = 5
        let staffGroupHeight = CGFloat(linesPerGroup - 1) * staffLineSpacing
        let period = staffGroupHeight + staffGroupGap
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.75)
        var groupTop = staffGroupGap * 0.5
        while groupTop < rect.maxY {
            for i in 0..<linesPerGroup {
                let y = groupTop + CGFloat(i) * staffLineSpacing
                if y > rect.maxY { break }
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            groupTop += period
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
