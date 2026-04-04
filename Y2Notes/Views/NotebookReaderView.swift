import SwiftUI
import PencilKit

// MARK: - NotebookReaderView

/// Presents a ``Notebook`` as a continuous book: every page across every
/// section is linearised into a single flat index so the user can flip
/// through the entire notebook like a real physical book.
///
/// **Architecture**
/// Each note in the notebook contributes its `pages` array to the flat list.
/// The view tracks a single `flatPageIndex` that maps back to the originating
/// `(noteID, pageIndex)` so drawing changes are saved to the correct note.
///
/// **Section tabs** appear at the top of the view; tapping one jumps to
/// the first page of that section.  The bottom navigation bar shows the
/// current section name and absolute page number.
struct NotebookReaderView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var toolStore: DrawingToolStore
    @EnvironmentObject var inkStore: InkEffectStore
    let notebook: Notebook

    @State private var flatPageIndex = 0
    @State private var showPageOverview = false

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
        var prevSectionID: UUID?
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
            prevSectionID = section.id
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
    private var canvasBackgroundColor: UIColor {
        if let ref = currentPage,
           let note = noteStore.notes.first(where: { $0.id == ref.noteID }),
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
            // Section tabs
            if sectionTabs.count > 1 {
                sectionTabsBar
            }

            if let ref = currentPage,
               let note = noteStore.notes.first(where: { $0.id == ref.noteID }) {

                // Section divider label when crossing into a new section
                if ref.isFirstInSection, let name = ref.sectionName {
                    sectionDividerBanner(name)
                }

                // Drawing toolbar
                DrawingToolbarView(toolStore: toolStore, inkStore: inkStore)

                // Canvas
                let pageData = note.pages.indices.contains(ref.pageIndex)
                    ? note.pages[ref.pageIndex] : Data()
                CanvasView(
                    noteID: note.id,
                    drawingData: pageData,
                    backgroundColor: canvasBackgroundColor,
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
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if direction > 0 {
                                flatPageIndex = min(pages.count - 1, flatPageIndex + 1)
                            } else {
                                flatPageIndex = max(0, flatPageIndex - 1)
                            }
                        }
                    },
                    onPinchToOverview: { showPageOverview = true },
                    pdfURL: noteStore.notePDFURL(for: note)
                )
                .id("\(ref.noteID)-\(ref.pageIndex)")
                .transition(.opacity)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 1)
                .animation(.easeInOut(duration: 0.22), value: flatPageIndex)

                // Page navigation bar
                notebookPageBar(totalPages: pages.count)
            } else {
                emptyNotebookView
            }
        }
        .navigationTitle(notebook.name)
        .navigationBarTitleDisplayMode(.inline)
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
                            withAnimation(.easeInOut(duration: 0.25)) {
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
                withAnimation(.easeInOut(duration: 0.25)) {
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
                    // Jump to the newly added page
                    let pages = allPages
                    if let newFlat = pages.firstIndex(where: {
                        $0.noteID == ref.noteID && $0.pageIndex == newIdx
                    }) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            flatPageIndex = newFlat
                        }
                    } else {
                        // Fallback: jump forward by one
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
                withAnimation(.easeInOut(duration: 0.25)) {
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
                let note = noteStore.addNote(inNotebook: notebook.id)
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
