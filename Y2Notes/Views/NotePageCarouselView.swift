import SwiftUI
import PencilKit

/// SwiftUI horizontal page carousel for a multi-page note.
///
/// Uses `ScrollView(.horizontal)` with `.scrollTargetBehavior(.paging)` for
/// natural single-finger page navigation. Each page is a persistent
/// `CanvasPageView` instance — no teardown/recreation on page change.
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
    let paperMaterial: PaperMaterial
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
    var isTextToolActive: Bool = false
    var onTextObjectsChanged: (([TextObject], Int) -> Void)?
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    var onPlaceTextObject: ((CGPoint) -> Void)?
    var isMagicModeActive: Bool = false
    var isStudyModeActive: Bool = false
    var activeAmbientScene: AmbientScene?
    var isAmbientSoundEnabled: Bool = true
    var isNewPage: Bool = false

    /// Minimum zoom scale above which the horizontal page-carousel scroll is disabled,
    /// preventing conflict between per-page canvas zoom-pan and carousel swiping.
    /// 1.02 (2% above 1×) provides a small hysteresis gap so that minor bounce
    /// at the end of a zoom-back-to-1× gesture doesn't momentarily re-enable carousel
    /// scrolling before the user lifts their fingers.
    private static let minZoomForScrollDisable: CGFloat = 1.02

    @State private var pageZooms: [Int: CGFloat] = [:]

    var body: some View {
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
        .scrollPosition(id: $currentPageIndex)
        .scrollDisabled(pageZooms[currentPageIndex, default: 1.0] > Self.minZoomForScrollDisable)
    }

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
            paperMaterial: paperMaterial,
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
            onZoomChanged: { zoom in pageZooms[idx] = zoom }
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
    }

    private var addPageSlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .systemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text("Swipe to add a page")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
    }
}
