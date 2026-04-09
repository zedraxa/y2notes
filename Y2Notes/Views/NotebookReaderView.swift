import SwiftUI
import PencilKit

// MARK: - NotebookReaderView

/// Presents a ``Notebook`` as a physical book you flip through.
///
/// **Architecture**
/// Every note → page in the notebook is linearised into a flat index.
/// The user swipes left/right to turn pages.  Swiping past the last
/// page auto-creates a new blank page so writing never stops.
///
/// **Section tabs** at the top let you jump between sections.
/// A bottom navigation bar shows the section name and page number.
/// Stacked page shadows behind the current canvas give a book-like
/// depth feeling.
struct NotebookReaderView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var toolStore: DrawingToolStore
    @EnvironmentObject var inkStore: InkEffectStore
    @EnvironmentObject var navigationStore: NavigationStore
    @Environment(TabWorkspaceStore.self) private var workspace
    let notebook: Notebook
    /// The tab ID for state sync. `nil` when the reader is not hosted inside
    /// the tab workspace (e.g. launched directly from a shortcut or widget).
    let tabID: UUID?

    @State var flatPageIndex = 0
    @State private var didRestorePosition = false
    @State var showPageOverview = false
    /// Horizontal drag offset for the page-turn gesture.
    @State private var dragOffset: CGFloat = 0
    /// Direction of the last completed page turn for the slide transition.
    @State var slideDirection: Edge = .trailing
    /// Whether the jump-to-page popover is shown.
    @State private var showJumpToPage = false
    /// Text field content for jump-to-page.
    @State private var jumpPageText = ""
    /// Transient "saved" checkmark badge — auto-hides after 2 s.
    @State private var showSavedBadge = false
    /// Whether the bookmarks list sheet is shown.
    @State private var showBookmarks = false
    /// Whether the recent-locations popover is shown.
    @State private var showRecentLocations = false
    /// Whether the universal search sheet is shown.
    @State private var showUniversalSearch = false
    /// Whether the notebook cover page overlay is shown.
    @State private var isShowingCoverPage = false
    /// Whether the notebook info sheet is shown.
    @State private var showNotebookInfo = false

    // MARK: - Linearised page model

    /// A reference to a single page inside the notebook's note hierarchy.
    fileprivate struct PageRef: Identifiable {
        let id: String  // "\(noteID)-\(pageIndex)" for stable identity
        let noteID: UUID
        let noteTitle: String
        let pageIndex: Int
        let sectionID: UUID?
        let sectionName: String?
        /// True for the very first page contributed by a new section.
        let isFirstInSection: Bool
    }

    /// Flat ordered list of every page in the notebook.
    private var allPages: [PageRef] {
        var result: [PageRef] = []

        // Unsectioned notes first (notebook-level, no section)
        let unsectioned = noteStore.unsectionedPages(inNotebook: notebook.id)
        for note in unsectioned {
            for pIdx in 0..<note.pages.count {
                let isFirst = result.isEmpty
                result.append(PageRef(
                    id: "\(note.id)-\(pIdx)",
                    noteID: note.id,
                    noteTitle: note.title,
                    pageIndex: pIdx,
                    sectionID: nil,
                    sectionName: nil,
                    isFirstInSection: isFirst
                ))
            }
        }

        // Sections ordered by sortOrder
        let orderedSections = noteStore.sections(inNotebook: notebook.id)
            .filter { $0.kind == .section }

        for section in orderedSections {
            let sectionNotes = noteStore.pages(inSection: section.id)
            var isFirst = true
            for note in sectionNotes {
                for pIdx in 0..<note.pages.count {
                    result.append(PageRef(
                        id: "\(note.id)-\(pIdx)",
                        noteID: note.id,
                        noteTitle: note.title,
                        pageIndex: pIdx,
                        sectionID: section.id,
                        sectionName: section.name,
                        isFirstInSection: isFirst
                    ))
                    isFirst = false
                }
            }
        }

        return result
    }

    /// Unique sections for the tab bar (including a pseudo-section for unsectioned notes).
    private var sectionTabs: [(id: UUID?, name: String, firstFlatIndex: Int)] {
        let pages = allPages
        var seen = Set<String>()
        var tabs: [(id: UUID?, name: String, firstFlatIndex: Int)] = []
        for (i, page) in pages.enumerated() {
            let key = page.sectionID?.uuidString ?? "__unsectioned__"
            if !seen.contains(key) {
                seen.insert(key)
                tabs.append((
                    id: page.sectionID,
                    name: page.sectionName ?? "General",
                    firstFlatIndex: i
                ))
            }
        }
        return tabs
    }

    // MARK: - Current page helpers

    private var currentPage: PageRef? {
        let pages = allPages
        guard !pages.isEmpty else { return nil }
        let idx = min(flatPageIndex, pages.count - 1)
        return pages[idx]
    }

    private var currentNote: Note? {
        guard let ref = currentPage else { return nil }
        return noteStore.notes.first { $0.id == ref.noteID }
    }

    private var effectiveTheme: AppTheme {
        currentNote?.themeOverride ?? notebook.defaultTheme ?? themeStore.effectiveTheme
    }

    var effectiveDefinition: ThemeDefinition {
        effectiveTheme.definition
    }

    var effectivePaperMaterial: PaperMaterial {
        currentNote?.paperMaterial ?? notebook.paperMaterial
    }

    /// Per-page ruling: pageTypes[pageIndex] → note.pageType → section.defaultPageType → notebook.pageType → .blank
    fileprivate func effectivePageType(for ref: PageRef) -> PageType {
        guard let note = noteStore.notes.first(where: { $0.id == ref.noteID }) else {
            return notebook.pageType
        }
        if let perPage = note.pageType(forPage: ref.pageIndex) ?? note.pageType {
            return perPage
        }
        // Section-level override
        if let secID = ref.sectionID,
           let section = noteStore.sections(inNotebook: notebook.id).first(where: { $0.id == secID }),
           let sectionType = section.defaultPageType {
            return sectionType
        }
        return notebook.pageType
    }

    /// Canvas background: per-page colour → theme + material blend.
    fileprivate func canvasBackground(for ref: PageRef) -> UIColor {
        if let note = noteStore.notes.first(where: { $0.id == ref.noteID }),
           let explicit = note.pageColor(forPage: ref.pageIndex) {
            return explicit
        }
        return blendedBackground(
            base: effectiveDefinition.canvasBackground,
            tint: effectivePaperMaterial.pageTint
        )
    }

    // MARK: - Body

    var body: some View {
        let pages = allPages
        VStack(spacing: 0) {
            // Notebook identity bar — gradient strip with texture hint
            ZStack {
                notebook.cover.gradient
                CoverTextureOverlay(
                    texture: notebook.coverTexture,
                    size: CGSize(width: 600, height: 4),
                    intensity: 0.6
                )
            }
            .frame(height: 4)
            .opacity(0.85)

            // Section tabs
            if sectionTabs.count > 1 {
                sectionTabsBar
            }

            if pages.isEmpty {
                emptyNotebookView
            } else {
                let safeIndex = min(flatPageIndex, pages.count - 1)
                let ref = pages[safeIndex]

                // Section divider label when crossing into a new section
                if ref.isFirstInSection, let name = ref.sectionName {
                    sectionDividerBanner(name)
                }

                // Desk surface + page stack + floating toolbar
                ZStack(alignment: .bottom) {
                    ZStack {
                        // Desk background — the page sits on a surface, not floating in void
                        Color(uiColor: UIColor.secondarySystemBackground)

                        // Page edge indicators (visible book edges)
                        pageEdgeIndicators(pageCount: pages.count, currentIndex: safeIndex)

                        // Background page shadows — fake "stacked pages" effect
                        pageStackShadows(pageCount: pages.count, currentIndex: safeIndex)

                        // Current page canvas
                        readerCanvasForPage(ref, in: pages)
                            .offset(x: dragOffset)
                            // Subtle 3D page-flip hint: ~7.5° max at full 500pt drag
                            .rotation3DEffect(
                                Angle.degrees(Double(dragOffset) * 0.015),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.5
                            )
                    }
                    .gesture(pageSwipeGesture(totalPages: pages.count))
                    .clipped()

                    // Cover page overlay (appears on top of canvas)
                    if isShowingCoverPage {
                        notebookCoverPageView
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .zIndex(10)
                    }

                    // Floating toolbar capsule — bottom-center, above page bar
                    FloatingToolbarCapsule(
                        toolStore: toolStore,
                        inkStore: inkStore
                    )
                    .opacity(toolStore.toolbarOpacity)
                    .animation(.easeInOut(duration: 0.3), value: toolStore.toolbarOpacity)
                    .allowsHitTesting(toolStore.toolbarOpacity > 0.5)
                    .padding(.bottom, 8)
                }

                // Page navigation bar
                notebookPageBar(totalPages: pages.count)
            }
        }
        .navigationTitle(notebook.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                // Back button
                Button {
                    navigateBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .medium))
                }
                .disabled(!navigationStore.canGoBack)
                .accessibilityLabel("Go back")

                // Forward button
                Button {
                    navigateForward()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .medium))
                }
                .disabled(!navigationStore.canGoForward)
                .accessibilityLabel("Go forward")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Cover page toggle
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isShowingCoverPage.toggle()
                    }
                } label: {
                    Image(systemName: isShowingCoverPage ? "book.fill" : "book")
                        .font(.system(size: 14, weight: .medium))
                }
                .accessibilityLabel(isShowingCoverPage ? "Hide cover page" : "Show cover page")

                // Universal search
                Button {
                    showUniversalSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                }
                .accessibilityLabel("Search notebook")

                // Recent locations
                Button {
                    showRecentLocations = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .medium))
                }
                .popover(isPresented: $showRecentLocations) {
                    RecentLocationsView(
                        notebook: notebook
                    ) { anchor in navigateToAnchor(anchor) }
                }
                .accessibilityLabel("Recent pages")

                // Bookmarks list
                Button {
                    showBookmarks = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 14, weight: .medium))
                }
                .accessibilityLabel("Bookmarks")

                // Page overview grid
                Button {
                    showPageOverview = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .medium))
                }
                .accessibilityLabel("Page overview")

                // Notebook info
                Button {
                    showNotebookInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                }
                .accessibilityLabel("Notebook info")

                // Lock indicator
                if notebook.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Notebook is locked")
                }
            }
        }
        .sheet(isPresented: $showPageOverview) {
            notebookPageOverviewSheet
        }
        .sheet(isPresented: $showBookmarks) {
            NavigationStack {
                BookmarkListView(
                    notebook: notebook
                ) { anchor in navigateToAnchor(anchor) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showUniversalSearch) {
            UniversalSearchView(
                currentNotebookID: notebook.id,
                onSelectNote: { noteID in
                    // Navigate to the first page of the selected note
                    let anchor = NavigationAnchor(
                        notebookID: notebook.id,
                        noteID: noteID,
                        pageIndex: 0
                    )
                    navigateToAnchor(anchor)
                },
                onJumpToAnchor: { anchor in
                    navigateToAnchor(anchor)
                }
            )
        }
        .sheet(isPresented: $showNotebookInfo) {
            NotebookInfoView(notebook: notebook)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .topTrailing) {
            if showSavedBadge {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onChange(of: noteStore.saveState) { _, newState in
            if newState == .saved {
                withAnimation(.easeIn(duration: 0.2)) { showSavedBadge = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeOut(duration: 0.3)) { showSavedBadge = false }
                }
            }
        }
        // Restore last page position when notebook opens (object permanence)
        .onAppear {
            navigationStore.activateNotebook(notebook.id)
            if !didRestorePosition {
                // Prefer the tab's persisted page index when running inside the
                // tab workspace; fall back to the notebook-level last-page store.
                let tabPage = tabID.flatMap { id in
                    workspace.tabs.first { $0.id == id }?.pageIndex
                }
                let saved = tabPage ?? noteStore.lastPageIndex(for: notebook.id)
                let maxIdx = max(0, allPages.count - 1)
                flatPageIndex = min(saved, maxIdx)
                didRestorePosition = true
            }
        }
        // Persist page position on every page turn + push history
        .onChange(of: flatPageIndex) { _, newIndex in
            noteStore.setLastPageIndex(newIndex, for: notebook.id)
            if let id = tabID {
                workspace.updateTabState(id, pageIndex: newIndex)
            }
            pushCurrentPageToHistory()
            if isShowingCoverPage {
                withAnimation(.easeOut(duration: 0.2)) { isShowingCoverPage = false }
            }
        }
    }

    // MARK: - Navigation helpers

    /// Pushes the current page into the navigation history.
    private func pushCurrentPageToHistory() {
        let pages = allPages
        let safeIndex = min(flatPageIndex, pages.count - 1)
        guard safeIndex >= 0 && safeIndex < pages.count else { return }
        let ref = pages[safeIndex]
        navigationStore.pushHistory(
            notebookID: notebook.id,
            noteID: ref.noteID,
            pageIndex: ref.pageIndex,
            flatPageIndex: safeIndex
        )
    }

    /// Navigates back in history.
    private func navigateBack() {
        let pages = allPages
        let safeIndex = min(flatPageIndex, pages.count - 1)
        guard safeIndex >= 0 && safeIndex < pages.count else { return }
        let ref = pages[safeIndex]
        if let entry = navigationStore.goBack(
            currentNotebookID: notebook.id,
            currentNoteID: ref.noteID,
            currentPageIndex: ref.pageIndex,
            currentFlatIndex: safeIndex
        ) {
            resolveAndJump(to: entry.anchor)
        }
    }

    /// Navigates forward in history.
    private func navigateForward() {
        let pages = allPages
        let safeIndex = min(flatPageIndex, pages.count - 1)
        guard safeIndex >= 0 && safeIndex < pages.count else { return }
        let ref = pages[safeIndex]
        if let entry = navigationStore.goForward(
            currentNotebookID: notebook.id,
            currentNoteID: ref.noteID,
            currentPageIndex: ref.pageIndex,
            currentFlatIndex: safeIndex
        ) {
            resolveAndJump(to: entry.anchor)
        }
    }

    /// Resolves a NavigationAnchor to a flat page index and navigates.
    private func navigateToAnchor(_ anchor: NavigationAnchor) {
        resolveAndJump(to: anchor)
        // Highlight a specific object (e.g. attachment) on the target page.
        if let objectID = anchor.objectID {
            Task { @MainActor in
                // Allow page transition to settle before selecting.
                try? await Task.sleep(for: .seconds(0.4))
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    toolStore.activeAttachmentSelection = objectID
                    toolStore.activeShapeSelection = nil
                    toolStore.activeStickerSelection = nil
                    toolStore.hasActiveSelection = false
                }
            }
        }
    }

    /// Resolves an anchor to a flat index and jumps.
    private func resolveAndJump(to anchor: NavigationAnchor) {
        let pages = allPages
        if let idx = pages.firstIndex(where: {
            $0.noteID == anchor.noteID && $0.pageIndex == anchor.pageIndex
        }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                flatPageIndex = idx
            }
        }
    }

    // MARK: - Canvas for a page

    /// Legacy canvas page construction — replaced by `readerCanvasForPage(_:in:)`
    /// in `NotebookReaderView+Canvas.swift`.
    ///
    /// Retained for reference during migration. Will be removed in a future release.
    @available(*, deprecated, message: "Use readerCanvasForPage(_:in:) instead")
    @ViewBuilder
    private func canvasForPage(_ ref: PageRef, in pages: [PageRef]) -> some View {
        if let note = noteStore.notes.first(where: { $0.id == ref.noteID }) {
            let pageData = note.pages.indices.contains(ref.pageIndex)
                ? note.pages[ref.pageIndex] : Data()
            CanvasView(
                noteID: note.id,
                drawingData: pageData,
                backgroundColor: canvasBackground(for: ref),
                defaultInkColor: effectiveDefinition.contrastingInkColor,
                currentTool: inkStore.activePreset?.pkTool ?? toolStore.pkTool,
                isShapeToolActive: toolStore.activeTool == .shape,
                activeShapeType: toolStore.activeShapeType,
                shapeColor: toolStore.activeColor,
                shapeWidth: toolStore.activeWidth,
                drawingPolicy: .anyInput,
                zoomResetTrigger: false,
                pageType: effectivePageType(for: ref),
                paperMaterial: effectivePaperMaterial,
                activeFX: inkStore.resolvedFX,
                fxColor: inkStore.activePreset?.uiColor ?? toolStore.activeColor,
                pageIndex: ref.pageIndex,
                onDrawingChanged: { data in
                    noteStore.updateDrawing(for: ref.noteID, pageIndex: ref.pageIndex, data: data)
                },
                onSaveRequested: { noteStore.save() },
                onUndoStateChanged: nil,
                onPageSwipe: { direction in
                    turnPage(direction: direction, totalPages: pages.count)
                },
                onPinchToOverview: { showPageOverview = true },
                pdfURL: noteStore.notePDFURL(for: note),
                toolStoreForFade: toolStore
            )
            .id("\(ref.noteID)-\(ref.pageIndex)")
            .overlay(alignment: .bottom) {
                // Page number watermark — like a printed notebook
                pageNumberWatermark(flatIndex: flatPageIndex, totalPages: pages.count)
            }
            .overlay(alignment: .leading) {
                // Left margin line on ruled pages — mimics traditional red margin on ruled paper
                if effectivePageType(for: ref) == .ruled {
                    Rectangle()
                        .fill(Color.red.opacity(0.08))
                        .frame(width: 1)
                        .padding(.leading, 28)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: slideDirection),
                removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
            ))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
            .padding(.horizontal, 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.88), value: flatPageIndex)
        }
    }

    // MARK: - Page stack shadows (book depth)

    /// Draws faint page edges behind the current canvas to simulate a paper stack.
    private func pageStackShadows(pageCount: Int, currentIndex: Int) -> some View {
        let pagesAfter = min(pageCount - 1 - currentIndex, 3)
        let pagesBefore = min(currentIndex, 3)
        return ZStack {
            // Pages "below" (stacked after current page — right edge)
            ForEach(0..<pagesAfter, id: \.self) { layer in
                let offset = CGFloat(layer + 1) * 2.0
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 2, x: offset, y: 1)
                    .padding(.horizontal, 4 + offset)
                    .padding(.vertical, offset)
                    .opacity(1.0 - Double(layer) * 0.25)
            }
            // Pages "above" (stacked before current page — left edge)
            ForEach(0..<pagesBefore, id: \.self) { layer in
                let offset = CGFloat(layer + 1) * 2.0
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 2, x: -offset, y: 1)
                    .padding(.horizontal, 4 + offset)
                    .padding(.vertical, offset)
                    .opacity(1.0 - Double(layer) * 0.25)
            }
        }
    }

    // MARK: - Page edge indicators (visible book edges)

    /// Subtle lines along left/right edges indicating remaining pages,
    /// like the visible edges of a closed physical book.
    private func pageEdgeIndicators(pageCount: Int, currentIndex: Int) -> some View {
        let pagesBefore = min(currentIndex, 6)
        let pagesAfter = min(pageCount - 1 - currentIndex, 6)
        return HStack {
            // Left edge — pages before
            VStack(spacing: 1.5) {
                ForEach(0..<pagesBefore, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(uiColor: .systemBackground).opacity(0.6))
                        .frame(width: 2, height: 6)
                }
            }
            .padding(.leading, 1)

            Spacer()

            // Right edge — pages after
            VStack(spacing: 1.5) {
                ForEach(0..<pagesAfter, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(uiColor: .systemBackground).opacity(0.6))
                        .frame(width: 2, height: 6)
                }
            }
            .padding(.trailing, 1)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    // MARK: - Page number watermark

    /// Subtle page number in the bottom-right corner of the page, like printed notebooks.
    func pageNumberWatermark(flatIndex: Int, totalPages: Int) -> some View {
        Text("\(flatIndex + 1)")
            .font(.system(size: 10, weight: .light, design: .serif))
            .foregroundStyle(.secondary.opacity(0.35))
            .padding(.trailing, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
    }

    // MARK: - Swipe gesture for page turns

    /// Horizontal drag that turns pages; swiping past the last page auto-creates a new one.
    private func pageSwipeGesture(totalPages: Int) -> some Gesture {
        DragGesture(minimumDistance: 40)
            .onChanged { value in
                // Only track horizontal drags that are clearly horizontal
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if horizontal > vertical * 1.2 {
                    // 50% drag ratio: responsive enough to feel physical without overshooting
                    dragOffset = value.translation.width * 0.5
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 60
                if value.translation.width < -threshold {
                    if isShowingCoverPage {
                        // Swipe left from cover → dismiss cover
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            dragOffset = 0
                            isShowingCoverPage = false
                        }
                    } else {
                        // Swipe left → next page (or create new)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            dragOffset = 0
                            turnPage(direction: 1, totalPages: totalPages)
                        }
                    }
                } else if value.translation.width > threshold {
                    if flatPageIndex == 0 && !isShowingCoverPage {
                        // Swipe right at page 0 → show cover
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            dragOffset = 0
                            isShowingCoverPage = true
                        }
                    } else {
                        // Swipe right → previous page
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            dragOffset = 0
                            turnPage(direction: -1, totalPages: totalPages)
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// Turns to the next or previous page. When swiping past the last page,
    /// auto-creates a new blank page so writing never stops.
    /// When the notebook is locked, auto-creation is suppressed.
    func turnPage(direction: Int, totalPages: Int) {
        if direction > 0 {
            slideDirection = .trailing
            if flatPageIndex >= totalPages - 1 {
                // Swipe past last page → auto-create new page (unless locked)
                guard !notebook.isLocked else { return }
                if let ref = currentPage,
                   let newIdx = noteStore.addPage(to: ref.noteID) {
                    let updatedPages = allPages
                    if let newFlat = updatedPages.firstIndex(where: {
                        $0.noteID == ref.noteID && $0.pageIndex == newIdx
                    }) {
                        flatPageIndex = newFlat
                    } else {
                        flatPageIndex = allPages.count - 1
                    }
                }
            } else {
                flatPageIndex = min(totalPages - 1, flatPageIndex + 1)
            }
        } else {
            slideDirection = .leading
            flatPageIndex = max(0, flatPageIndex - 1)
        }
    }

    // MARK: - Section tabs bar

    private var sectionTabsBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(sectionTabs, id: \.firstFlatIndex) { tab in
                        let isActive = currentPage?.sectionID == tab.id
                            || (tab.id == nil && currentPage?.sectionID == nil)
                        let tabColor = sectionColor(for: tab.id)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                flatPageIndex = tab.firstFlatIndex
                            }
                        } label: {
                            Text(tab.name)
                                .font(.subheadline.weight(isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? tabColor : .secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    isActive
                                        ? tabColor.opacity(0.12)
                                        : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .id(tab.firstFlatIndex)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.6))
            .onChange(of: flatPageIndex) { _, _ in
                if let tab = sectionTabs.last(where: { $0.firstFlatIndex <= flatPageIndex }) {
                    withAnimation { proxy.scrollTo(tab.firstFlatIndex, anchor: .center) }
                }
            }
        }
    }

    private func sectionColor(for sectionID: UUID?) -> Color {
        guard let id = sectionID,
              let section = noteStore.sections.first(where: { $0.id == id })
        else { return Color.accentColor }
        return section.colorTag.color
    }

    // MARK: - Section divider banner

    private func sectionDividerBanner(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
    }

    // MARK: - Page navigation bar

    private func notebookPageBar(totalPages: Int) -> some View {
        HStack(spacing: 16) {
            // Previous page
            Button {
                slideDirection = .leading
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    flatPageIndex = max(0, flatPageIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .disabled(flatPageIndex <= 0)
            .accessibilityLabel("Previous page")

            Spacer()

            // Page info — section + absolute page number (tap to jump)
            Button {
                jumpPageText = "\(flatPageIndex + 1)"
                showJumpToPage = true
            } label: {
                VStack(spacing: 1) {
                    if let sName = currentPage?.sectionName {
                        Text(sName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("Page \(flatPageIndex + 1) of \(totalPages)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showJumpToPage) {
                jumpToPagePopover(totalPages: totalPages)
            }
            .accessibilityLabel("Page \(flatPageIndex + 1) of \(totalPages). Tap to jump to page.")

            Spacer()

            // Add page to the current note
            Button {
                if let ref = currentPage,
                   let newIdx = noteStore.addPage(to: ref.noteID) {
                    let updatedPages = allPages
                    if let newFlat = updatedPages.firstIndex(where: {
                        $0.noteID == ref.noteID && $0.pageIndex == newIdx
                    }) {
                        slideDirection = .trailing
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            flatPageIndex = newFlat
                        }
                    } else {
                        slideDirection = .trailing
                        flatPageIndex = min(flatPageIndex + 1, allPages.count - 1)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Add page")

            // Bookmark toggle for current page
            Button {
                if let ref = currentPage {
                    navigationStore.toggleBookmark(
                        notebookID: notebook.id,
                        noteID: ref.noteID,
                        pageIndex: ref.pageIndex
                    )
                }
            } label: {
                let isMarked = currentPage.map {
                    navigationStore.isBookmarked(
                        notebookID: notebook.id,
                        noteID: $0.noteID,
                        pageIndex: $0.pageIndex
                    )
                } ?? false
                Image(systemName: isMarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isMarked ? .red : .primary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Toggle bookmark")

            // Next page
            Button {
                slideDirection = .trailing
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    flatPageIndex = min(totalPages - 1, flatPageIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .disabled(flatPageIndex >= totalPages - 1)
            .accessibilityLabel("Next page")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.85))
    }

    // MARK: - Empty state

    private var emptyNotebookView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Empty Notebook")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Add a page to start writing in this notebook.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button {
                _ = noteStore.addNote(inNotebook: notebook.id)
                flatPageIndex = 0
            } label: {
                Label("Add First Page", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .disabled(notebook.isLocked)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Helpers

    private func blendedBackground(base: UIColor, tint: Color) -> UIColor {
        let isDark = effectiveDefinition.canvasIsDark
        let fraction: CGFloat = isDark ? 0.07 : 0.15
        let uiTint = UIColor(tint)
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        uiTint.getRed(&tr, green: &tg, blue: &tb, alpha: nil)
        return UIColor(
            red: br + (tr - br) * fraction,
            green: bg + (tg - bg) * fraction,
            blue: bb + (tb - bb) * fraction,
            alpha: ba
        )
    }

    // MARK: - Notebook cover page

    private var notebookCoverPageView: some View {
        GeometryReader { geo in
            ZStack {
                // Full background — custom photo or built-in gradient
                if let data = notebook.customCoverData, let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    notebook.cover.gradient
                }

                // Semi-transparent scrim so text is always readable
                LinearGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    Text(notebook.name.isEmpty ? "Untitled" : notebook.name)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                    if !notebook.description.isEmpty {
                        Text(notebook.description)
                            .font(.system(size: 17, weight: .light, design: .serif))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.top, 6)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(height: 0.5)
                        .padding(.vertical, 16)

                    let tocSections = noteStore.sections(inNotebook: notebook.id).filter { $0.kind == .section }
                    if !tocSections.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Contents")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .tracking(1.5)
                                .textCase(.uppercase)
                            ForEach(tocSections) { section in
                                HStack {
                                    Circle()
                                        .fill(section.colorTag.color)
                                        .frame(width: 7, height: 7)
                                        .accessibilityLabel("\(section.colorTag.rawValue) color indicator")
                                        .accessibilityHidden(section.colorTag == .none)
                                    Text(section.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.88))
                                    Spacer()
                                    Text(sectionPageRangeLabel(section))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                        .padding(.bottom, 12)
                    }

                    HStack(spacing: 20) {
                        coverStatItem(
                            icon: "doc.plaintext",
                            value: "\(allPages.count)",
                            label: "pages"
                        )
                        coverStatItem(
                            icon: "calendar",
                            value: notebook.createdAt.formatted(.dateTime.month(.abbreviated).day().year()),
                            label: "created"
                        )
                    }
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isShowingCoverPage = false
            }
        }
        .accessibilityHint("Double tap to dismiss cover page")
        .allowsHitTesting(true)
    }

    private func coverStatItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func sectionPageRangeLabel(_ section: NotebookSection) -> String {
        let pages = allPages.filter { $0.sectionID == section.id }
        guard !pages.isEmpty,
              let first = allPages.firstIndex(where: { $0.sectionID == section.id })
        else { return "—" }
        let last = first + pages.count - 1
        if first == last { return "p. \(first + 1)" }
        return "pp. \(first + 1)–\(last + 1)"
    }

    // MARK: - Jump to page popover

    private func jumpToPagePopover(totalPages: Int) -> some View {
        VStack(spacing: 12) {
            Text("Jump to Page")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("Page", text: $jumpPageText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
                    .submitLabel(.go)
                    .onSubmit { commitJump(totalPages: totalPages) }
                Text("of \(totalPages)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Go") {
                commitJump(totalPages: totalPages)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(minWidth: 200)
    }

    private func commitJump(totalPages: Int) {
        if let target = Int(jumpPageText), target >= 1 && target <= totalPages {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                flatPageIndex = target - 1
            }
        }
        showJumpToPage = false
    }

    // MARK: - Notebook page overview sheet

    private var notebookPageOverviewSheet: some View {
        NavigationStack {
            let pages = allPages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { idx, ref in
                            notebookPageThumbnail(ref: ref, flatIndex: idx)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    let idx = min(flatPageIndex, pages.count - 1)
                    if idx >= 0 && idx < pages.count {
                        proxy.scrollTo(pages[idx].id, anchor: .center)
                    }
                }
            }
            .navigationTitle("Pages (\(pages.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showPageOverview = false }
                }
            }
        }
    }

    @ViewBuilder
    private func notebookPageThumbnail(ref: PageRef, flatIndex: Int) -> some View {
        let isSelected = flatIndex == flatPageIndex
        let isMarked = navigationStore.isBookmarked(
            notebookID: notebook.id,
            noteID: ref.noteID,
            pageIndex: ref.pageIndex
        )
        Button {
            flatPageIndex = flatIndex
            showPageOverview = false
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(uiColor: canvasBackground(for: ref)))
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay(
                        pageTypeIndicator(for: ref)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isMarked {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .padding(4)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 2.5
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 2)

                Text("Page \(flatIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .id(ref.id)
        .accessibilityLabel("Page \(flatIndex + 1)\(isMarked ? ", bookmarked" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Simple visual indicator of the page ruling type inside a thumbnail.
    @ViewBuilder
    private func pageTypeIndicator(for ref: PageRef) -> some View {
        let ruling = effectivePageType(for: ref)
        switch ruling {
        case .ruled:
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 0.5)
                }
            }
            .padding(12)
        case .grid:
            Image(systemName: "grid")
                .font(.title3)
                .foregroundStyle(.secondary.opacity(0.3))
        case .dot:
            Image(systemName: "circle.grid.3x3")
                .font(.title3)
                .foregroundStyle(.secondary.opacity(0.3))
        case .cornell:
            Image(systemName: "rectangle.split.2x1")
                .font(.title3)
                .foregroundStyle(.secondary.opacity(0.3))
        case .hexagonal:
            Image(systemName: "hexagon")
                .font(.title3)
                .foregroundStyle(.secondary.opacity(0.3))
        case .music:
            Image(systemName: "music.note.list")
                .font(.title3)
                .foregroundStyle(.secondary.opacity(0.3))
        case .blank:
            EmptyView()
        }
    }
}
