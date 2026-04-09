import SwiftUI
import PencilKit
import OSLog

private let carouselLogger = Logger(subsystem: "com.y2notes", category: "NotebookCarousel")

// MARK: - NotebookCarouselView

/// Configuration-driven page carousel for the notebook experience.
///
/// Replaces `NotePageCarouselView` with a clean API that accepts factory
/// closures instead of 60+ individual parameters.
///
/// ## Key Improvements over NotePageCarouselView
/// - **3 properties** instead of 60+
/// - **Factory-based**: pages are built via `configurationForPage` / `callbacksForPage`
/// - **Same rendering**: internally uses `NotebookCanvasView` → `CanvasPageView`
///
/// ## Usage
/// ```swift
/// NotebookCarouselView(
///     note: note,
///     currentPageIndex: $currentPageIndex,
///     configurationForPage: { idx in .page(for: note, at: idx, ...) },
///     callbacksForPage: { idx in .forPage(idx, note: note, ...) }
/// )
/// ```
struct NotebookCarouselView: View {

    /// The note model.
    let note: Note
    /// Zero-based index of the currently displayed page.
    @Binding var currentPageIndex: Int

    /// Factory that builds a `CanvasPageConfiguration` for the given page index.
    let configurationForPage: (Int) -> CanvasPageConfiguration
    /// Factory that builds a `CanvasPageCallbacks` for the given page index.
    let callbacksForPage: (Int) -> CanvasPageCallbacks

    /// Reference to the drawing tool store for toolbar auto-fade.
    var toolStore: DrawingToolStore?
    /// Image provider for rendering sticker assets.
    var stickerImageProvider: ((String) -> UIImage?)?

    // MARK: - Tuning

    /// Minimum zoom above which horizontal carousel scroll is disabled.
    private static let minZoomForScrollDisable: CGFloat = 1.02

    // MARK: - State

    /// Per-page zoom levels, persisted across page switches.
    @State private var pageZooms: [Int: CGFloat] = [:]
    /// Pre-prepared haptic generator for page-turn feedback.
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

    /// Returns callbacks for `idx` with zoom tracking wired so the carousel
    /// can disable horizontal scroll while the user is pinch-zoomed in.
    ///
    /// Extracted from `pageView(for:)` because SwiftUI's `@ViewBuilder`
    /// result builder treats every expression as a potential `View`; the
    /// bare assignment `callbacks.onZoomChanged = …` produces a `Void`
    /// expression that doesn't conform to `View` and causes a compile error.
    private func preparedCallbacks(for idx: Int) -> CanvasPageCallbacks {
        var callbacks = callbacksForPage(idx)
        callbacks.onZoomChanged = { zoom in pageZooms[idx] = zoom }
        return callbacks
    }

    @ViewBuilder
    private func pageView(for idx: Int) -> some View {
        let config = configurationForPage(idx)
            .withInitialZoomScale(pageZooms[idx] ?? configurationForPage(idx).initialZoomScale)
        let callbacks = preparedCallbacks(for: idx)

        NotebookCanvasView(
            configuration: config,
            callbacks: callbacks,
            toolStore: toolStore,
            stickerImageProvider: stickerImageProvider
        )
        .equatable()
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
                Text(NSLocalizedString("Pages.SwipeToAdd", comment: "Instruction text shown on empty page slot in carousel"))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
    }
}
