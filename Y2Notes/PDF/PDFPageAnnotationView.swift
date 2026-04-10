import SwiftUI
import PDFKit
import PencilKit

// MARK: - PDFPageAnnotationView

/// A `UIViewRepresentable` that renders a single PDF page via `PDFView` and layers a
/// transparent `PKCanvasView` on top for freehand annotation, with additional SwiftUI
/// overlays for stickers and widgets.
///
/// **Annotation mode vs. read mode:**
/// - When `isAnnotating` is `true` the canvas captures all touches (drawing).
/// - When `isAnnotating` is `false` the canvas is non-interactive and `PDFView` handles
///   all touches (hyperlink navigation, text selection, scroll).
///
/// **Page navigation:**
/// - SwiftUI drives the current page via `pageIndex`.
/// - Internal navigation (e.g. user taps a hyperlink) fires `onPageChanged`.
/// - When the page changes the canvas drawing is swapped automatically.
struct PDFPageAnnotationView: UIViewRepresentable {

    let pdfURL: URL
    let pageIndex: Int
    /// All annotation data for the document (key = page index as decimal string).
    let annotationData: [String: Data]
    let currentTool: PKTool
    let drawingPolicy: PKCanvasViewDrawingPolicy
    let isAnnotating: Bool
    /// Called when internal PDF navigation changes the visible page.
    let onPageChanged: (Int) -> Void
    /// Called ~0.8 s after the user stops drawing; provides (pageIndex, drawingData).
    let onAnnotationChanged: (Int, Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPageChanged: onPageChanged,
            onAnnotationChanged: onAnnotationChanged
        )
    }

    func makeUIView(context: Context) -> PDFAnnotationContainer {
        let container = PDFAnnotationContainer()
        container.configure(
            pdfURL: pdfURL,
            pageIndex: pageIndex,
            annotationData: annotationData,
            tool: currentTool,
            drawingPolicy: drawingPolicy,
            isAnnotating: isAnnotating,
            coordinator: context.coordinator
        )
        return container
    }

    func updateUIView(_ uiView: PDFAnnotationContainer, context: Context) {
        context.coordinator.onPageChanged      = onPageChanged
        context.coordinator.onAnnotationChanged = onAnnotationChanged
        uiView.update(
            pageIndex: pageIndex,
            annotationData: annotationData,
            tool: currentTool,
            drawingPolicy: drawingPolicy,
            isAnnotating: isAnnotating
        )
    }
}

// MARK: - PDFAnnotationContainer

/// The `UIView` that hosts `PDFView` (bottom) and `PKCanvasView` (top).
final class PDFAnnotationContainer: UIView {

    private(set) var pdfView: PDFView = PDFView()
    private(set) var canvas: PKCanvasView = PKCanvasView()

    /// The page index currently displayed, tracked to detect navigation changes.
    private(set) var currentPageIndex: Int = 0
    /// Keeps the latest annotation data so internal navigation can load the right drawing.
    private var latestAnnotationData: [String: Data] = [:]

    weak var coordinator: PDFPageAnnotationView.Coordinator?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func setup() {
        backgroundColor = .systemBackground

        // ── PDFView ────────────────────────────────────────────────────
        pdfView.displayMode      = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.autoScales       = true
        pdfView.backgroundColor  = .systemBackground
        pdfView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // ── PKCanvasView ───────────────────────────────────────────────
        // The canvas must NOT have its own zoom/scroll — PDFView owns zoom.
        canvas.backgroundColor  = .clear
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0
        canvas.isScrollEnabled  = false
        canvas.translatesAutoresizingMaskIntoConstraints = false

        addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Observe PDFKit page-change notification (hyperlinks, go(to:), etc.).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfPageDidChange),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Give PKCanvasView a valid drawing area that matches the view bounds.
        // Without this, the canvas contentSize may be zero and drawing input
        // is silently ignored.
        canvas.contentSize = bounds.size
    }

    // MARK: - Configuration

    func configure(
        pdfURL: URL,
        pageIndex: Int,
        annotationData: [String: Data],
        tool: PKTool,
        drawingPolicy: PKCanvasViewDrawingPolicy,
        isAnnotating: Bool,
        coordinator: PDFPageAnnotationView.Coordinator
    ) {
        self.coordinator = coordinator
        canvas.delegate  = coordinator
        latestAnnotationData = annotationData

        if let document = PDFDocument(url: pdfURL) {
            pdfView.document = document
        }
        canvas.tool          = tool
        canvas.drawingPolicy = drawingPolicy
        canvas.isUserInteractionEnabled = isAnnotating

        goToPage(pageIndex, annotationData: annotationData)
        DispatchQueue.main.async { self.canvas.becomeFirstResponder() }
    }

    func update(
        pageIndex: Int,
        annotationData: [String: Data],
        tool: PKTool,
        drawingPolicy: PKCanvasViewDrawingPolicy,
        isAnnotating: Bool
    ) {
        canvas.tool          = tool
        canvas.drawingPolicy = drawingPolicy
        canvas.isUserInteractionEnabled = isAnnotating

        latestAnnotationData = annotationData

        if pageIndex != currentPageIndex {
            goToPage(pageIndex, annotationData: annotationData)
        }
    }

    // MARK: - Internal navigation

    private func goToPage(_ index: Int, annotationData: [String: Data]) {
        guard let doc = pdfView.document,
              let page = doc.page(at: index) else { return }
        currentPageIndex = index
        pdfView.go(to: page)
        loadDrawing(for: index, from: annotationData)
    }

    private func loadDrawing(for pageIndex: Int, from annotationData: [String: Data]) {
        let data = annotationData[String(pageIndex)] ?? Data()
        if !data.isEmpty, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        } else {
            canvas.drawing = PKDrawing()
        }
    }

    // MARK: - PDFView notification

    @objc private func pdfPageDidChange() {
        guard let page = pdfView.currentPage,
              let doc  = pdfView.document else { return }
        let newIndex = doc.index(for: page)
        guard newIndex != NSNotFound, newIndex != currentPageIndex else { return }

        // Save the annotation for the page we're leaving.
        let outgoingData = canvas.drawing.dataRepresentation()
        coordinator?.flushAnnotation(page: currentPageIndex, data: outgoingData)

        // Load the annotation for the new page.
        currentPageIndex = newIndex
        loadDrawing(for: newIndex, from: latestAnnotationData)

        // Notify SwiftUI so it can update the page indicator.
        coordinator?.onPageChanged(newIndex)
    }
}

// MARK: - Coordinator

extension PDFPageAnnotationView {

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onPageChanged:       (Int) -> Void
        var onAnnotationChanged: (Int, Data) -> Void

        private var debounceTimer: Timer?
        private var pendingPage: Int = 0

        init(
            onPageChanged: @escaping (Int) -> Void,
            onAnnotationChanged: @escaping (Int, Data) -> Void
        ) {
            self.onPageChanged       = onPageChanged
            self.onAnnotationChanged = onAnnotationChanged
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            debounceTimer?.invalidate()
            guard let container = canvasView.superview as? PDFAnnotationContainer else { return }
            let page = container.currentPageIndex
            let data = canvasView.drawing.dataRepresentation()
            pendingPage = page
            debounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.8, repeats: false
            ) { [weak self] _ in
                self?.onAnnotationChanged(page, data)
            }
        }

        // MARK: Internal flush (called before loading new drawing)

        func flushAnnotation(page: Int, data: Data) {
            debounceTimer?.invalidate()
            debounceTimer = nil
            onAnnotationChanged(page, data)
        }
    }
}
