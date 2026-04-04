import PencilKit
import PDFKit
import UIKit

// MARK: - NotePDFGenerator

/// Generates and maintains PDF files that back every note, giving the app a
/// "book-like" feel where each note *is* a PDF document.
///
/// **Template PDFs** contain only the page background (colour, ruling, grain)
/// and are generated once when a note is created.
///
/// **Composite PDFs** overlay PencilKit strokes on top of the template and are
/// regenerated on every debounced save so the on-disk PDF always reflects the
/// latest drawing state.
///
/// All rendering uses the same geometry constants as `NoteExporter` and
/// `PageBackgroundView` for pixel-perfect consistency.
enum NotePDFGenerator {

    // MARK: - Paper dimensions

    /// Standard US Letter at 72 pt/in — matches `NoteExporter.pdfPageSize`.
    static let pdfPageSize = CGSize(width: 612, height: 792)

    /// Directory inside Documents/ where note PDFs are stored.
    static let pdfDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("NotePDFs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - URL helpers

    /// Returns the absolute file URL for a given PDF filename.
    static func pdfURL(for filename: String) -> URL {
        pdfDirectory.appendingPathComponent(filename)
    }

    // MARK: - Template PDF generation

    /// Creates a multi-page template PDF containing only page backgrounds (colour + ruling).
    /// This is the initial "empty notebook" PDF that strokes are overlaid onto.
    ///
    /// - Parameters:
    ///   - pageCount:       Number of blank pages to generate.
    ///   - backgroundColor: Fill colour for every page.
    ///   - pageTypes:       Ruling style per page.  Shorter than `pageCount` → `.blank` for rest.
    /// - Returns: A unique filename (UUID-based) for the generated PDF, or `nil` on failure.
    @discardableResult
    static func generateTemplatePDF(
        pageCount: Int,
        backgroundColor: UIColor,
        pageTypes: [PageType]
    ) -> String? {
        let filename = UUID().uuidString + ".pdf"
        let url = pdfURL(for: filename)
        let pageRect = CGRect(origin: .zero, size: pdfPageSize)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        do {
            try renderer.writePDF(to: url) { pdfCtx in
                for i in 0 ..< max(pageCount, 1) {
                    pdfCtx.beginPage()
                    let ctx = pdfCtx.cgContext
                    let pt = i < pageTypes.count ? pageTypes[i] : .blank
                    renderBackground(
                        pageSize: pdfPageSize,
                        backgroundColor: backgroundColor,
                        pageType: pt,
                        into: ctx
                    )
                }
            }
            return filename
        } catch {
            return nil
        }
    }

    // MARK: - Composite PDF generation (background + strokes)

    /// Regenerates the note's backing PDF by compositing page backgrounds with
    /// PencilKit strokes.  Overwrites the file at `filename` in place.
    ///
    /// Called on the debounced save path so the on-disk PDF always mirrors the
    /// latest drawing state.
    ///
    /// - Parameters:
    ///   - filename:        Existing PDF filename to overwrite.
    ///   - pages:           Serialised `PKDrawing` data — one element per page.
    ///   - backgroundColor: Canvas background colour.
    ///   - pageTypes:       Ruling style per page.
    static func regeneratePDF(
        filename: String,
        pages: [Data],
        backgroundColor: UIColor,
        pageTypes: [PageType]
    ) {
        let url = pdfURL(for: filename)
        let pageRect = CGRect(origin: .zero, size: pdfPageSize)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        do {
            try renderer.writePDF(to: url) { pdfCtx in
                for (i, pageData) in pages.enumerated() {
                    pdfCtx.beginPage()
                    let ctx = pdfCtx.cgContext
                    let pt = i < pageTypes.count ? pageTypes[i] : .blank
                    renderBackground(
                        pageSize: pdfPageSize,
                        backgroundColor: backgroundColor,
                        pageType: pt,
                        into: ctx
                    )
                    renderStrokes(data: pageData, pageSize: pdfPageSize, into: ctx)
                }
            }
        } catch {
            // Best-effort — the note is still editable from in-memory PKDrawing data.
            #if DEBUG
            print("NotePDFGenerator: regenerate failed — \(error)")
            #endif
        }
    }

    // MARK: - Cleanup

    /// Deletes the backing PDF file for a note.
    static func deletePDF(filename: String) {
        let url = pdfURL(for: filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private rendering helpers

    /// Draws the page background (fill + ruling) into a CGContext.
    /// Mirrors `NoteExporter.renderPage` and `PageBackgroundView.draw(_:)`.
    private static func renderBackground(
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
    }

    /// Draws PencilKit strokes scaled from on-screen canvas dimensions to PDF page size.
    private static func renderStrokes(
        data: Data,
        pageSize: CGSize,
        into ctx: CGContext
    ) {
        guard !data.isEmpty,
              let drawing = try? PKDrawing(data: data),
              !drawing.strokes.isEmpty else { return }

        let screenBounds = UIScreen.main.bounds
        let screenW = max(screenBounds.width, screenBounds.height)
        let canvasPageSize = CGSize(width: screenW, height: ceil(screenW * 1.414))

        let scaleX = pageSize.width / canvasPageSize.width
        let scaleY = pageSize.height / canvasPageSize.height
        let drawingScale = min(scaleX, scaleY)

        let drawingImage = drawing.image(
            from: CGRect(origin: .zero, size: canvasPageSize),
            scale: drawingScale
        )
        let drawRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: canvasPageSize.width * drawingScale,
                height: canvasPageSize.height * drawingScale
            )
        )
        drawingImage.draw(in: drawRect)
    }

    // MARK: - Ruling line helpers (identical to NoteExporter)

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
