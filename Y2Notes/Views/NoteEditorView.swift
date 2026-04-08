import SwiftUI
import PencilKit
import PDFKit
import OSLog
import UniformTypeIdentifiers

// MARK: - Performance instrumentation

/// Human-readable editor lifecycle messages — visible in Console.app.
private let editorLogger = Logger(subsystem: "com.y2notes.app", category: "editor")

/// Instruments-visible signposts for canvas setup, drawing changes, and save flushes.
private let editorSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "editor.perf")

// MARK: - NoteEditorView

/// Full-screen note editor: editable title + drawing toolbar + PencilKit canvas.
struct NoteEditorView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var toolStore: DrawingToolStore
    @EnvironmentObject var inkStore: InkEffectStore
    @EnvironmentObject var documentStore: DocumentStore
    @EnvironmentObject var stickerStore: StickerStore
    @EnvironmentObject var pdfStore: PDFStore
    @Environment(\.undoManager) var undoManager
    @Environment(TabWorkspaceStore.self) var workspace
    let note: Note
    /// The tab ID for state sync. `nil` when opened as a standalone editor
    /// (e.g. from a widget or deep link) rather than inside the tab workspace.
    let tabID: UUID?

    @State var titleText: String
    @State var canUndo = false
    @State var canRedo = false
    /// Controls the transient "saved" checkmark badge (hidden 2 s after saved).
    @State var showSavedBadge = false
    /// Timestamp of the most recent "saved" event — used to debounce the auto-hide timer.
    @State private var badgeShownAt: Date?

    /// When true only Apple Pencil input draws; finger touches pan/zoom the canvas.
    /// When false any touch input draws. Persisted across sessions via AppStorage.
    @AppStorage("y2notes.pencilOnlyDrawing") var pencilOnlyDrawing = false

    /// Toggling this value signals the canvas to animate back to 1× zoom.
    @State var zoomResetTrigger = false

    /// Controls visibility of the right-side AdvancedToolsPanel inspector overlay.
    @State var showAdvancedPanel = false

    /// Whether the in-document find bar is visible.
    @State var showFindBar = false
    /// Current query in the in-document find bar.
    @State var findQuery = ""
    /// Matches in the note's typedText produced by the current query.
    @State var findMatches: [InDocumentMatch] = []
    /// Index of the currently highlighted find match.
    @State var findMatchIndex: Int = 0

    /// Whether the editor is in keyboard text-entry mode (true) or drawing mode (false).
    @State var isTextMode = false
    /// Live content of the typed-text layer. Seeded from `note.typedText` on init.
    @State var typedTextContent: String
    /// Debounce timer for persisting text changes — mirrors the 0.8 s drawing debounce.
    @State var textSaveTimer: Timer?

    /// Whether the "Create Flashcard" sheet is visible.
    @State var showCreateFlashcard = false

    /// Whether the page overview grid is visible (triggered by pinch-to-overview gesture).
    @State var showPageOverview = false

    /// Whether the system share sheet is presented for an exported file or image.
    @State var showShareSheet = false
    /// Items forwarded to `UIActivityViewController` when `showShareSheet` is true.
    @State var shareItems: [Any] = []
    /// True while an export render is in progress — disables the export button.
    @State var isExporting = false

    /// Whether the document import picker is visible.
    @State var showDocumentImporter = false

    /// Whether the version history sheet is visible.
    @State var showVersionHistory = false
    @State var showUnlinkConfirm = false

    /// Zero-based index of the currently displayed page.
    @State var currentPageIndex = 0

    /// Set to `true` immediately before navigating to a freshly created page
    /// so the canvas plays its paper-settle reveal animation.  Reset shortly
    /// after to avoid replaying the animation on subsequent re-renders.
    @State var isNewPageJustAdded = false

    /// Widget being edited in the inline editor sheet.
    @State var widgetToEdit: NoteWidget?

    let searchService = SearchService()

    /// Delay (seconds) before resetting `isNewPageJustAdded` after a page is created.
    /// Set to 0.55 s — 2.2× the carousel navigation animation duration (0.25 s) —
    /// to guarantee the new canvas is fully visible and its PKCanvasView has completed
    /// its initial layout before the flag clears. A smaller margin (e.g. 1.1×) risks
    /// the flag resetting mid-animation, which could suppress the new-page reveal effect.
    static let newPageFlagResetDelay: TimeInterval = 0.55

    init(note: Note, tab: TabSession? = nil) {
        self.note = note
        self.tabID = tab?.id
        _titleText = State(initialValue: note.title)
        _typedTextContent = State(initialValue: note.typedText)
        _currentPageIndex = State(initialValue: tab?.pageIndex ?? 0)
        _showAdvancedPanel = State(initialValue: tab?.showAdvancedPanel ?? false)
    }

    // MARK: - Notebook context

    /// The notebook this note belongs to (nil for unfiled notes).
    var notebook: Notebook? {
        guard let id = note.notebookID else { return nil }
        return noteStore.notebooks.first { $0.id == id }
    }

    /// Note-level page ruling fallback: note.pageType → notebook.pageType → .blank.
    /// This is the default when no per-page override exists.
    /// Use `effectivePageType(forPage:)` for per-page resolution.
    var effectivePageType: PageType {
        note.pageType ?? notebook?.pageType ?? .blank
    }

    /// Per-page ruling style for a given page index.
    /// Cascade: pageTypes[index] → note.pageType → notebook.pageType → .blank
    func effectivePageType(forPage index: Int) -> PageType {
        note.pageType(forPage: index) ?? notebook?.pageType ?? .blank
    }

    /// Paper material: note-level override → notebook setting → `.standard` fallback.
    var effectivePaperMaterial: PaperMaterial {
        note.paperMaterial ?? notebook?.paperMaterial ?? .standard
    }

    // MARK: - Effective theme

    var effectiveTheme: AppTheme {
        note.themeOverride ?? themeStore.effectiveTheme
    }

    var effectiveDefinition: ThemeDefinition {
        effectiveTheme.definition
    }

    /// Canvas background: per-page colour → theme base blended with paper material tint.
    var canvasBackgroundColor: UIColor {
        // Per-page colour takes absolute precedence when set.
        if let explicit = note.pageColor(forPage: safePageIndex) {
            return explicit
        }
        return blendedBackground(
            base: effectiveDefinition.canvasBackground,
            tint: effectivePaperMaterial.pageTint
        )
    }

    /// Clamped page index that never exceeds valid bounds.
    var safePageIndex: Int {
        min(currentPageIndex, max(0, note.pages.count - 1))
    }

    var body: some View {
        editorWithLifecycle
    }

    /// Animations and navigation chrome — kept short to help the Swift type-checker.
    private var editorWithChrome: some View {
        editorZStack
            .animation(.easeInOut(duration: 0.35), value: toolStore.isFocusModeActive)
            .animation(.easeInOut(duration: 0.45), value: toolStore.activeAmbientScene)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showAdvancedPanel)
            .navigationBarTitleDisplayMode(.inline)
            .animation(.spring(duration: 0.25), value: showFindBar)
            .animation(.spring(duration: 0.25), value: isTextMode)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    saveStateIndicator
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    trailingToolbarContent
                }
            }
    }

    /// Sheets and document importer — separated to reduce type-checker load.
    private var editorWithPresentations: some View {
        editorWithChrome
            .sheet(isPresented: $showCreateFlashcard) {
                NoteFlashcardSheet(note: note)
            }
            .sheet(isPresented: $showVersionHistory) {
                VersionHistoryView(noteID: note.id)
                    .environmentObject(noteStore)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPageOverview) {
                PageOverviewGrid(
                    note: note,
                    currentPageIndex: $currentPageIndex,
                    canvasBackground: canvasBackgroundColor,
                    onDismiss: { showPageOverview = false }
                )
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: shareItems)
            }
            .sheet(isPresented: $toolStore.isStickerLibraryPresented) {
                StickerLibraryView(stickerStore: stickerStore) { asset in
                    placeSticker(asset)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $toolStore.isWidgetPickerPresented) {
                WidgetPickerView { kind in
                    placeWidget(kind)
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $widgetToEdit) { widget in
                WidgetEditorView(widget: widget) { updated in
                    let pageIdx = currentPageIndex
                    var widgets = note.widgets(forPage: pageIdx)
                    if let idx = widgets.firstIndex(where: { $0.id == updated.id }) {
                        widgets[idx] = updated
                        noteStore.updateWidgets(for: note.id, pageIndex: pageIdx, widgets: widgets)
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .fileImporter(
                isPresented: $showDocumentImporter,
                allowedContentTypes: ImportedDocumentType.allUTTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    documentStore.importDocuments(from: urls)
                }
            }
    }

    /// Lifecycle modifiers — separated to keep each modifier chain short.
    private var editorWithLifecycle: some View {
        editorWithPresentations
            .onAppear {
                refreshUndoRedoState()
                toolStore.currentPaperMaterial = effectivePaperMaterial
            }
            .onDisappear {
                toolStore.currentPaperMaterial = .standard
            }
            // Sync tab navigation state and handle carousel swiping to the "add page" slot.
            .onChange(of: currentPageIndex) { _, newIndex in
                if newIndex >= note.pageCount {
                    if let newIdx = noteStore.addPage(to: note.id) {
                        currentPageIndex = newIdx
                        isNewPageJustAdded = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.newPageFlagResetDelay) {
                            isNewPageJustAdded = false
                        }
                    } else {
                        currentPageIndex = max(0, note.pageCount - 1)
                    }
                }
                if let id = tabID {
                    workspace.updateTabState(id, pageIndex: newIndex)
                }
            }
            .onChange(of: showAdvancedPanel) { _, isOpen in
                if let id = tabID {
                    workspace.updateTabState(id, showAdvancedPanel: isOpen)
                }
            }
            .onChange(of: toolStore.isFocusModeActive) { _, isActive in
                // Toolbar opacity is driven directly by the SwiftUI toolbarOpacity
                // binding.  The paper glow (CALayer) is handled here via the
                // Coordinator's FocusModeEngine.
                if isActive {
                    toolStore.toolbarOpacity = 0.35
                } else {
                    toolStore.toolbarOpacity = 1.0
                }
            }
            .onChange(of: toolStore.activeAmbientScene) { _, scene in
                // Ambient environment scenes are driven via the Coordinator's
                // AmbientEnvironmentEngine — all effects are GPU-composited
                // CALayers added to the editor container layer.
                //
                // When an ambient scene becomes active, focus mode is
                // deactivated (they share toolbar dimming).
                if scene != nil {
                    if toolStore.isFocusModeActive {
                        toolStore.isFocusModeActive = false
                    }
                }
            }
            // Notification-based fallback to keep undo/redo state in sync even when the
            // canvas delegate fires before the onUndoStateChanged callback is invoked.
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in
                refreshUndoRedoState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in
                refreshUndoRedoState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in
                refreshUndoRedoState()
            }
            .onReceive(noteStore.$saveState) { state in
                if state == .saved {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showSavedBadge = true
                    }
                    let now = Date()
                    badgeShownAt = now
                    // Each rapid save updates `badgeShownAt`; only the last scheduled
                    // callback will actually hide the badge, avoiding premature dismissal.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if badgeShownAt == now {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showSavedBadge = false
                            }
                        }
                    }
                }
            }
            .onDisappear {
                flushTextNow()
                toolStore.currentPaperMaterial = .standard
                // Persist tab state when leaving this editor tab.
                if let id = tabID {
                    workspace.updateTabState(id, pageIndex: currentPageIndex, showAdvancedPanel: showAdvancedPanel)
                }
                // Reset focus mode on editor tear-down so state doesn't leak.
                if toolStore.isFocusModeActive {
                    toolStore.isFocusModeActive = false
                    toolStore.toolbarOpacity = 1.0
                }
                // Reset ambient scene.
                if toolStore.activeAmbientScene != nil {
                    toolStore.activeAmbientScene = nil
                    toolStore.toolbarOpacity = 1.0
                }
                noteStore.save()
            }
    }

    // MARK: - Body sub-views (extracted to help Swift type-checker)

    /// Top-level ZStack that composes the editor content layers.
    private var editorZStack: some View {
        ZStack(alignment: .topTrailing) {
            mainContentStack
            floatingToolbarOverlay
            selectionActionBars
            advancedPanelOverlay
            effectOverlays
        }
    }

    /// Primary VStack: title, linked-import banner, contrast banner, find bar, canvas or text layer, page bar.
    private var mainContentStack: some View {
        VStack(spacing: 0) {
            titleField
            if note.linkedPDFID != nil || note.linkedDocumentID != nil {
                linkedImportBanner
            }
            if effectiveDefinition.canvasIsDark && !isTextMode {
                contrastBanner
            }
            Divider()
            if showFindBar {
                findBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if isTextMode {
                textLayer
            } else {
                notebookCanvasSection
                pageNavigationBar
            }
        }
    }
}
