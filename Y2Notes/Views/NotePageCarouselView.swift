import SwiftUI
import PencilKit
import OSLog

private let carouselLogger = Logger(subsystem: "com.y2notes", category: "NotePageCarousel")

/// SwiftUI horizontal page carousel for a multi-page note.
///
/// Uses `ScrollView(.horizontal)` with `.scrollTargetBehavior(.paging)` for
/// natural single-finger page navigation. Each page is a persistent
/// `CanvasPageView` instance — no teardown/recreation on page change.
///
/// **Zoom isolation**: per-page zoom state is tracked via `pageZooms`.
/// When the current page zoom exceeds 1.02× (the hysteresis threshold),
/// the horizontal carousel scroll is disabled so pinch-pan gestures don't
/// accidentally trigger a page turn. The stored zoom value is passed back
/// to `CanvasPageView.initialZoomScale` so pages resume at their last zoom
/// level after being swiped away and back.
struct NotePageCarouselView: View {
    let note: Note
    @Binding var currentPageIndex: Int
    let noteID: UUID
    let backgroundColor: UIColor
    let defaultInkColor: UIColor
    let currentTool: PKTool
    let isShapeToolActive: Bool
    let activeShapeType: ShapeType
    let shapeColor: UIColor
    let shapeWidth: Double
    let drawingPolicy: PKCanvasViewDrawingPolicy
    let zoomResetTrigger: Bool
    let pageTypeForIndex: (Int) -> PageType
    let activeFX: WritingFXType
    let fxColor: UIColor
    let onDrawingChanged: (Data, Int) -> Void
    let onSaveRequested: () -> Void
    var onUndoStateChanged: ((Bool, Bool) -> Void)?
    var onPinchToOverview: (() -> Void)?
    var pdfURL: URL?
    var toolStoreForFade: DrawingToolStore?
    var onShapesChanged: (([ShapeInstance], Int) -> Void)?
    var onAttachmentsChanged: (([AttachmentObject], Int) -> Void)?
    var onAttachmentSelectionChanged: ((UUID?) -> Void)?
    var onWidgetsChanged: (([NoteWidget], Int) -> Void)?
    var onWidgetSelectionChanged: ((UUID?) -> Void)?
    var currentPageStickers: [StickerInstance] = []
    var onStickersChanged: (([StickerInstance]) -> Void)?
    var onStickerSelectionChanged: ((UUID?) -> Void)?
    var stickerImageProvider: ((String) -> UIImage?)?
    var isTextToolActive: Bool = false
    var onTextObjectsChanged: (([TextObject], Int) -> Void)?
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    var onPlaceTextObject: ((CGPoint) -> Void)?
    var isMagicModeActive: Bool = false
    var isStudyModeActive: Bool = false
    var activeAmbientScene: AmbientScene?
    var isAmbientSoundEnabled: Bool = true
    var isNewPage: Bool = false
    /// Called when the user taps the "add page" slot at the end of the carousel.
    var onAddPage: (() -> Void)?

    // MARK: - Tuning

    /// Minimum zoom scale above which the horizontal page-carousel scroll is disabled,
    /// preventing conflict between per-page canvas zoom-pan and carousel swiping.
    /// 1.02 (2% above 1×) provides a small hysteresis gap so that minor bounce
    /// at the end of a zoom-back-to-1× gesture doesn't momentarily re-enable carousel
    /// scrolling before the user lifts their fingers.
    private static let minZoomForScrollDisable: CGFloat = 1.02

    // MARK: - State

    /// Per-page zoom levels, persisted across page switches so that returning to
    /// a previously visited page restores the user's zoom position.
    @State private var pageZooms: [Int: CGFloat] = [:]

    /// Pre-prepared impact generator for page-turn haptics.
    @State private var pageTurnHaptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            carouselScrollView
            pageIndicator
        }
        .onChange(of: currentPageIndex) { oldVal, newVal in
            guard oldVal != newVal else { return }
            pageTurnHaptic.impactOccurred(intensity: 0.5)
            carouselLogger.debug("Page turned: \(oldVal) → \(newVal)")
        }
        .onAppear {
            pageTurnHaptic.prepare()
        }
    }

    // MARK: - Carousel

    private var carouselScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(note.pages.indices, id: \.self) { idx in
                    pageView(for: idx)
                        .containerRelativeFrame(.horizontal)
                        .tag(idx)
                }
                addPageSlot
                    .containerRelativeFrame(.horizontal)
                    .tag(note.pages.count)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding<Int?>(
            get: { currentPageIndex },
            set: { if let v = $0 { currentPageIndex = v } }
        ))
        .scrollDisabled(pageZooms[currentPageIndex, default: 1.0] > Self.minZoomForScrollDisable)
    }

    // MARK: - Page Indicator

    /// Minimal page dot indicator at the bottom of the carousel. Only shown when
    /// the note has more than one page and the current page is at base zoom
    /// (so it doesn't overlap zoomed-in content).
    private var pageIndicator: some View {
        Group {
            if note.pageCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<note.pageCount, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentPageIndex ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: idx == currentPageIndex ? 7 : 5,
                                   height: idx == currentPageIndex ? 7 : 5)
                            .animation(.easeInOut(duration: 0.2), value: currentPageIndex)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 8)
                .opacity(pageZooms[currentPageIndex, default: 1.0] > Self.minZoomForScrollDisable ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: pageZooms[currentPageIndex, default: 1.0])
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Per-Page Canvas

    @ViewBuilder
    private func pageView(for idx: Int) -> some View {
        CanvasPageView(
            noteID: noteID,
            drawingData: idx < note.pages.count ? note.pages[idx] : Data(),
            backgroundColor: backgroundColor,
            defaultInkColor: defaultInkColor,
            currentTool: currentTool,
            isShapeToolActive: isShapeToolActive,
            activeShapeType: activeShapeType,
            shapeColor: shapeColor,
            shapeWidth: shapeWidth,
            drawingPolicy: drawingPolicy,
            zoomResetTrigger: zoomResetTrigger,
            pageType: pageTypeForIndex(idx),
            activeFX: activeFX,
            fxColor: fxColor,
            pageIndex: idx,
            onDrawingChanged: { data in onDrawingChanged(data, idx) },
            onSaveRequested: onSaveRequested,
            onUndoStateChanged: onUndoStateChanged,
            onPinchToOverview: onPinchToOverview,
            pdfURL: pdfURL,
            toolStoreForFade: toolStoreForFade,
            currentPageShapes: note.shapes(forPage: idx),
            onShapesChanged: { shapes in onShapesChanged?(shapes, idx) },
            currentPageAttachments: note.attachments(forPage: idx),
            attachmentNoteID: noteID,
            onAttachmentsChanged: { atts in onAttachmentsChanged?(atts, idx) },
            onAttachmentSelectionChanged: onAttachmentSelectionChanged,
            currentPageWidgets: note.widgets(forPage: idx),
            onWidgetsChanged: { widgets in onWidgetsChanged?(widgets, idx) },
            onWidgetSelectionChanged: onWidgetSelectionChanged,
            isTextToolActive: isTextToolActive,
            currentPageTextObjects: note.textObjects(forPage: idx),
            onTextObjectsChanged: { objs in onTextObjectsChanged?(objs, idx) },
            onTextObjectSelectionChanged: onTextObjectSelectionChanged,
            onPlaceTextObject: onPlaceTextObject,
            pageCount: note.pageCount,
            isMagicModeActive: isMagicModeActive,
            isStudyModeActive: isStudyModeActive,
            activeAmbientScene: activeAmbientScene,
            isAmbientSoundEnabled: isAmbientSoundEnabled,
            isNewPage: isNewPage && idx == currentPageIndex,
            onZoomChanged: { zoom in pageZooms[idx] = zoom },
            initialZoomScale: pageZooms[idx]
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
    }

    // MARK: - Add Page Slot

    private var addPageSlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .systemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text(NSLocalizedString("Pages.SwipeToAdd", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { onAddPage?() }
    }
}
