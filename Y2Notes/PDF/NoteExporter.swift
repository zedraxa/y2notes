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
    /// Each page is drawn as: background fill → optional ruling lines → PKDrawing.
    /// The PKDrawing is scaled from the app's on-screen canvas dimensions to the
    /// standard PDF page size while preserving the aspect ratio.
    ///
    /// - Parameters:
    ///   - title:           Display name used as the PDF filename (special characters sanitised).
    ///   - pages:           Serialised `PKDrawing` data — one element per note page.
    ///   - backgroundColor: Canvas background colour (theme + paper-material blend).
    ///   - pageTypes:       Ruling style per page.  Element *i* is used for `pages[i]`.
    ///                      If `pageTypes` is shorter than `pages`, remaining pages are blank.
    /// - Returns: A temporary file URL pointing at the rendered PDF, or `nil` on failure.
    static func exportAsPDF(
        title: String,
        pages: [Data],
        backgroundColor: UIColor,
        pageTypes: [PageType]
    ) async -> URL? {
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
                        renderPage(
                            data: pageData,
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
    ///   - pageData:        Serialised `PKDrawing` data for the page.
    ///   - backgroundColor: Canvas background colour.
    ///   - pageType:        Ruling style drawn behind the strokes.
    ///   - scale:           Rendering scale factor (default 2× for Retina).
    /// - Returns: A rendered `UIImage`, or `nil` when the page data cannot be decoded.
    static func exportPageAsImage(
        pageData: Data,
        backgroundColor: UIColor,
        pageType: PageType,
        scale: CGFloat = 2.0
    ) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: pdfPageSize, format: format)
            return renderer.image { rendererCtx in
                renderPage(
                    data: pageData,
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
    ///   3. `PKDrawing` strokes scaled to fit the destination `pageSize`
    ///
    /// - Parameters:
    ///   - data:            Serialised `PKDrawing`.  Empty data → blank page, no strokes.
    ///   - pageSize:        Destination canvas size (PDF or image).
    ///   - backgroundColor: Fill colour for the page background.
    ///   - pageType:        Ruling style.
    ///   - ctx:             Core Graphics context already prepared by the caller.
    private static func renderPage(
        data: Data,
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

        // 3. PKDrawing — scale from the on-screen canvas dimensions to `pageSize`
        guard !data.isEmpty,
              let drawing = try? PKDrawing(data: data),
              !drawing.strokes.isEmpty else { return }

        // Recompute the on-screen canvas size (mirrors CanvasView.pageSize).
        let screenBounds = UIScreen.main.bounds
        let screenW = max(screenBounds.width, screenBounds.height)
        let canvasPageSize = CGSize(width: screenW, height: ceil(screenW * 1.414))

        let scaleX = pageSize.width  / canvasPageSize.width
        let scaleY = pageSize.height / canvasPageSize.height
        let drawingScale = min(scaleX, scaleY)

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
