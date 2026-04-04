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
    let notebook: Notebook

    @State private var flatPageIndex = 0
    @State private var showPageOverview = false
    /// Horizontal drag offset for the page-turn gesture.
    @State private var dragOffset: CGFloat = 0
    /// Direction of the last completed page turn for the slide transition.
    @State private var slideDirection: Edge = .trailing

    // MARK: - Linearised page model

    /// A reference to a single page inside the notebook's note hierarchy.
    private struct PageRef: Identifiable {
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
        currentNote?.themeOverride ?? notebook.defaultTheme ?? themeStore.selectedTheme
    }

    private var effectiveDefinition: ThemeDefinition {
        effectiveTheme.definition
    }

    private var effectivePaperMaterial: PaperMaterial {
        currentNote?.paperMaterial ?? notebook.paperMaterial
    }

    /// Per-page ruling: pageTypes[pageIndex] → note.pageType → notebook.pageType → .blank
    private func effectivePageType(for ref: PageRef) -> PageType {
        guard let note = noteStore.notes.first(where: { $0.id == ref.noteID }) else {
            return notebook.pageType
        }
        return note.pageType(forPage: ref.pageIndex) ?? note.pageType ?? notebook.pageType
    }

    /// Canvas background: per-page colour → theme + material blend.
    private func canvasBackground(for ref: PageRef) -> UIColor {
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

    // swiftlint:disable:next function_body_length
    var body: some View {
        let pages = allPages
        VStack(spacing: 0) {
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

                // Drawing toolbar
                DrawingToolbarView(toolStore: toolStore, inkStore: inkStore)

                // Page stack: stacked shadows behind current page for book depth
                ZStack {
                    // Background page shadows — fake "stacked pages" effect
                    pageStackShadows(pageCount: pages.count, currentIndex: safeIndex)

                    // Current page canvas
                    canvasForPage(ref, in: pages)
                        .offset(x: dragOffset)
                }
                .gesture(pageSwipeGesture(totalPages: pages.count))
                .clipped()

                // Page navigation bar
                notebookPageBar(totalPages: pages.count)
            }
        }
        .navigationTitle(notebook.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Canvas for a page

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
                pdfURL: noteStore.notePDFURL(for: note)
            )
            .id("\(ref.noteID)-\(ref.pageIndex)")
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

    // MARK: - Swipe gesture for page turns

    /// Horizontal drag that turns pages; swiping past the last page auto-creates a new one.
    private func pageSwipeGesture(totalPages: Int) -> some Gesture {
        DragGesture(minimumDistance: 40)
            .onChanged { value in
                // Only track horizontal drags that are clearly horizontal
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if horizontal > vertical * 1.2 {
                    dragOffset = value.translation.width * 0.3
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 60
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    dragOffset = 0
                    if value.translation.width < -threshold {
                        // Swipe left → next page (or create new)
                        turnPage(direction: 1, totalPages: totalPages)
                    } else if value.translation.width > threshold {
                        // Swipe right → previous page
                        turnPage(direction: -1, totalPages: totalPages)
                    }
                }
            }
    }

    /// Turns to the next or previous page. When swiping past the last page,
    /// auto-creates a new blank page so writing never stops.
    private func turnPage(direction: Int, totalPages: Int) {
        if direction > 0 {
            slideDirection = .trailing
            if flatPageIndex >= totalPages - 1 {
                // Swipe past last page → auto-create new page
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
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                flatPageIndex = tab.firstFlatIndex
                            }
                        } label: {
                            Text(tab.name)
                                .font(.subheadline.weight(isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    isActive
                                        ? Color.accentColor.opacity(0.12)
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

    // MARK: - Section divider banner

    private func sectionDividerBanner(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.accentColor)
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

            // Page info — section + absolute page number
            VStack(spacing: 1) {
                if let sName = currentPage?.sectionName {
                    Text(sName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.accentColor)
                }
                Text("Page \(flatPageIndex + 1) of \(totalPages)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

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
            red:   br + (tr - br) * fraction,
            green: bg + (tg - bg) * fraction,
            blue:  bb + (tb - bb) * fraction,
            alpha: ba
        )
    }
}
