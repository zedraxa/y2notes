// swiftlint:disable file_length
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
    @Environment(\.undoManager) private var undoManager
    @Environment(TabWorkspaceStore.self) private var workspace
    let note: Note
    /// The tab ID for state sync. `nil` when opened as a standalone editor
    /// (e.g. from a widget or deep link) rather than inside the tab workspace.
    let tabID: UUID?

    @State private var titleText: String
    @State private var canUndo = false
    @State private var canRedo = false
    /// Controls the transient "saved" checkmark badge (hidden 2 s after saved).
    @State private var showSavedBadge = false
    /// Timestamp of the most recent "saved" event — used to debounce the auto-hide timer.
    @State private var badgeShownAt: Date?

    /// When true only Apple Pencil input draws; finger touches pan/zoom the canvas.
    /// When false any touch input draws. Persisted across sessions via AppStorage.
    @AppStorage("y2notes.pencilOnlyDrawing") private var pencilOnlyDrawing = false

    /// Toggling this value signals the canvas to animate back to 1× zoom.
    @State private var zoomResetTrigger = false

    /// Controls visibility of the right-side AdvancedToolsPanel inspector overlay.
    @State private var showAdvancedPanel = false

    /// Whether the in-document find bar is visible.
    @State private var showFindBar = false
    /// Current query in the in-document find bar.
    @State private var findQuery = ""
    /// Matches in the note's typedText produced by the current query.
    @State private var findMatches: [InDocumentMatch] = []
    /// Index of the currently highlighted find match.
    @State private var findMatchIndex: Int = 0

    /// Whether the editor is in keyboard text-entry mode (true) or drawing mode (false).
    @State private var isTextMode = false
    /// Live content of the typed-text layer. Seeded from `note.typedText` on init.
    @State private var typedTextContent: String
    /// Debounce timer for persisting text changes — mirrors the 0.8 s drawing debounce.
    @State private var textSaveTimer: Timer?

    /// Whether the "Create Flashcard" sheet is visible.
    @State private var showCreateFlashcard = false

    /// Whether the page overview grid is visible (triggered by pinch-to-overview gesture).
    @State private var showPageOverview = false

    /// Whether the system share sheet is presented for an exported file or image.
    @State private var showShareSheet = false
    /// Items forwarded to `UIActivityViewController` when `showShareSheet` is true.
    @State private var shareItems: [Any] = []
    /// True while an export render is in progress — disables the export button.
    @State private var isExporting = false

    /// Whether the document import picker is visible.
    @State private var showDocumentImporter = false

    /// Whether the version history sheet is visible.
    @State private var showVersionHistory = false
    @State private var showUnlinkConfirm = false

    /// Zero-based index of the currently displayed page.
    @State private var currentPageIndex = 0

    /// Set to `true` immediately before navigating to a freshly created page
    /// so the canvas plays its paper-settle reveal animation.  Reset shortly
    /// after to avoid replaying the animation on subsequent re-renders.
    @State private var isNewPageJustAdded = false

    /// Widget being edited in the inline editor sheet.
    @State private var widgetToEdit: NoteWidget?

    private let searchService = SearchService()

    /// Delay (seconds) before resetting `isNewPageJustAdded` after a page is created.
    /// Set to 0.55 s — 2.2× the carousel navigation animation duration (0.25 s) —
    /// to guarantee the new canvas is fully visible and its PKCanvasView has completed
    /// its initial layout before the flag clears. A smaller margin (e.g. 1.1×) risks
    /// the flag resetting mid-animation, which could suppress the new-page reveal effect.
    private static let newPageFlagResetDelay: TimeInterval = 0.55

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
    private var notebook: Notebook? {
        guard let id = note.notebookID else { return nil }
        return noteStore.notebooks.first { $0.id == id }
    }

    /// Note-level page ruling fallback: note.pageType → notebook.pageType → .blank.
    /// This is the default when no per-page override exists.
    /// Use `effectivePageType(forPage:)` for per-page resolution.
    private var effectivePageType: PageType {
        note.pageType ?? notebook?.pageType ?? .blank
    }

    /// Per-page ruling style for a given page index.
    /// Cascade: pageTypes[index] → note.pageType → notebook.pageType → .blank
    private func effectivePageType(forPage index: Int) -> PageType {
        note.pageType(forPage: index) ?? notebook?.pageType ?? .blank
    }

    /// Paper material: note-level override → notebook setting → `.standard` fallback.
    private var effectivePaperMaterial: PaperMaterial {
        note.paperMaterial ?? notebook?.paperMaterial ?? .standard
    }

    // MARK: - Effective theme

    private var effectiveTheme: AppTheme {
        note.themeOverride ?? themeStore.effectiveTheme
    }

    private var effectiveDefinition: ThemeDefinition {
        effectiveTheme.definition
    }

    /// Canvas background: per-page colour → theme base blended with paper material tint.
    private var canvasBackgroundColor: UIColor {
        // Per-page colour takes absolute precedence when set.
        let safeIdx = min(currentPageIndex, max(0, note.pages.count - 1))
        if let explicit = note.pageColor(forPage: safeIdx) {
            return explicit
        }
        return blendedBackground(
            base: effectiveDefinition.canvasBackground,
            tint: effectivePaperMaterial.pageTint
        )
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
                canvasSection
                pageNavigationBar
            }
        }
    }

    /// SwiftUI-native page carousel — each page is a persistent CanvasPageView.
    @ViewBuilder
    private var canvasSection: some View {
        NotePageCarouselView(
            note: note,
            currentPageIndex: $currentPageIndex,
            noteID: note.id,
            backgroundColor: canvasBackgroundColor,
            defaultInkColor: effectiveDefinition.contrastingInkColor,
            currentTool: toolStore.pkTool,
            isShapeToolActive: toolStore.activeTool == .shape,
            activeShapeType: toolStore.activeShapeType,
            shapeColor: toolStore.activeColor,
            shapeWidth: toolStore.activeWidth,
            drawingPolicy: pencilOnlyDrawing ? .pencilOnly : .anyInput,
            zoomResetTrigger: zoomResetTrigger,
            pageTypeForIndex: { idx in effectivePageType(forPage: idx) },
            paperMaterial: effectivePaperMaterial,
            activeFX: inkStore.resolvedFX,
            fxColor: toolStore.activeColor,
            onDrawingChanged: { data, idx in
                noteStore.updateDrawing(for: note.id, pageIndex: idx, data: data)
            },
            onSaveRequested: { noteStore.save() },
            onUndoStateChanged: { canUndoVal, canRedoVal in
                canUndo = canUndoVal
                canRedo = canRedoVal
            },
            onPinchToOverview: { showPageOverview = true },
            pdfURL: noteStore.notePDFURL(for: note),
            toolStoreForFade: toolStore,
            onShapesChanged: { shapes, idx in
                noteStore.updateShapes(for: note.id, pageIndex: idx, shapes: shapes)
            },
            onAttachmentsChanged: { atts, idx in
                noteStore.updateAttachments(for: note.id, pageIndex: idx, attachments: atts)
            },
            onAttachmentSelectionChanged: { attachmentID in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    toolStore.activeAttachmentSelection = attachmentID
                    if attachmentID != nil {
                        toolStore.activeShapeSelection = nil
                        toolStore.activeStickerSelection = nil
                        toolStore.activeWidgetSelection = nil
                        toolStore.activeTextObjectSelection = nil
                        toolStore.hasActiveSelection = false
                    }
                }
            },
            onWidgetsChanged: { widgets, idx in
                noteStore.updateWidgets(for: note.id, pageIndex: idx, widgets: widgets)
            },
            onWidgetSelectionChanged: { widgetID in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    toolStore.activeWidgetSelection = widgetID
                    if widgetID != nil {
                        toolStore.activeShapeSelection = nil
                        toolStore.activeStickerSelection = nil
                        toolStore.activeAttachmentSelection = nil
                        toolStore.activeTextObjectSelection = nil
                        toolStore.hasActiveSelection = false
                    }
                }
            },
            isTextToolActive: toolStore.activeTool == .text,
            onTextObjectsChanged: { objs, idx in
                noteStore.updateTextObjects(for: note.id, pageIndex: idx, textObjects: objs)
            },
            onTextObjectSelectionChanged: { textObjectID in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    toolStore.activeTextObjectSelection = textObjectID
                    if textObjectID != nil {
                        toolStore.activeShapeSelection = nil
                        toolStore.activeStickerSelection = nil
                        toolStore.activeAttachmentSelection = nil
                        toolStore.activeWidgetSelection = nil
                        toolStore.hasActiveSelection = false
                    }
                }
            },
            onPlaceTextObject: { point in placeTextObject(at: point) },
            isMagicModeActive: toolStore.isMagicModeActive,
            isStudyModeActive: toolStore.isStudyModeActive,
            activeAmbientScene: toolStore.activeAmbientScene,
            isAmbientSoundEnabled: toolStore.isAmbientSoundEnabled,
            isNewPage: isNewPageJustAdded
        )
    }

    /// Floating toolbar capsule — bottom-center, above page navigation bar.
    @ViewBuilder
    private var floatingToolbarOverlay: some View {
        if !isTextMode {
            VStack {
                Spacer()
                FloatingToolbarCapsule(
                    toolStore: toolStore,
                    inkStore: inkStore,
                    stickerStore: stickerStore,
                    canUndo: canUndo,
                    canRedo: canRedo,
                    onUndo: { undoManager?.undo() },
                    onRedo: { undoManager?.redo() },
                    onOpenInspector: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showAdvancedPanel.toggle()
                        }
                    },
                    onSelectionAction: { action in
                        handleSelectionAction(action)
                    }
                )
                .opacity(toolStore.toolbarOpacity)
                .animation(.easeInOut(duration: 0.3), value: toolStore.toolbarOpacity)
                .allowsHitTesting(toolStore.toolbarOpacity > 0.5)
                .padding(.bottom, 8)
            }
            .zIndex(0.5)
        }
    }

    /// Shape / attachment / widget action bars — appear when an object is selected.
    @ViewBuilder
    private var selectionActionBars: some View {
        // Shape action bar
        if toolStore.hasActiveShapeSelection,
           let selectedID = toolStore.activeShapeSelection,
           let selectedShape = note.shapes(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                ShapeHandlesView(
                    toolStore: toolStore,
                    selectedShape: selectedShape,
                    onAction: { action in
                        handleShapeAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.6)
        }

        // Attachment action bar
        if toolStore.hasActiveAttachmentSelection,
           let selectedID = toolStore.activeAttachmentSelection,
           let selectedAttachment = note.attachments(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                AttachmentHandlesView(
                    attachment: selectedAttachment,
                    onAction: { action in
                        handleAttachmentAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.7)
        }

        // Widget action bar
        if toolStore.hasActiveWidgetSelection,
           let selectedID = toolStore.activeWidgetSelection,
           let selectedWidget = note.widgets(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                WidgetHandlesView(
                    widget: selectedWidget,
                    onAction: { action in
                        handleWidgetAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.75)
        }

        // Text object action bar
        if toolStore.hasActiveTextObjectSelection,
           let selectedID = toolStore.activeTextObjectSelection,
           let selectedTextObject = note.textObjects(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                TextObjectHandlesView(
                    textObject: selectedTextObject,
                    onAction: { action in
                        handleTextObjectAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.8)
        }
    }

    /// Advanced tools inspector — slides in from the right.
    @ViewBuilder
    private var advancedPanelOverlay: some View {
        if showAdvancedPanel {
            AdvancedToolsPanel(toolStore: toolStore, isPresented: $showAdvancedPanel)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(1)
        }
    }

    /// Focus-mode and ambient scene overlays.
    @ViewBuilder
    private var effectOverlays: some View {
        // Focus-mode ambient overlays — vignette + dim.
        if toolStore.isFocusModeActive {
            focusModeOverlay
                .zIndex(0.4)
                .allowsHitTesting(false)
                .transition(.opacity)
        }

        // Ambient environment scene indicator.
        if toolStore.activeAmbientScene != nil {
            ambientSceneOverlay
                .zIndex(0.35)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Trailing navigation bar toolbar items.
    @ViewBuilder
    private var trailingToolbarContent: some View {
        noteThemeMenu

        // Page setup menu — GoodNotes-style per-page paper type & material picker.
        pageSetupMenu

        // Create flashcard from this note.
        Button {
            showCreateFlashcard = true
        } label: {
            Image(systemName: "rectangle.on.rectangle.angled")
        }
        .accessibilityLabel("Create Flashcard")

        // Export menu — PDF (single page), PDF (all pages), PNG image.
        exportMenu

        // Version history browser.
        Button {
            showVersionHistory = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("Version History")

        // Import document into the library.
        Button {
            showDocumentImporter = true
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .accessibilityLabel("Import document")

        // Open the PDF or document that this note was created for, if any.
        if note.linkedPDFID != nil || note.linkedDocumentID != nil {
            Button {
                openLinkedImport()
            } label: {
                Image(systemName: "doc.viewfinder")
            }
            .accessibilityLabel("Open linked document")
        }

        // Draw ↔ Type mode toggle.
        // "keyboard" switches to text mode; "pencil" returns to drawing mode.
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            flushTextNow()
            isTextMode.toggle()
        } label: {
            Image(systemName: isTextMode ? "pencil" : "keyboard")
        }
        .accessibilityLabel(isTextMode ? "Switch to drawing mode" : "Switch to text mode")

        // In-document find bar toggle.
        Button {
            showFindBar.toggle()
            if !showFindBar {
                findQuery = ""
                findMatches = []
            }
        } label: {
            Image(systemName: showFindBar ? "magnifyingglass.circle.fill" : "magnifyingglass")
        }
        .accessibilityLabel(showFindBar ? "Hide find bar" : "Find in note")

        if !isTextMode {
            // Finger / Pencil drawing policy toggle.
            Button {
                pencilOnlyDrawing.toggle()
            } label: {
                Image(systemName: pencilOnlyDrawing ? "pencil.tip" : "hand.and.pencil")
            }
            .accessibilityLabel(
                pencilOnlyDrawing ? "Enable finger drawing" : "Enable Pencil-only drawing"
            )

            // Zoom reset — animates the canvas back to 1× scale.
            Button {
                zoomResetTrigger.toggle()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Fit page to screen")

            Button {
                undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button {
                undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .accessibilityLabel("Redo")
        }
    }

    // MARK: - Sticker Placement

    /// Places a sticker asset at the center of the current page.
    private func placeSticker(_ asset: StickerAsset) {
        guard var updatedNote = noteStore.notes.first(where: { $0.id == note.id }) else { return }
        let pageIdx = currentPageIndex

        // Ensure stickerLayers array is sized to match pages
        while updatedNote.stickerLayers.count < updatedNote.pages.count {
            updatedNote.stickerLayers.append(nil)
        }

        var existing = updatedNote.stickerLayers[pageIdx] ?? []

        // Enforce per-page limit
        guard existing.count < StickerConstants.maxStickersPerPage else { return }

        let maxZ = existing.map(\.zIndex).max() ?? 0

        // Place at approximate center of page
        let pageSize = CanvasView.pageSize
        let center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)

        let instance = StickerInstance(
            stickerID: asset.id,
            position: center,
            scale: 1.0,
            rotation: 0,
            opacity: 1.0,
            zIndex: maxZ + 1,
            isLocked: false
        )

        existing.append(instance)
        updatedNote.stickerLayers[pageIdx] = existing
        updatedNote.modifiedAt = Date()

        noteStore.updateStickers(for: note.id, pageIndex: pageIdx, stickers: existing)
    }

    // MARK: - Widget Placement

    /// Places a new widget of the given kind at the centre of the current page.
    private func placeWidget(_ kind: WidgetKind) {
        let pageIdx = currentPageIndex
        var widgets = note.widgets(forPage: pageIdx)

        // Enforce per-page limit
        guard widgets.count < WidgetConstants.maxWidgetsPerPage else { return }

        let maxZ = widgets.map(\.zIndex).max() ?? 0

        // Place at approximate centre of page
        let pageSize = CanvasView.pageSize
        let center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)

        var widget: NoteWidget
        switch kind {
        case .checklist:
            widget = NoteWidget.makeChecklist(at: center)
        case .quickTable:
            widget = NoteWidget.makeQuickTable(at: center)
        case .calloutBox:
            widget = NoteWidget.makeCalloutBox(at: center)
        case .referenceCard:
            widget = NoteWidget.makeReferenceCard(at: center)
        case .stickyNote:
            widget = NoteWidget.makeStickyNote(at: center)
        case .flashcard:
            widget = NoteWidget.makeFlashcard(at: center)
        case .progressTracker:
            widget = NoteWidget.makeProgressTracker(at: center)
        }
        widget.zIndex = maxZ + 1

        widgets.append(widget)
        noteStore.updateWidgets(for: note.id, pageIndex: pageIdx, widgets: widgets)

        // Auto-select the newly placed widget
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            toolStore.activeWidgetSelection = widget.id
            toolStore.activeShapeSelection = nil
            toolStore.activeStickerSelection = nil
            toolStore.activeAttachmentSelection = nil
            toolStore.activeTextObjectSelection = nil
            toolStore.hasActiveSelection = false
        }
    }

    // MARK: - Text Object Placement

    /// Places a new empty text box anchored at the given page-coordinate point.
    private func placeTextObject(at tapPoint: CGPoint) {
        let pageIdx = currentPageIndex
        var objects = note.textObjects(forPage: pageIdx)

        // Enforce per-page limit
        guard objects.count < TextObjectConstants.maxTextObjectsPerPage else { return }

        let maxZ = objects.map(\.zIndex).max() ?? 0
        let size = TextObjectConstants.defaultSize
        // Centre the box on the tap point
        let origin = CGPoint(x: tapPoint.x - size.width / 2, y: tapPoint.y - size.height / 2)
        let frame = CGRect(origin: origin, size: size)

        let obj = TextObject(
            frame: frame,
            fontSize: toolStore.activeTextFontSize,
            fontFamily: toolStore.activeTextFontFamily,
            isBold: toolStore.activeTextBold,
            textColor: .label,
            alignment: toolStore.activeTextAlignment,
            zIndex: maxZ + 1
        )

        objects.append(obj)
        noteStore.updateTextObjects(for: note.id, pageIndex: pageIdx, textObjects: objects)

        // Auto-select so the user can immediately start editing
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            toolStore.activeTextObjectSelection = obj.id
            toolStore.activeShapeSelection = nil
            toolStore.activeStickerSelection = nil
            toolStore.activeAttachmentSelection = nil
            toolStore.activeWidgetSelection = nil
            toolStore.hasActiveSelection = false
        }
    }

    // MARK: - Shape Actions

    /// Handles actions from the shape action bar.
    private func handleShapeAction(_ action: ShapeAction, for shapeID: UUID) {
        let pageIdx = currentPageIndex
        var shapes = note.shapes(forPage: pageIdx)
        guard let idx = shapes.firstIndex(where: { $0.id == shapeID }) else { return }

        switch action {
        case .duplicate:
            var copy = shapes[idx]
            copy = ShapeInstance(
                shapeType: copy.shapeType,
                frame: copy.frame.offsetBy(dx: 20, dy: 20),
                rotation: copy.rotation,
                style: copy.style,
                zIndex: (shapes.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false
            )
            shapes.append(copy)
            toolStore.activeShapeSelection = copy.id

        case .delete:
            shapes.remove(at: idx)
            toolStore.activeShapeSelection = nil

        case .toggleLock:
            shapes[idx].isLocked.toggle()

        case .bringToFront:
            let maxZ = shapes.map(\.zIndex).max() ?? 0
            shapes[idx].zIndex = maxZ + 1

        case .sendToBack:
            let minZ = shapes.map(\.zIndex).min() ?? 0
            shapes[idx].zIndex = minZ - 1

        case .updateStyle(let newStyle):
            shapes[idx].style = newStyle
        }

        noteStore.updateShapes(for: note.id, pageIndex: pageIdx, shapes: shapes)
    }

    private func handleAttachmentAction(_ action: AttachmentAction, for attachmentID: UUID) {
        let pageIdx = currentPageIndex
        var attachments = note.attachments(forPage: pageIdx)
        guard let idx = attachments.firstIndex(where: { $0.id == attachmentID }) else { return }

        switch action {
        case .expand:
            // Handled by presenting AttachmentViewerView — signal via state
            break

        case .duplicate:
            var copy = attachments[idx]
            copy = AttachmentObject(
                type: copy.type,
                frame: AttachmentFrame(
                    position: CGPoint(
                        x: copy.frame.position.x + AttachmentConstants.duplicateOffset,
                        y: copy.frame.position.y + AttachmentConstants.duplicateOffset
                    ),
                    size: copy.frame.size
                ),
                label: copy.label,
                zIndex: (attachments.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false,
                aspectRatio: copy.aspectRatio,
                fileExtension: copy.fileExtension,
                linkURL: copy.linkURL
            )
            attachments.append(copy)
            toolStore.activeAttachmentSelection = copy.id

        case .toggleLock:
            attachments[idx].isLocked.toggle()

        case .delete:
            let removed = attachments.remove(at: idx)
            toolStore.activeAttachmentSelection = nil
            AttachmentStore.shared.deleteAttachmentFiles(
                noteID: note.id,
                attachmentID: removed.id,
                ext: removed.fileExtension
            )
        }

        noteStore.updateAttachments(for: note.id, pageIndex: pageIdx, attachments: attachments)
    }

    private func handleWidgetAction(_ action: WidgetAction, for widgetID: UUID) {
        let pageIdx = currentPageIndex
        var widgets = note.widgets(forPage: pageIdx)
        guard let idx = widgets.firstIndex(where: { $0.id == widgetID }) else { return }

        switch action {
        case .edit:
            widgetToEdit = widgets[idx]

        case .duplicate:
            let source = widgets[idx]
            let copy = NoteWidget(
                kind: source.kind,
                frame: WidgetFrame(
                    position: CGPoint(
                        x: source.frame.position.x + WidgetConstants.duplicateOffset,
                        y: source.frame.position.y + WidgetConstants.duplicateOffset
                    ),
                    size: source.frame.size
                ),
                payload: source.payload,
                zIndex: (widgets.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false,
                borderColorComponents: source.borderColorComponents
            )
            widgets.append(copy)
            toolStore.activeWidgetSelection = copy.id

        case .toggleLock:
            widgets[idx].isLocked.toggle()

        case .bringForward:
            let maxZ = widgets.map(\.zIndex).max() ?? 0
            if widgets[idx].zIndex < maxZ {
                widgets[idx].zIndex += 1
            }

        case .sendBack:
            let minZ = widgets.map(\.zIndex).min() ?? 0
            if widgets[idx].zIndex > minZ {
                widgets[idx].zIndex -= 1
            }

        case .delete:
            widgets.remove(at: idx)
            toolStore.activeWidgetSelection = nil
        }

        noteStore.updateWidgets(for: note.id, pageIndex: pageIdx, widgets: widgets)
    }

    /// Handles actions from the text object action bar.
    private func handleTextObjectAction(_ action: TextObjectAction, for textObjectID: UUID) {
        let pageIdx = currentPageIndex
        var textObjects = note.textObjects(forPage: pageIdx)
        guard let idx = textObjects.firstIndex(where: { $0.id == textObjectID }) else { return }

        switch action {
        case .duplicate:
            let source = textObjects[idx]
            let copy = TextObject(
                content: source.content,
                frame: source.frame.offsetBy(dx: 20, dy: 20),
                fontSize: source.fontSize,
                fontFamily: source.fontFamily,
                isBold: source.isBold,
                textColor: source.textColor,
                backgroundColor: source.backgroundColor,
                alignment: source.textAlignment,
                rotation: source.rotation,
                opacity: source.opacity,
                zIndex: (textObjects.map(\.zIndex).max() ?? 0) + 1,
                isLocked: false,
                borderRadius: source.borderRadius,
                borderColor: source.borderColor,
                borderWidth: source.borderWidth
            )
            textObjects.append(copy)
            toolStore.activeTextObjectSelection = copy.id

        case .delete:
            textObjects.remove(at: idx)
            toolStore.activeTextObjectSelection = nil

        case .toggleLock:
            textObjects[idx].isLocked.toggle()

        case .bringToFront:
            let maxZ = textObjects.map(\.zIndex).max() ?? 0
            textObjects[idx].zIndex = maxZ + 1

        case .sendToBack:
            let minZ = textObjects.map(\.zIndex).min() ?? 0
            textObjects[idx].zIndex = minZ - 1

        case .updateFontSize(let size):
            textObjects[idx].fontSize = size

        case .updateFontFamily(let family):
            textObjects[idx].fontFamily = family

        case .toggleBold:
            textObjects[idx].isBold.toggle()

        case .updateAlignment(let alignment):
            switch alignment {
            case .center: textObjects[idx].alignmentRaw = 1
            case .right:  textObjects[idx].alignmentRaw = 2
            default:      textObjects[idx].alignmentRaw = 0
            }

        case .updateTextColor(let color):
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            textObjects[idx].textColorComponents = [Double(r), Double(g), Double(b), Double(a)]

        case .updateBackgroundColor(let color):
            if let bg = color {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                bg.getRed(&r, green: &g, blue: &b, alpha: &a)
                textObjects[idx].backgroundColorComponents = [Double(r), Double(g), Double(b), Double(a)]
            } else {
                textObjects[idx].backgroundColorComponents = nil
            }

        case .updateBorderRadius(let radius):
            textObjects[idx].borderRadius = radius

        case .updateBorderColor(let color):
            if let bc = color {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                bc.getRed(&r, green: &g, blue: &b, alpha: &a)
                textObjects[idx].borderColorComponents = [Double(r), Double(g), Double(b), Double(a)]
            } else {
                textObjects[idx].borderColorComponents = nil
            }

        case .updateBorderWidth(let width):
            textObjects[idx].borderWidth = width
        }

        noteStore.updateTextObjects(for: note.id, pageIndex: pageIdx, textObjects: textObjects)
    }

    // MARK: - Background blend helper

    /// Blends the theme's canvas background colour with the paper material's
    /// `pageTint` by applying the tint as a very light overlay (15 % opacity).
    /// In dark themes the tint contribution is halved to avoid washing out the
    /// dark canvas.
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

    private var noteThemeMenu: some View {
        Menu {
            Button {
                noteStore.updateThemeOverride(for: note.id, theme: nil)
            } label: {
                if note.themeOverride == nil {
                    Label("App Theme", systemImage: "checkmark")
                } else {
                    Text("App Theme")
                }
            }
            Divider()
            ForEach(AppTheme.allCases) { theme in
                Button {
                    noteStore.updateThemeOverride(for: note.id, theme: theme)
                } label: {
                    if note.themeOverride == theme {
                        Label(theme.displayName, systemImage: "checkmark")
                    } else {
                        Label(theme.displayName, systemImage: theme.systemImage)
                    }
                }
                .disabled(theme.isPremium)
            }
        } label: {
            Image(systemName: note.themeOverride == nil ? "paintbrush" : "paintbrush.fill")
                .accessibilityLabel("Note theme")
        }
    }

    /// GoodNotes-style page setup menu — lets users change the page ruling and paper material
    /// for the current note without leaving the editor.
    private var pageSetupMenu: some View {
        let safePageIndex: Int = min(currentPageIndex, max(0, note.pageCount - 1))
        let currentPagePT = effectivePageType(forPage: safePageIndex)
        return Menu {
            // Per-page ruling section — only changes the current page
            Section("This Page") {
                ForEach(PageType.allCases) { pt in
                    Button {
                        noteStore.updatePageType(for: note.id, pageIndex: safePageIndex, pageType: pt)
                    } label: {
                        if currentPagePT == pt {
                            Label(pt.displayName, systemImage: "checkmark")
                        } else {
                            Label(pt.displayName, systemImage: pt.systemImage)
                        }
                    }
                }
            }

            Divider()

            // Note-level ruling — applies to all pages that have no per-page override
            Section("All Pages") {
                ForEach(PageType.allCases) { pt in
                    Button {
                        noteStore.updatePageType(for: note.id, pageType: pt)
                    } label: {
                        if effectivePageType == pt {
                            Label(pt.displayName, systemImage: "checkmark")
                        } else {
                            Label(pt.displayName, systemImage: pt.systemImage)
                        }
                    }
                }
            }

            Divider()

            // Paper material section
            Section("Paper Material") {
                ForEach(PaperMaterial.allCases) { pm in
                    Button {
                        noteStore.updatePaperMaterial(for: note.id, paperMaterial: pm)
                    } label: {
                        if effectivePaperMaterial == pm {
                            Label(pm.displayName, systemImage: "checkmark")
                        } else {
                            Label(pm.displayName, systemImage: pm.systemImage)
                        }
                    }
                }
            }

            Divider()

            // Page colour — quick presets for the current page
            Section("Page Colour") {
                Button {
                    noteStore.updatePageColor(for: note.id, pageIndex: safePageIndex, color: nil)
                } label: {
                    Label("Theme Default", systemImage: note.pageColor(forPage: safePageIndex) == nil
                          ? "checkmark" : "paintbrush")
                }
                ForEach(pageColorPresets, id: \.name) { preset in
                    Button {
                        noteStore.updatePageColor(
                            for: note.id, pageIndex: safePageIndex, color: preset.color)
                    } label: {
                        Label(preset.name, systemImage: "circle.fill")
                    }
                }
            }
        } label: {
            Image(systemName: "doc.richtext")
                .accessibilityLabel("Page setup")
        }
    }

    /// Quick-access page background colour presets.
    private var pageColorPresets: [(name: String, color: UIColor)] {
        [
            ("White",       .white),
            ("Cream",       UIColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1)),
            ("Pale Yellow",  UIColor(red: 1.00, green: 0.99, blue: 0.88, alpha: 1)),
            ("Pale Blue",    UIColor(red: 0.93, green: 0.96, blue: 1.00, alpha: 1)),
            ("Pale Green",   UIColor(red: 0.93, green: 0.99, blue: 0.93, alpha: 1)),
            ("Pale Pink",    UIColor(red: 1.00, green: 0.93, blue: 0.95, alpha: 1)),
            ("Light Grey",   UIColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1)),
            ("Dark Grey",    UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)),
            ("Black",        UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)),
        ]
    }

    // MARK: - Contrast banner

    private var contrastBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.fill")
                .font(.caption2)
            Text("Dark canvas — use a light ink colour for best contrast")
                .font(.caption2)
        }
        .foregroundStyle(Color(uiColor: effectiveDefinition.secondaryText))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: effectiveDefinition.canvasBackground).opacity(0.8))
    }

    // MARK: - Focus Mode Overlay

    /// Full-screen SwiftUI overlay combining background dimming and a radial
    /// vignette.  Layered behind toolbar capsules (zIndex 0.4) but above the
    /// canvas, so it dims chrome without intercepting touch input.
    @ViewBuilder
    private var focusModeOverlay: some View {
        ZStack {
            // Background dim — very subtle darkening of the entire view.
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            // Radial vignette — darkens edges, clear centre.
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.15)
                ]),
                center: .center,
                startRadius: 80,
                endRadius: UIScreen.main.bounds.height * 0.55
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Ambient Scene Overlay

    /// Lightweight SwiftUI tint overlay for the active ambient scene.
    /// The heavy lifting (rain streaks, grain, warm wash) is handled via
    /// CALayers in `AmbientEnvironmentEngine` — this overlay just adds
    /// a subtle colour tint that auto-sizes on rotation.
    @ViewBuilder
    private var ambientSceneOverlay: some View {
        switch toolStore.activeAmbientScene {
        case .rainStudy:
            // Cool blue-grey tint.
            Color(red: 0.6, green: 0.72, blue: 0.88).opacity(0.05)
                .ignoresSafeArea()
        case .lofiLight:
            // Warm amber tint.
            Color(red: 1.0, green: 0.92, blue: 0.76).opacity(0.04)
                .ignoresSafeArea()
        case .nightGrain:
            // Cool dark blue tint.
            Color(red: 0.15, green: 0.18, blue: 0.28).opacity(0.06)
                .ignoresSafeArea()
        case .none:
            EmptyView()
        }
    }

    // MARK: - Helpers

    /// Compact toolbar indicator that reflects the current disk-write state.
    /// - Spinning icon while saving (transitions quickly; mostly visible on slow storage).
    /// - Checkmark shown for 2 s after a successful save.
    /// - Warning triangle shown (persistently) when a save error has occurred.
    @ViewBuilder
    private var saveStateIndicator: some View {
        switch noteStore.saveState {
        case .saving:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityLabel("Saving")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .accessibilityLabel("Save error")
        case .saved where showSavedBadge:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .accessibilityLabel("Saved")
        default:
            EmptyView()
        }
    }

    private func refreshUndoRedoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    /// Opens the PDF or document that this note was created to accompany.
    ///
    /// If the linked import no longer exists (e.g. user deleted it), the action is a no-op.
    private func openLinkedImport() {
        if let pdfID = note.linkedPDFID,
           let record = pdfStore.records.first(where: { $0.id == pdfID }) {
            workspace.openTab(
                .pdf(id: record.id),
                displayName: record.title,
                accentColor: [0.8, 0.3, 0.3]
            )
        } else if let docID = note.linkedDocumentID,
                  let doc = documentStore.documents.first(where: { $0.id == docID }) {
            workspace.openTab(
                .document(id: doc.id),
                displayName: doc.displayName,
                accentColor: [0.3, 0.5, 0.7]
            )
        }
    }

    // MARK: - Linked Import Banner

    /// Tappable banner shown below the title when this note is linked to an imported document.
    /// Shows the source file name and type; tapping opens the linked file in its viewer tab.
    private var linkedImportBanner: some View {
        HStack(spacing: 8) {
            Button(action: openLinkedImport) {
                HStack(spacing: 8) {
                    Image(systemName: linkedImportIcon)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(
                            format: NSLocalizedString("Import.LinkedTo", comment: ""),
                            linkedImportTitle
                        ))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(linkedImportSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                format: NSLocalizedString("Import.LinkedTo", comment: ""),
                linkedImportTitle
            ))

            Button {
                showUnlinkConfirm = true
            } label: {
                Image(systemName: "link.badge.minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
                    .padding(.trailing, 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Import.Unlink", comment: ""))
        }
        .background(Color.accentColor.opacity(0.08))
        .alert(
            NSLocalizedString("Import.UnlinkTitle", comment: ""),
            isPresented: $showUnlinkConfirm
        ) {
            Button(NSLocalizedString("Import.Unlink", comment: ""), role: .destructive) {
                noteStore.unlinkCompanionNote(id: note.id)
            }
            Button(NSLocalizedString("Common.Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Import.UnlinkMessage", comment: ""))
        }
    }

    private var linkedImportIcon: String {
        if note.linkedPDFID != nil { return "doc.richtext" }
        return "doc"
    }

    private var linkedImportTitle: String {
        if let pdfID = note.linkedPDFID,
           let record = pdfStore.records.first(where: { $0.id == pdfID }) {
            return record.title
        }
        if let docID = note.linkedDocumentID,
           let doc = documentStore.documents.first(where: { $0.id == docID }) {
            return doc.displayName
        }
        return NSLocalizedString("Import.SourceDeleted", comment: "")
    }

    private var linkedImportSubtitle: String {
        if note.linkedPDFID != nil {
            if pdfStore.records.first(where: { $0.id == note.linkedPDFID }) != nil {
                return "PDF Document — " + NSLocalizedString("Import.TapToOpen", comment: "")
            }
            return NSLocalizedString("Import.SourceDeleted", comment: "")
        }
        if let docID = note.linkedDocumentID,
           let doc = documentStore.documents.first(where: { $0.id == docID }) {
            return "\(doc.documentType.displayName) — " + NSLocalizedString("Import.TapToOpen", comment: "")
        }
        return NSLocalizedString("Import.SourceDeleted", comment: "")
    }

    // MARK: - Selection Actions
    /// to the canvas's responder chain. PencilKit's built-in lasso selection
    /// supports cut/copy/paste/delete through the standard UIResponder actions.
    private func handleSelectionAction(_ action: SelectionAction) {
        // The canvas is first responder; dispatch standard UIResponder actions
        // which PencilKit handles for lasso selections.
        let app = UIApplication.shared
        switch action {
        case .cut:
            app.sendAction(#selector(UIResponderStandardEditActions.cut(_:)), to: nil, from: nil, for: nil)
            toolStore.hasActiveSelection = false
        case .copy:
            app.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: nil, for: nil)
        case .duplicate:
            // Copy then paste in-place to duplicate selected strokes
            app.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: nil, for: nil)
            app.sendAction(#selector(UIResponderStandardEditActions.paste(_:)), to: nil, from: nil, for: nil)
        case .delete:
            app.sendAction(#selector(UIResponderStandardEditActions.delete(_:)), to: nil, from: nil, for: nil)
            toolStore.hasActiveSelection = false
        }
    }

    // MARK: - Export menu

    /// Toolbar menu that offers PDF and image export options for the current note.
    private var exportMenu: some View {
        let safePageIndex: Int = min(currentPageIndex, max(0, note.pageCount - 1))
        return Menu {
            Section("Export") {
                Button {
                    exportCurrentPageAsPDF(pageIndex: safePageIndex)
                } label: {
                    Label("Export Page as PDF", systemImage: "doc.fill")
                }

                Button {
                    exportAllPagesAsPDF()
                } label: {
                    Label("Export All Pages as PDF", systemImage: "doc.on.doc.fill")
                }

                Button {
                    exportCurrentPageAsImage(pageIndex: safePageIndex)
                } label: {
                    Label("Export Page as Image", systemImage: "photo")
                }
            }
        } label: {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(isExporting)
        .accessibilityLabel("Export")
    }

    /// Exports only the current page as a single-page PDF and presents the share sheet.
    private func exportCurrentPageAsPDF(pageIndex: Int) {
        guard note.pages.indices.contains(pageIndex) else { return }
        let pageData = note.pages[pageIndex]
        let pt = effectivePageType(forPage: pageIndex)
        let bg = canvasBackgroundColor
        let title = note.title.isEmpty ? "Note" : note.title
        let attachments = note.attachments(forPage: pageIndex)
        let widgets = note.widgets(forPage: pageIndex)
        let nid = note.id
        isExporting = true
        Task {
            let url = await NoteExporter.exportAsPDF(
                title: "\(title) — Page \(pageIndex + 1)",
                pages: [pageData],
                attachmentLayers: [attachments.isEmpty ? nil : attachments],
                widgetLayers: [widgets.isEmpty ? nil : widgets],
                noteID: nid,
                backgroundColor: bg,
                pageTypes: [pt]
            )
            await MainActor.run {
                isExporting = false
                if let url {
                    shareItems = [url]
                    showShareSheet = true
                }
            }
        }
    }

    /// Exports every page of the note as a multi-page PDF and presents the share sheet.
    /// When the note has a maintained backing PDF, shares it directly without re-rendering.
    private func exportAllPagesAsPDF() {
        let attachmentLayers = note.attachmentLayers
        let widgetLayersData = note.widgetLayers
        let nid = note.id

        // Fast path: share the maintained PDF file directly when available.
        if let pdfURL = noteStore.notePDFURL(for: note),
           FileManager.default.fileExists(atPath: pdfURL.path) {
            // Force a synchronous regeneration so the PDF reflects the very latest strokes.
            if let filename = note.pdfFilename {
                let pageTypes = (0..<note.pageCount).map { effectivePageType(forPage: $0) }
                NotePDFGenerator.regeneratePDF(
                    filename: filename,
                    pages: note.pages,
                    attachmentLayers: attachmentLayers,
                    noteID: nid,
                    backgroundColor: canvasBackgroundColor,
                    pageTypes: pageTypes
                )
            }
            shareItems = [pdfURL]
            showShareSheet = true
            return
        }
        // Fallback: render a new PDF from scratch (legacy notes without backing PDF).
        let pages = note.pages
        let pageTypes = (0..<note.pageCount).map { effectivePageType(forPage: $0) }
        let bg = canvasBackgroundColor
        let title = note.title.isEmpty ? "Note" : note.title
        isExporting = true
        Task {
            let url = await NoteExporter.exportAsPDF(
                title: title,
                pages: pages,
                attachmentLayers: attachmentLayers,
                widgetLayers: widgetLayersData,
                noteID: nid,
                backgroundColor: bg,
                pageTypes: pageTypes
            )
            await MainActor.run {
                isExporting = false
                if let url {
                    shareItems = [url]
                    showShareSheet = true
                }
            }
        }
    }

    /// Exports the current page as a PNG image and presents the share sheet.
    private func exportCurrentPageAsImage(pageIndex: Int) {
        guard note.pages.indices.contains(pageIndex) else { return }
        let pageData = note.pages[pageIndex]
        let pt = effectivePageType(forPage: pageIndex)
        let bg = canvasBackgroundColor
        let attachments = note.attachments(forPage: pageIndex)
        let widgets = note.widgets(forPage: pageIndex)
        let nid = note.id
        isExporting = true
        Task {
            let image = await NoteExporter.exportPageAsImage(
                pageData: pageData,
                attachments: attachments.isEmpty ? nil : attachments,
                widgets: widgets.isEmpty ? nil : widgets,
                noteID: nid,
                backgroundColor: bg,
                pageType: pt
            )
            await MainActor.run {
                isExporting = false
                if let image {
                    shareItems = [image]
                    showShareSheet = true
                }
            }
        }
    }

    private var titleField: some View {
        TextField("Note title", text: $titleText)
            .font(.title2.bold())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onChange(of: titleText) { _, newValue in
                noteStore.updateTitle(for: note.id, title: newValue)
            }
    }

    // MARK: - In-document find bar

    /// Compact find bar shown between the toolbar and the canvas.
    /// Searches the note's `typedText`; shows a count and previous/next navigation.
    /// For drawing-only notes (empty typedText) it shows a context message.
    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)

            TextField("Find in note…", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .onChange(of: findQuery) { _, _ in updateFindMatches() }
                .submitLabel(.search)
                .onSubmit { advanceFindMatch(forward: true) }

            if !findMatches.isEmpty {
                Text("\(findMatchIndex + 1)/\(findMatches.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else if !findQuery.isEmpty {
                Text(note.typedText.isEmpty && note.ocrText.isEmpty ? "Drawing only" : "0 results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Spacer(minLength: 0)

            if !findMatches.isEmpty {
                Button {
                    advanceFindMatch(forward: false)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(findMatches.count <= 1)
                .accessibilityLabel("Previous match")

                Button {
                    advanceFindMatch(forward: true)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(findMatches.count <= 1)
                .accessibilityLabel("Next match")
            }

            Button {
                showFindBar = false
                findQuery = ""
                findMatches = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close find bar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func updateFindMatches() {
        findMatches = searchService.findInDocument(query: findQuery, note: note)
        findMatchIndex = 0
    }

    private func advanceFindMatch(forward: Bool) {
        guard !findMatches.isEmpty else { return }
        if forward {
            findMatchIndex = (findMatchIndex + 1) % findMatches.count
        } else {
            findMatchIndex = (findMatchIndex - 1 + findMatches.count) % findMatches.count
        }
    }

    // MARK: - Typed text layer

    /// Full-height scrollable text editor shown when the user is in keyboard (text) mode.
    /// Uses the note's effective theme for background and text colours.
    private var textLayer: some View {
        TextEditor(text: $typedTextContent)
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: effectiveDefinition.canvasBackground))
            .foregroundStyle(Color(uiColor: effectiveDefinition.primaryText))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: typedTextContent) { _, _ in scheduleTextSave() }
    }

    /// Schedules a debounced persist of the current `typedTextContent`.
    /// Mirrors the 0.8 s debounce used by the drawing layer.
    private func scheduleTextSave() {
        textSaveTimer?.invalidate()
        let id   = note.id
        let text = typedTextContent
        let store = noteStore
        textSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
            store.updateTypedText(for: id, text: text)
        }
    }

    /// Immediately cancels the pending debounce timer and persists typed text to the store.
    private func flushTextNow() {
        textSaveTimer?.invalidate()
        textSaveTimer = nil
        noteStore.updateTypedText(for: note.id, text: typedTextContent)
    }

    // MARK: - Page navigation (book-like experience)

    /// Horizontal bar with prev/next buttons, page indicator, overview, and add-page action.
    private var pageNavigationBar: some View {
        HStack(spacing: 16) {
            // Previous page
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPageIndex = max(0, currentPageIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .disabled(currentPageIndex <= 0)
            .accessibilityLabel("Previous page")

            Spacer()

            // Page overview button — opens the grid view
            Button {
                showPageOverview = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                    Text("Page \(currentPageIndex + 1) of \(note.pageCount)")
                        .font(.subheadline.monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Page \(currentPageIndex + 1) of \(note.pageCount). Tap to open page overview.")

            Spacer()

            // Add page
            Button {
                if let newIndex = noteStore.addPage(to: note.id) {
                    isNewPageJustAdded = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPageIndex = newIndex
                    }
                    // Reset the flag after the CA reveal animation completes.
                    // The delay (0.55 s) intentionally exceeds the SwiftUI navigation
                    // animation (0.25 s) to ensure the new CanvasView is fully
                    // displayed before the flag resets, preventing a double-reveal
                    // if SwiftUI re-renders during the transition.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        isNewPageJustAdded = false
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
                    currentPageIndex = min(note.pageCount - 1, currentPageIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .disabled(currentPageIndex >= note.pageCount - 1)
            .accessibilityLabel("Next page")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.85))
    }
}

// MARK: - PencilKit canvas bridge

/// UIViewRepresentable that wraps a PKCanvasView inside a plain UIView container.
/// The container also hosts a ShapeOverlayView that intercepts gestures when the
/// shape tool is active so shapes can be committed as PKStrokes.
///
/// Features
/// - Tool driven by `DrawingToolStore` via `currentTool` (no floating PKToolPicker).
/// - Finger vs Pencil drawing policy: controlled by `drawingPolicy`.
/// - Zoom/pan: pinch-to-zoom from 0.25× to 5×; zoom-reset via `zoomResetTrigger`.
/// - Shape overlay: dashed preview + PKStroke commit when shape tool is active.
/// - Performance: `OSSignposter` intervals for canvas setup; events for drawing changes
///   and save flushes — all visible in Instruments → os_signpost.
/// - Undo/redo state: reports (canUndo, canRedo) from the canvas's own undo manager
///   after every drawing change via `onUndoStateChanged`.
///
/// **Apple Pencil features (all degrade gracefully)**
/// - Double-tap (Pencil 2nd gen+, iOS 12.1+): dispatches the user's preferred action.
/// - Squeeze (Pencil Pro, iOS 17.5+): dispatches the user's preferred squeeze action.
/// - Ghost nib / hover preview (M2+ iPad Pro, iOS 16.1+): draws an overlay cursor.
/// - Barrel-roll fountain pen (Pencil Pro, iOS 17.5+): modulates fountain-pen width.
/// - Contextual palette: compact floating palette anchored near the Pencil tip.

struct CanvasView: UIViewRepresentable {
    let noteID: UUID
    let drawingData: Data
    let backgroundColor: UIColor
    let defaultInkColor: UIColor
    let currentTool: PKTool
    let isShapeToolActive: Bool
    let activeShapeType: ShapeType
    let shapeColor: UIColor
    let shapeWidth: Double
    /// Controls whether finger touches draw or pan/zoom the canvas.
    let drawingPolicy: PKCanvasViewDrawingPolicy
    /// Flip this value to trigger an animated reset to 1× zoom scale.
    let zoomResetTrigger: Bool
    /// Page ruling style rendered behind the canvas.
    let pageType: PageType
    /// Paper material used for background tint and grain texture.
    let paperMaterial: PaperMaterial
    /// Active writing FX type from the ink-effects system (`.none` = no FX).
    let activeFX: WritingFXType
    /// Ink colour resolved for the active FX preset.
    let fxColor: UIColor
    /// Zero-based page index within the multi-page note.
    let pageIndex: Int
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void
    /// Called after each stroke with updated (canUndo, canRedo) from the canvas undo manager.
    let onUndoStateChanged: ((Bool, Bool) -> Void)?
    /// Called when a two-finger swipe gesture requests a page change.
    /// Positive = next page, negative = previous page.
    let onPageSwipe: ((Int) -> Void)?
    /// Called when a pinch-in gesture requests the page overview.
    let onPinchToOverview: (() -> Void)?
    /// On-disk URL of the note's backing PDF, if available.
    /// When non-nil the canvas renders the PDF page as background instead of the
    /// procedural `PageBackgroundView`, giving the note a book-like appearance.
    let pdfURL: URL?
    /// Reference to the toolbar store, used to drive auto-fade during drawing.
    var toolStoreForFade: DrawingToolStore?

    /// Shape objects for the current page.
    var currentPageShapes: [ShapeInstance] = []
    /// Callback to persist shape changes.
    var onShapesChanged: (([ShapeInstance]) -> Void)?

    /// Attachment objects for the current page.
    var currentPageAttachments: [AttachmentObject] = []
    /// Note ID used for attachment file lookups.
    var attachmentNoteID: UUID = UUID()
    /// Callback to persist attachment changes.
    var onAttachmentsChanged: (([AttachmentObject]) -> Void)?
    /// Callback when attachment selection changes.
    var onAttachmentSelectionChanged: ((UUID?) -> Void)?

    /// Widget instances for the current page.
    var currentPageWidgets: [NoteWidget] = []
    /// Callback to persist widget changes.
    var onWidgetsChanged: (([NoteWidget]) -> Void)?
    /// Callback when widget selection changes.
    var onWidgetSelectionChanged: ((UUID?) -> Void)?

    /// Whether the text tool is active (text canvas overlay intercepts touches).
    var isTextToolActive: Bool = false
    /// Text objects for the current page.
    var currentPageTextObjects: [TextObject] = []
    /// Callback to persist text object changes.
    var onTextObjectsChanged: (([TextObject]) -> Void)?
    /// Callback when text object selection changes.
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    /// Called when the user taps an empty area while the text tool is active.
    var onPlaceTextObject: ((CGPoint) -> Void)?

    /// Total number of pages in the note, used for adaptive effects complexity signals.
    var pageCount: Int = 1

    /// Whether Magic Mode is active (writing particles, keyword glow, highlight).
    var isMagicModeActive: Bool = false
    /// Whether Study Mode is active (heading glow, checklist pulse, timer pulse).
    var isStudyModeActive: Bool = false
    /// The currently active ambient environment scene, or `nil` when inactive.
    var activeAmbientScene: AmbientScene?
    /// Whether ambient soundscapes are enabled.
    var isAmbientSoundEnabled: Bool = true

    /// When `true`, `makeUIView` plays a paper-settle reveal animation on the
    /// container layer to celebrate the addition of a brand-new blank page.
    var isNewPage: Bool = false

    // MARK: - Page dimensions

    /// A4 paper aspect ratio (~1 : √2) used to compute page height from width.
    private static let a4AspectRatio: CGFloat = 1.414

    /// Fixed page size for the canvas content area. Uses the *landscape* screen
    /// width (the larger dimension) with an A4 aspect ratio so the page fills
    /// the screen in width regardless of orientation and provides vertical
    /// scrolling room like a real paper page.
    static let pageSize: CGSize = {
        let screen = UIScreen.main.bounds
        let w = max(screen.width, screen.height)
        return CGSize(width: w, height: ceil(w * a4AspectRatio))
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDrawingChanged: onDrawingChanged,
            onSaveRequested: onSaveRequested,
            onPageSwipe: onPageSwipe,
            onPinchToOverview: onPinchToOverview
        )
    }

    // swiftlint:disable:next function_body_length
    func makeUIView(context: Context) -> UIView {
        let setupState = editorSignposter.beginInterval("CanvasSetup")
        editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - begin")

        let container = UIView()
        // The container is the "desk surface" — it shows around the page when
        // zoomed out.  The paper colour is rendered by PageBackgroundView instead.
        container.backgroundColor = Self.deskSurfaceColor

        // ── Page background (ruling + paper tint, sits behind the canvas) ──────
        // Frame-based layout sized to the fixed page dimensions so the ruling
        // zooms and scrolls together with the PencilKit drawing content.
        let ps = Self.pageSize
        let pageBackground = PageBackgroundView(frame: CGRect(origin: .zero, size: ps))
        pageBackground.pageColor    = backgroundColor
        pageBackground.pageType     = pageType
        pageBackground.lineColor    = Self.rulingLineColor(for: backgroundColor)
        pageBackground.grainIntensity = paperMaterial.grainIntensity
        pageBackground.rulingTint   = paperMaterial.rulingTint
        pageBackground.isUserInteractionEnabled = false

        // Give the page a soft drop-shadow so it looks like a physical sheet
        // resting on the desk surface.  An explicit shadow path avoids the
        // expensive offscreen-composite pass that Core Animation would otherwise
        // need for a view with a non-opaque background.
        pageBackground.layer.shadowColor   = UIColor.black.cgColor
        pageBackground.layer.shadowOpacity = 0.18
        pageBackground.layer.shadowRadius  = 12
        pageBackground.layer.shadowOffset  = CGSize(width: 0, height: 3)
        pageBackground.layer.shadowPath    =
            UIBezierPath(rect: CGRect(origin: .zero, size: ps)).cgPath

        container.addSubview(pageBackground)
        context.coordinator.pageBackground = pageBackground

        // ── PDF page background (book-like feel) ─────────────────────────────
        // When the note has a backing PDF, render the template page from the PDF
        // file so the background is a real PDF page.  This sits above the
        // procedural PageBackgroundView and provides pixel-perfect fidelity with
        // the exported PDF.
        if let pdfURL,
           let pdfDoc = PDFDocument(url: pdfURL),
           let pdfPage = pdfDoc.page(at: pageIndex) {
            let mediaBox = pdfPage.bounds(for: .mediaBox)
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: ps, format: format)
            let pageImage = renderer.image { ctx in
                let cgCtx = ctx.cgContext
                cgCtx.setFillColor(backgroundColor.cgColor)
                cgCtx.fill(CGRect(origin: .zero, size: ps))
                // Scale from PDF media box to canvas page size
                let sx = ps.width / mediaBox.width
                let sy = ps.height / mediaBox.height
                let scale = min(sx, sy)
                cgCtx.saveGState()
                cgCtx.scaleBy(x: scale, y: -scale)
                cgCtx.translateBy(x: 0, y: -mediaBox.height)
                pdfPage.draw(with: .mediaBox, to: cgCtx)
                cgCtx.restoreGState()
            }
            let pdfImageView = UIImageView(image: pageImage)
            pdfImageView.frame = CGRect(origin: .zero, size: ps)
            pdfImageView.contentMode = .scaleToFill
            pdfImageView.isUserInteractionEnabled = false
            container.addSubview(pdfImageView)
            context.coordinator.pdfBackgroundView = pdfImageView
        }

        // ── PencilKit canvas ─────────────────────────────────────────────────
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = drawingPolicy
        canvas.alwaysBounceVertical   = true
        canvas.alwaysBounceHorizontal = true
        // Canvas is transparent so the page background shows through.
        canvas.backgroundColor = .clear
        canvas.tool = currentTool

        // Touch type filtering for latency reduction: when pencilOnly mode is
        // active, restrict the drawing gesture recognizer to pencil touches only.
        // This eliminates the ~16ms first-touch discrimination delay that
        // PKCanvasView normally incurs waiting to decide if a touch is pencil
        // or finger.
        if WritingConfig.useTouchTypeFiltering && drawingPolicy == .pencilOnly {
            canvas.drawingGestureRecognizer.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.pencil.rawValue)
            ]
        }

        // Zoom/pan: PKCanvasView inherits UIScrollView zoom support.
        // 0.25× minimum lets users step back for a full-page view.
        // 5×   maximum provides fine-detail writing precision.
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.bouncesZoom = true

        // Deceleration rate: fast deceleration feels more "anchored" and prevents
        // the canvas from sliding away after a quick pan. This matches the feel
        // of physical paper on a desk.
        canvas.decelerationRate = .fast

        // Set the canvas content area to the fixed page dimensions so the user
        // can draw across the full page and scroll vertically.
        canvas.contentSize = ps

        // Restore previously saved drawing, if any.
        if !drawingData.isEmpty, let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }

        container.addSubview(canvas)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.canvas = canvas
        canvas.isUserInteractionEnabled = !isShapeToolActive

        // Begin observing scroll/zoom so the page background tracks the canvas
        // content (zoom + pan).
        context.coordinator.observeCanvasScroll(canvas)

        // ── Shape overlay ────────────────────────────────────────────────────
        let overlay = ShapeOverlayView(
            shapeType: activeShapeType,
            strokeColor: shapeColor,
            strokeWidth: CGFloat(shapeWidth)
        ) { stroke in
            // PKDrawing.strokes is a read-only sequence; appending requires building
            // a new PKDrawing from the full stroke list — this is the standard
            // PencilKit pattern since PKDrawing is an immutable value type.
            canvas.drawing = PKDrawing(strokes: Array(canvas.drawing.strokes) + [stroke])
        }
        overlay.isHidden = !isShapeToolActive

        container.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.shapeOverlay = overlay

        // ── Attachment canvas (attachment cards layer) ────────────────────────
        let attachCanvas = AttachmentCanvasView(frame: .zero)
        attachCanvas.translatesAutoresizingMaskIntoConstraints = false
        attachCanvas.noteID = attachmentNoteID
        attachCanvas.attachments = currentPageAttachments
        attachCanvas.onSelectionChanged = { attachmentID in
            context.coordinator.onAttachmentSelectionChanged?(attachmentID)
        }
        attachCanvas.onAttachmentTransformed = { attachment in
            context.coordinator.handleAttachmentTransformed(attachment)
        }
        attachCanvas.onAttachmentsChanged = { attachments in
            context.coordinator.handleAttachmentsChanged(attachments)
        }
        context.coordinator.onAttachmentsChanged = onAttachmentsChanged
        context.coordinator.onAttachmentSelectionChanged = onAttachmentSelectionChanged
        container.addSubview(attachCanvas)
        NSLayoutConstraint.activate([
            attachCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            attachCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            attachCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            attachCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.attachmentCanvas = attachCanvas

        // ── Widget canvas (interactive widget cards layer) ───────────────────
        let widgetCanvas = WidgetCanvasView(frame: .zero)
        widgetCanvas.translatesAutoresizingMaskIntoConstraints = false
        widgetCanvas.widgets = currentPageWidgets
        widgetCanvas.onSelectionChanged = { widgetID in
            context.coordinator.onWidgetSelectionChanged?(widgetID)
        }
        widgetCanvas.onWidgetTransformed = { widget in
            context.coordinator.handleWidgetTransformed(widget)
        }
        widgetCanvas.onWidgetsChanged = { widgets in
            context.coordinator.handleWidgetsChanged(widgets)
        }
        // Study mode: fire checklist completion animation.
        widgetCanvas.onChecklistCompleted = { _, center in
            context.coordinator.studyModeEngine.checklistComplete(at: center)
        }
        // Study mode: fire timer/progress completion animation.
        widgetCanvas.onTimerCompleted = { _, _ in
            context.coordinator.studyModeEngine.timerComplete()
        }
        context.coordinator.onWidgetsChanged = onWidgetsChanged
        context.coordinator.onWidgetSelectionChanged = onWidgetSelectionChanged
        container.addSubview(widgetCanvas)
        NSLayoutConstraint.activate([
            widgetCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            widgetCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            widgetCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            widgetCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.widgetCanvas = widgetCanvas

        // ── Text object canvas (anchored text boxes layer) ───────────────────
        let textCanvas = TextCanvasView(frame: .zero)
        textCanvas.translatesAutoresizingMaskIntoConstraints = false
        textCanvas.isTextToolActive = isTextToolActive
        textCanvas.textObjects = currentPageTextObjects
        textCanvas.onSelectionChanged = { textObjectID in
            context.coordinator.onTextObjectSelectionChanged?(textObjectID)
        }
        textCanvas.onTextObjectsChanged = { textObjects in
            context.coordinator.handleTextObjectsChanged(textObjects)
        }
        textCanvas.onPlaceTextObject = { point in
            context.coordinator.onPlaceTextObject?(point)
        }
        textCanvas.onTextObjectTransformed = { textObject in
            context.coordinator.handleTextObjectTransformed(textObject)
        }
        context.coordinator.onTextObjectsChanged = onTextObjectsChanged
        context.coordinator.onTextObjectSelectionChanged = onTextObjectSelectionChanged
        context.coordinator.onPlaceTextObject = onPlaceTextObject
        container.addSubview(textCanvas)
        NSLayoutConstraint.activate([
            textCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            textCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.textCanvas = textCanvas

        // ── Shape object canvas (editable shapes layer) ──────────────────────
        let shapeCanvas = ShapeCanvasView(frame: .zero)
        shapeCanvas.translatesAutoresizingMaskIntoConstraints = false
        shapeCanvas.shapes = currentPageShapes
        shapeCanvas.isShapeToolActive = isShapeToolActive
        shapeCanvas.onShapesChanged = { [weak shapeCanvas] shapes in
            guard let shapeCanvas else { return }
            context.coordinator.handleShapesChanged(shapes)
            shapeCanvas.shapes = shapes
        }
        shapeCanvas.onSelectionChanged = { shapeID in
            context.coordinator.handleShapeSelectionChanged(shapeID)
        }
        context.coordinator.onShapesChanged = onShapesChanged
        container.addSubview(shapeCanvas)
        NSLayoutConstraint.activate([
            shapeCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            shapeCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shapeCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shapeCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.shapeCanvas = shapeCanvas

        // ── Hover overlay (non-interactive, floats above the canvas) ─────────
        let hoverOverlay = PencilHoverOverlayView(frame: .zero)
        hoverOverlay.translatesAutoresizingMaskIntoConstraints = false
        hoverOverlay.isUserInteractionEnabled = false
        canvas.addSubview(hoverOverlay)
        NSLayoutConstraint.activate([
            hoverOverlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: canvas.topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        context.coordinator.hoverOverlay = hoverOverlay

        // ── Eraser cursor overlay (non-interactive, shows ring sized to eraser width) ──
        let eraserCursor = EraserCursorOverlay(frame: .zero)
        eraserCursor.translatesAutoresizingMaskIntoConstraints = false
        eraserCursor.isUserInteractionEnabled = false
        canvas.addSubview(eraserCursor)
        NSLayoutConstraint.activate([
            eraserCursor.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            eraserCursor.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            eraserCursor.topAnchor.constraint(equalTo: canvas.topAnchor),
            eraserCursor.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        context.coordinator.eraserCursorOverlay = eraserCursor

        // ── Apple Pencil interaction coordinator ─────────────────────────────
        let pencilCoordinator = PencilInteractionCoordinator()
        pencilCoordinator.delegate = context.coordinator
        pencilCoordinator.attach(to: canvas)
        context.coordinator.pencilCoordinator = pencilCoordinator
        context.coordinator.canvasRef = canvas

        // ── Real-time nib tracker for effects ────────────────────────────────
        // PencilNibTrackerGestureRecognizer fires on every pencil touchesMoved
        // event at the hardware's native frame rate (up to 240 Hz).  This drives
        // ink-effect emitter positions in real time instead of waiting for
        // canvasViewDrawingDidChange (which only fires on committed stroke batches
        // and lags 100–300 ms behind the actual pen tip).
        let nibTracker = PencilNibTrackerGestureRecognizer()
        nibTracker.onNibBegan = { [weak context] location in
            guard let coordinator = context?.coordinator,
                  coordinator.isDrawing,
                  coordinator.canvasRef?.tool is PKInkingTool else { return }
            let inkColor = (coordinator.canvasRef?.tool as? PKInkingTool)?.color ?? .label
            coordinator.effects.dispatch(
                .strokeBegan(at: location, inkColor: inkColor),
                inkEffectEngine: coordinator.effectEngine
            )
        }
        nibTracker.onNibMoved = { [weak context] location, force, velocity in
            guard let coordinator = context?.coordinator,
                  coordinator.isDrawing,
                  coordinator.canvasRef?.tool is PKInkingTool else { return }
            coordinator.effects.dispatch(
                .strokeUpdated(at: location, pressure: force, velocity: velocity),
                inkEffectEngine: coordinator.effectEngine
            )
        }
        canvas.addGestureRecognizer(nibTracker)
        context.coordinator.nibTracker = nibTracker

        // ── Scratch-to-delete gesture recognizer ─────────────────────────────
        // ScribbleDeleteRecognizer is a fully passive observer: it never cancels
        // or prevents PKCanvasView's own drawing recognizer.  When a rapid
        // back-and-forth pencil motion is detected, the matching ink strokes are
        // removed via deleteScratchStrokes(in:).  The deletion is dispatched
        // asynchronously to guarantee PKCanvasView has committed the stroke before
        // we modify canvas.drawing.
        let scratchRecognizer = ScribbleDeleteRecognizer()
        scratchRecognizer.onScratchDetected = { [weak coordinator = context.coordinator] viewportRect in
            DispatchQueue.main.async {
                coordinator?.deleteScratchStrokes(in: viewportRect)
            }
        }
        canvas.addGestureRecognizer(scratchRecognizer)
        context.coordinator.scratchDeleteRecognizer = scratchRecognizer

        // Pre-warm all haptic generators for interaction feedback (AGENT-23).
        context.coordinator.interactionFeedback.prepareAll()

        // ── Ink effect engine (fire / sparkle / glitch / ripple) ────────────
        let engine = InkEffectEngine(tier: DeviceCapabilityTier.current)
        engine.configure(fx: activeFX, color: fxColor)
        engine.attach(to: container)
        context.coordinator.effectEngine = engine

        // ── Writing Effects Pipeline (glow, neon, trail, taper, pooling) ───
        context.coordinator.writingPipeline.attach(to: container)
        context.coordinator.writingPipeline.configure(
            config: toolStoreForFade?.writingEffectConfig ?? .default,
            color: toolStoreForFade?.activeColor ?? .black
        )

        // ── Page gestures (two-finger pan + three-finger pinch) ──────────────
        // Two-finger horizontal pan navigates pages.  Using a pan recogniser
        // (instead of a swipe) allows the page to follow the finger in real-time,
        // giving the physical "book page" feel.  A horizontal-dominance check in
        // the handler prevents accidental fires during canvas pan/zoom.
        let pagePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePagePan(_:))
        )
        pagePan.minimumNumberOfTouches = 2
        pagePan.maximumNumberOfTouches = 2
        pagePan.delegate = context.coordinator
        container.addGestureRecognizer(pagePan)
        context.coordinator.pagePanGesture = pagePan

        // Pinch-in opens page overview grid.
        // The gesture delegate allows simultaneous recognition with
        // PKCanvasView's built-in pinch-to-zoom so normal zoom still works.
        let pinchOverview = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinchToOverview(_:))
        )
        pinchOverview.delegate = context.coordinator
        container.addGestureRecognizer(pinchOverview)
        context.coordinator.pinchOverviewGesture = pinchOverview

        // ── Book feel: page shadow ──────────────────────────────────────────
        // Shadow is on the pageBackground layer (see above) so it follows the
        // page rather than the full-screen container.

        // Seed coordinator state so the first updateUIView call does not misfire.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder so Apple Pencil is ready immediately.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            // Set initial zoom so the page width fits the visible canvas exactly.
            // This ensures the user sees a complete, correctly-proportioned page on
            // first open regardless of device orientation or screen size.
            let canvasW = canvas.bounds.width
            if canvasW > 0 {
                let fitZoom = canvasW / CanvasView.pageSize.width
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, fitZoom))
                canvas.setZoomScale(clamped, animated: false)
            }
            editorSignposter.endInterval("CanvasSetup", setupState)
            editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - complete")
        }

        // Play a paper-settle reveal when this canvas represents a newly added page.
        if isNewPage {
            PageTransitionEngine.playNewPageReveal(on: container.layer)
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        // Wire up toolbar store reference for auto-fade (idempotent).
        context.coordinator.toolStoreRef = toolStoreForFade

        // Sync page background (ruling view).
        if let bg = context.coordinator.pageBackground {
            if bg.pageColor != backgroundColor {
                bg.pageColor  = backgroundColor
                bg.lineColor  = Self.rulingLineColor(for: backgroundColor)
            }
            if bg.pageType != pageType {
                bg.pageType = pageType
            }
            let wantedIntensity = paperMaterial.grainIntensity
            if bg.grainIntensity != wantedIntensity {
                bg.grainIntensity = wantedIntensity
            }
            let wantedTint = paperMaterial.rulingTint
            if bg.rulingTint != wantedTint {
                bg.rulingTint = wantedTint
            }
            // Re-sync position/scale in case SwiftUI re-rendered while
            // the canvas was scrolled or zoomed.
            context.coordinator.syncBackgroundWithCanvas(canvas)
        }

        // Sync drawing policy when the user toggles the finger/pencil preference.
        if canvas.drawingPolicy != drawingPolicy {
            canvas.drawingPolicy = drawingPolicy
            // Update touch type filtering to match: pencilOnly → restrict to pencil
            // touches for faster first-touch discrimination, anyInput → allow all.
            if WritingConfig.useTouchTypeFiltering {
                if drawingPolicy == .pencilOnly {
                    canvas.drawingGestureRecognizer.allowedTouchTypes = [
                        NSNumber(value: UITouch.TouchType.pencil.rawValue)
                    ]
                } else {
                    canvas.drawingGestureRecognizer.allowedTouchTypes = [
                        NSNumber(value: UITouch.TouchType.direct.rawValue),
                        NSNumber(value: UITouch.TouchType.pencil.rawValue),
                    ]
                }
            }
            // Reset palm guard when switching modes.
            context.coordinator.palmGuard.reset()
        }

        // Update the active tool from DrawingToolStore — but ONLY when:
        // 1. The user is not mid-stroke (setting tool mid-stroke kills PencilKit's
        //    internal pressure/tilt pipeline, destroying pressure sensitivity).
        // 2. The tool actually changed. We compare a lightweight snapshot of the
        //    tool's identity (type + ink type + color + width) to avoid redundant
        //    assignments that would reset PencilKit's state.
        if !context.coordinator.isDrawing {
            let snapshot = ToolSnapshot(currentTool)
            if context.coordinator.lastToolSnapshot != snapshot {
                canvas.tool = currentTool
                context.coordinator.lastToolSnapshot = snapshot

                // ── Interaction feedback for tool switch (AGENT-23) ─────
                if currentTool is PKEraserTool {
                    context.coordinator.interactionFeedback.play(.eraserEngage, on: canvas.layer)
                } else {
                    context.coordinator.interactionFeedback.play(.toolSwitch, on: canvas.layer)
                    context.coordinator.microInteractionEngine.playToolSwitchMorph(on: canvas.layer)
                }
            }
        }
        canvas.isUserInteractionEnabled = !isShapeToolActive

        // Sync shape overlay properties.
        if let overlay = context.coordinator.shapeOverlay {
            overlay.isHidden    = !isShapeToolActive
            overlay.shapeType   = activeShapeType
            overlay.strokeColor = shapeColor
            overlay.strokeWidth = CGFloat(shapeWidth)
        }

        // Sync shape object canvas.
        if let shapeCanvas = context.coordinator.shapeCanvas {
            shapeCanvas.isShapeToolActive = isShapeToolActive
            shapeCanvas.shapes = currentPageShapes
            shapeCanvas.selectedShapeID = toolStoreForFade?.activeShapeSelection
        }

        // Sync attachment canvas.
        if let attachCanvas = context.coordinator.attachmentCanvas {
            attachCanvas.attachments = currentPageAttachments
            attachCanvas.noteID = attachmentNoteID
            attachCanvas.selectedAttachmentID = toolStoreForFade?.activeAttachmentSelection
            attachCanvas.zoomScale = canvas.zoomScale
        }
        context.coordinator.onAttachmentsChanged = onAttachmentsChanged
        context.coordinator.onAttachmentSelectionChanged = onAttachmentSelectionChanged

        // Sync widget canvas.
        if let widgetCanvas = context.coordinator.widgetCanvas {
            widgetCanvas.widgets = currentPageWidgets
            widgetCanvas.selectedWidgetID = toolStoreForFade?.activeWidgetSelection
        }
        context.coordinator.onWidgetsChanged = onWidgetsChanged
        context.coordinator.onWidgetSelectionChanged = onWidgetSelectionChanged

        // Sync text object canvas.
        if let textCanvas = context.coordinator.textCanvas {
            textCanvas.isTextToolActive = isTextToolActive
            textCanvas.textObjects = currentPageTextObjects
            textCanvas.selectedTextObjectID = toolStoreForFade?.activeTextObjectSelection
        }
        context.coordinator.onTextObjectsChanged = onTextObjectsChanged
        context.coordinator.onTextObjectSelectionChanged = onTextObjectSelectionChanged
        context.coordinator.onPlaceTextObject = onPlaceTextObject

        // Zoom reset: animate to fit-to-width when the trigger value flips.
        // "Fit to width" is more useful than a fixed 1× scale because it adapts
        // to the current screen size and orientation.
        if context.coordinator.lastZoomResetTrigger != zoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            // Dispatch to avoid mutating scroll state mid-layout-pass.
            DispatchQueue.main.async {
                let canvasW = canvas.bounds.width
                let fitZoom = canvasW > 0 ? canvasW / CanvasView.pageSize.width : 1.0
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, fitZoom))
                canvas.setZoomScale(clamped, animated: true)
                editorLogger.debug("[\(noteID, privacy: .public)] zoom reset to fit-width (\(clamped, format: .fixed(precision: 2))×)")
            }
        }

        // Keep the undo state callback current (closures capture SwiftUI state by value).
        context.coordinator.onUndoStateChanged = onUndoStateChanged

        // Sync page boundary info so the page-pan gesture can reject out-of-range drags.
        context.coordinator.coordinatorPageIndex = pageIndex
        context.coordinator.coordinatorPageCount = pageCount

        // Sync adaptive effects engine with current note complexity.
        context.coordinator.adaptiveEffectsEngine.pageCount = pageCount
        // Propagate current intensity to canvas sub-views (coordinator
        // handles its own sub-engines automatically via Combine).
        let intensity = context.coordinator.adaptiveEffectsEngine.intensity
        context.coordinator.effects.distribute(
            intensity: intensity,
            shapeCanvas: context.coordinator.shapeCanvas,
            attachmentCanvas: context.coordinator.attachmentCanvas,
            widgetCanvas: context.coordinator.widgetCanvas
        )

        // Sync magic mode engine — activate/deactivate when toggle changes.
        context.coordinator.effects.setMagicMode(active: isMagicModeActive, on: uiView.layer)
        // Sync study mode engine — activate/deactivate when toggle changes.
        context.coordinator.effects.setStudyMode(active: isStudyModeActive, on: uiView.layer)
        // Keep layout-sensitive engines in sync on resize / rotation.
        context.coordinator.effects.updateLayout(containerBounds: uiView.bounds)

        // Sync ambient environment engine — activate/deactivate/sound when scene changes.
        let ambientEngine = context.coordinator.ambientEngine
        ambientEngine.soundEnabled = isAmbientSoundEnabled
        if let ts = toolStoreForFade {
            switch (activeAmbientScene, ambientEngine.activeScene) {
            case let (scene?, current) where current != scene:
                ambientEngine.activate(scene, on: uiView.layer, toolStore: ts)
            case (nil, .some):
                ambientEngine.deactivate(toolStore: ts)
            default:
                break
            }
        }
        if ambientEngine.activeScene != nil {
            ambientEngine.updateLayout(containerBounds: uiView.bounds)
        }

        // Sync ink effect engine configuration when FX type or colour changes.
        if let engine = context.coordinator.effectEngine {
            engine.syncLayerFrames()
            engine.configure(fx: activeFX, color: fxColor)
        }

        // Sync writing effects pipeline when the pen tool or colour changes.
        context.coordinator.writingPipeline.configure(
            config: toolStoreForFade?.writingEffectConfig ?? .default,
            color: toolStoreForFade?.activeColor ?? .black
        )
    }

    // MARK: - Ruling line color helper

    /// Returns a ruling line color that is visible against the given background.
    /// On dark backgrounds the lines are white at low opacity; on light backgrounds
    /// they are black at low opacity.
    private static func rulingLineColor(for background: UIColor) -> UIColor {
        let isDarkBackground: Bool = {
            var white: CGFloat = 0
            if background.getWhite(&white, alpha: nil) {
                return white < 0.5
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            if background.getRed(&red, green: &green, blue: &blue, alpha: nil) {
                let relativeLuminance =
                    (0.2126 * red) +
                    (0.7152 * green) +
                    (0.0722 * blue)
                return relativeLuminance < 0.5
            }

            return false
        }()

        return isDarkBackground
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.label.withAlphaComponent(0.10)
    }

    // MARK: - Desk surface color

    /// The background color shown outside the page boundaries (the "desk" surface).
    /// Uses a neutral warm-gray that contrasts with the paper in both light and
    /// dark appearances, giving the canvas the look of a real page resting on a table.
    private static let deskSurfaceColor: UIColor = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.13, alpha: 1)
            : UIColor(white: 0.86, alpha: 1)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let onDrawingChanged: (Data) -> Void
        let onSaveRequested: () -> Void
        /// Page swipe callback: +1 next, −1 previous.
        let onPageSwipe: ((Int) -> Void)?
        /// Pinch-to-overview callback.
        let onPinchToOverview: (() -> Void)?
        weak var canvas: PKCanvasView?
        weak var shapeOverlay: ShapeOverlayView?
        /// Page ruling / background view placed behind the canvas.
        weak var pageBackground: PageBackgroundView?
        /// PDF page image rendered behind the canvas (book-like feel).
        weak var pdfBackgroundView: UIImageView?
        /// Updated by updateUIView to always hold the freshest closure.
        var onUndoStateChanged: ((Bool, Bool) -> Void)?
        /// Tracks the last zoom-reset trigger seen so we only react to flips.
        var lastZoomResetTrigger: Bool = false
        private var debounceTimer: Timer?

        // Apple Pencil support
        var pencilCoordinator: PencilInteractionCoordinator?
        /// Passive gesture recognizer that feeds real-time pencil positions
        /// to the effects engines at the hardware's native touch rate.
        var nibTracker: PencilNibTrackerGestureRecognizer?
        var hoverOverlay: PencilHoverOverlayView?
        var eraserCursorOverlay: EraserCursorOverlay?
        /// Passive gesture recognizer that detects scratch-to-delete gestures.
        var scratchDeleteRecognizer: ScribbleDeleteRecognizer?
        weak var canvasRef: PKCanvasView?

        /// Ink effect engine that renders fire/sparkle/glitch/ripple overlays.
        var effectEngine: InkEffectEngine?

        /// Central coordinator that owns and wires all effect sub-engines.
        let effects = EffectsCoordinator()

        // Convenience accessors forwarded to the coordinator.
        var pageTransitionEngine: PageTransitionEngine { effects.pageTransitionEngine }
        var focusModeEngine: FocusModeEngine           { effects.focusModeEngine }
        var ambientEngine: AmbientEnvironmentEngine    { effects.ambientEngine }
        var magicModeEngine: MagicModeEngine           { effects.magicModeEngine }
        var studyModeEngine: StudyModeEngine           { effects.studyModeEngine }
        var adaptiveEffectsEngine: AdaptiveEffectsEngine { effects.adaptiveEngine }
        var writingPipeline: WritingEffectsPipeline    { effects.writingEffectsPipeline }
        var microInteractionEngine: MicroInteractionEngine { effects.microInteractionEngine }
        var snapAlignEffectEngine: SnapAlignEffectEngine { effects.snapAlignEffectEngine }
        var interactionFeedback: InteractionFeedbackEngine { effects.interactionFeedbackEngine }


        /// Shape objects canvas for the current page.
        weak var shapeCanvas: ShapeCanvasView?

        /// Debounce timer for persisting shape changes.
        private var shapeDebounceTimer: Timer?

        /// Callback to persist shape changes.
        var onShapesChanged: (([ShapeInstance]) -> Void)?

        /// Attachment canvas overlay for the current page.
        weak var attachmentCanvas: AttachmentCanvasView?

        /// Debounce timer for persisting attachment changes.
        private var attachmentDebounceTimer: Timer?

        /// Callback to persist attachment changes.
        var onAttachmentsChanged: (([AttachmentObject]) -> Void)?

        /// Callback when attachment selection changes.
        var onAttachmentSelectionChanged: ((UUID?) -> Void)?

        /// Widget canvas overlay for the current page.
        weak var widgetCanvas: WidgetCanvasView?

        /// Debounce timer for persisting widget changes.
        private var widgetDebounceTimer: Timer?

        /// Callback to persist widget changes.
        var onWidgetsChanged: (([NoteWidget]) -> Void)?

        /// Callback when widget selection changes.
        var onWidgetSelectionChanged: ((UUID?) -> Void)?

        /// Text object canvas overlay for the current page.
        weak var textCanvas: TextCanvasView?

        /// Debounce timer for persisting text object changes.
        private var textDebounceTimer: Timer?

        /// Callback to persist text object changes.
        var onTextObjectsChanged: (([TextObject]) -> Void)?

        /// Callback when text object selection changes.
        var onTextObjectSelectionChanged: ((UUID?) -> Void)?

        /// Called when the user taps empty space with the text tool active.
        var onPlaceTextObject: ((CGPoint) -> Void)?

        /// Callback to propagate text object transform to the view.
        var onTextObjectTransformed: ((TextObject) -> Void)?

        /// Weak reference to the drawing tool store for toolbar auto-fade.
        weak var toolStoreRef: DrawingToolStore?

        /// Task that schedules the toolbar fade after a delay of active drawing.
        private var fadeTask: Task<Void, Never>?

        /// Pinch gesture recognizer for page overview.
        var pinchOverviewGesture: UIPinchGestureRecognizer?

        /// Two-finger pan gesture recognizer for interactive page navigation.
        var pagePanGesture: UIPanGestureRecognizer?

        /// Minimum scale observed during the current pinch-to-overview gesture.
        /// Tracked during `.changed` because `numberOfTouches` is zero at `.ended`.
        private var pinchOverviewMinScale: CGFloat = 1.0

        // ── Interactive page-drag state ──────────────────────────────────────────
        /// True while a two-finger horizontal pan is being tracked for page navigation.
        private var pageIsDragging = false
        /// Direction locked in at the start of the current page drag.
        private var pageDragDirection: PageTransitionDirection = .forward
        /// Current zero-based page index, kept in sync by `updateUIView`.
        var coordinatorPageIndex: Int = 0
        /// Total page count, kept in sync by `updateUIView`.
        var coordinatorPageCount: Int = 1

        /// Light haptic feedback played when a page drag commits.
        private let pageTurnImpact: UIImpactFeedbackGenerator = {
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            return g
        }()

        /// True while the user is actively drawing a stroke. Used to prevent
        /// `updateUIView` from overwriting `canvas.tool` mid-stroke, which
        /// would reset PencilKit's internal pressure/tilt pipeline.
        private(set) var isDrawing = false

        /// Tracks the last PKTool identity set on the canvas so updateUIView
        /// skips redundant assignments that would reset PencilKit's state.
        var lastToolSnapshot: ToolSnapshot?

        /// Stable base width captured from the tool when a fountain-pen stroke
        /// begins. Used for barrel-roll modulation so the feedback loop does
        /// not shift the reference width on every micro-movement.
        var barrelRollBaseWidth: CGFloat?

        /// The last active inking tool before switching to the eraser.
        /// Used to restore the tool when the user double-taps "switch to previous".
        private var previousInkingTool: PKTool?

        /// Zoom scale captured when a stroke begins. When `WritingConfig.lockZoomDuringWriting`
        /// is enabled, the canvas zoom is pinned to this value during active writing to
        /// prevent accidental zoom drift from multi-touch interference.
        private var strokeStartZoomScale: CGFloat?

        /// Timer that re-enables zoom/scroll gestures after a short delay following
        /// the end of a stroke. Prevents accidental zoom when lifting the hand
        /// between quick successive strokes.
        private var postStrokeZoomUnlockTimer: Timer?

        /// Timer that fires when the user holds the pen still after drawing a stroke,
        /// triggering automatic straightening of the last stroke into a clean line.
        private var holdToStraightenTimer: Timer?

        /// True while `straightenLastStroke` is replacing the canvas drawing so
        /// `canvasViewDrawingDidChange` does not restart `holdToStraightenTimer`
        /// on the programmatic change.
        private var isStraightening = false

        /// Tracks Apple Pencil contact timing for palm rejection in `.anyInput` mode.
        let palmGuard = PalmGuardState()

        /// Tracks stroke count and data size for performance warnings.
        let strokeMonitor = StrokePerformanceMonitor()

        // KVO observers that keep the page background in sync with canvas
        // scroll offset and zoom scale. Invalidated automatically on dealloc.
        private var contentOffsetObservation: NSKeyValueObservation?
        private var zoomScaleObservation: NSKeyValueObservation?

        /// Tracks whether the last zoom update landed on a detent, so the
        /// visual micro-bounce fires only on the leading edge (entry, not hold).
        private var wasOnZoomDetent: Bool = false

        // Pre-prepared haptic generator for double-tap pencil delete feedback.
        // Preparing eagerly avoids the latency spike that would occur if the
        // generator were created and prepared on the first deletion event.
        private let deletionImpactGenerator: UIImpactFeedbackGenerator = {
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            return g
        }()

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onSaveRequested: @escaping () -> Void,
            onPageSwipe: ((Int) -> Void)? = nil,
            onPinchToOverview: (() -> Void)? = nil
        ) {
            self.onDrawingChanged = onDrawingChanged
            self.onSaveRequested  = onSaveRequested
            self.onPageSwipe      = onPageSwipe
            self.onPinchToOverview = onPinchToOverview
        }

        deinit {
            // Flush any pending drawing save so strokes are never silently
            // dropped when the coordinator deallocates (e.g. on page change).
            flushPendingSave()
            // Invalidate remaining timers.
            postStrokeZoomUnlockTimer?.invalidate()
            shapeDebounceTimer?.invalidate()
            attachmentDebounceTimer?.invalidate()
            // KVO observations are invalidated automatically by
            // NSKeyValueObservation.deinit, but nil them for clarity.
            contentOffsetObservation?.invalidate()
            zoomScaleObservation?.invalidate()
        }

        // MARK: - Page gesture handlers

        /// Tuning constants for the two-finger page-pan gesture recogniser.
        private enum PagePanTuning {
            /// Minimum horizontal-to-vertical ratio required before the gesture
            /// is locked in as a horizontal page drag.
            static let horizontalDominanceRatio: CGFloat = 1.5
            /// Minimum horizontal displacement (points) before direction is
            /// locked in — prevents accidental page turns on tiny movements.
            static let minimumLockInDistance: CGFloat = 8
            /// Minimum horizontal release velocity (points/second) for a
            /// reduce-motion fast-swipe to commit a page change.
            static let reducedMotionCommitVelocity: CGFloat = 400
        }

        /// Two-finger pan handler for interactive page navigation.
        ///
        /// The page follows the finger in real-time.  Direction is determined on
        /// the first update where horizontal motion clearly dominates vertical.
        /// Backward drags are blocked when already on the first page to prevent
        /// the container from flying off-screen with no state change to recover it.
        ///
        /// `onPageSwipe` is only called inside the snap-completion callback so
        /// SwiftUI rebuilds the page content *after* the outgoing page has
        /// finished its animation — eliminating the visual conflict that occurred
        /// when state and CA animation changed simultaneously.
        @objc func handlePagePan(_ gesture: UIPanGestureRecognizer) {
            guard !isDrawing, let view = gesture.view else { return }

            let translation = gesture.translation(in: view)
            let velocity    = gesture.velocity(in: view)
            let pageWidth   = view.bounds.width

            switch gesture.state {
            case .began:
                // Direction and drag start are deferred until the first `.changed`
                // event that shows clear horizontal dominance.
                pageIsDragging = false

            case .changed:
                if !pageIsDragging {
                    // Wait until horizontal motion clearly dominates vertical.
                    guard abs(translation.x) > abs(translation.y) * PagePanTuning.horizontalDominanceRatio,
                          abs(translation.x) > PagePanTuning.minimumLockInDistance
                    else { return }

                    let dir: PageTransitionDirection = translation.x < 0 ? .forward : .backward

                    // Block backward drag on the very first page: there's nothing to
                    // return to, and committing would leave the container off-screen.
                    if dir == .backward && coordinatorPageIndex == 0 { return }

                    // Reduce-motion: fall through to the simpler cross-fade path.
                    if pageTransitionEngine.effectIntensity.allowsPageTurnPhysics {
                        pageDragDirection = dir
                        pageIsDragging    = true
                        pageTransitionEngine.beginInteractiveDrag(
                            on: view,
                            direction: dir,
                            pageWidth: pageWidth
                        )
                    }
                }

                if pageIsDragging {
                    pageTransitionEngine.updateInteractiveDrag(
                        on: view,
                        translation: translation.x,
                        pageWidth: pageWidth
                    )
                }

            case .ended:
                if pageIsDragging {
                    // Normal mode: spring-snap the interactive drag to completion
                    // or back to origin.
                    pageIsDragging = false

                    pageTransitionEngine.finishInteractiveDrag(
                        on: view,
                        velocityX: velocity.x,
                        pageWidth: pageWidth
                    ) { [weak self] committed in
                        guard let self, committed else { return }
                        // Flush any pending drawing save so strokes are
                        // persisted before the page transition replaces
                        // the canvas content.
                        self.flushPendingSave()
                        self.pageTurnImpact.impactOccurred()
                        self.pageTurnImpact.prepare()
                        self.onPageSwipe?(self.pageDragDirection == .forward ? 1 : -1)
                    }
                } else if !pageTransitionEngine.effectIntensity.allowsPageTurnPhysics {
                    // Reduce-motion / low-intensity fallback: treat a fast, clearly
                    // horizontal release as a swipe and change page immediately.
                    guard abs(velocity.x) > PagePanTuning.reducedMotionCommitVelocity,
                          abs(velocity.x) > abs(velocity.y) * PagePanTuning.horizontalDominanceRatio
                    else { return }
                    let dir: PageTransitionDirection = velocity.x < 0 ? .forward : .backward
                    guard !(dir == .backward && coordinatorPageIndex == 0) else { return }
                    flushPendingSave()
                    onPageSwipe?(dir == .forward ? 1 : -1)
                }

            case .cancelled, .failed:
                guard pageIsDragging else { return }
                pageIsDragging = false
                pageTransitionEngine.cancelInteractiveDrag(on: view) {}

            default:
                break
            }
        }

        /// Pinch-in handler for page overview.
        @objc func handlePinchToOverview(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchOverviewMinScale = gesture.scale
            case .changed:
                pinchOverviewMinScale = min(pinchOverviewMinScale, gesture.scale)
            case .ended, .cancelled:
                // Trigger overview when the user performed a clear pinch-in
                // (fingers came together significantly).
                if pinchOverviewMinScale < 0.7 {
                    onPinchToOverview?()
                }
                pinchOverviewMinScale = 1.0
            default:
                break
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        /// Allows the page-overview pinch and the page-pan to fire simultaneously
        /// with PKCanvasView's built-in gestures.  The page-pan handler uses a
        /// horizontal-dominance check to distinguish page turns from canvas scroll.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === pinchOverviewGesture
                || gestureRecognizer === pagePanGesture
        }

        // MARK: - Drawing lifecycle (protects pressure/tilt pipeline)

        /// Converts a PKDrawing content-space point to the viewport/overlay
        /// coordinate space so that ink-effect particles render at the correct
        /// on-screen position regardless of zoom/scroll state.
        private func viewportPoint(from contentPoint: CGPoint, in canvasView: PKCanvasView) -> CGPoint {
            let z = canvasView.zoomScale
            let o = canvasView.contentOffset
            return CGPoint(
                x: contentPoint.x * z - o.x,
                y: contentPoint.y * z - o.y
            )
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = true
            // Cancel any pending zoom-unlock timer from a previous stroke so
            // rapid successive strokes keep zoom locked continuously.
            postStrokeZoomUnlockTimer?.invalidate()
            postStrokeZoomUnlockTimer = nil

            // Cancel any pending hold-to-straighten from the previous stroke.
            holdToStraightenTimer?.invalidate()
            holdToStraightenTimer = nil

            // Lock zoom during writing to prevent accidental zoom drift from
            // multi-touch interference (e.g. palm resting on screen).
            if WritingConfig.lockZoomDuringWriting {
                strokeStartZoomScale = canvasView.zoomScale
                canvasView.pinchGestureRecognizer?.isEnabled = false
                canvasView.isScrollEnabled = false
            }

            // Capture base width for barrel-roll modulation at stroke start.
            if let inkTool = canvasView.tool as? PKInkingTool {
                barrelRollBaseWidth = inkTool.width
            }
            // NOTE: .strokeBegan is dispatched by PencilNibTrackerGestureRecognizer
            // with the actual first-contact position.  No dispatch needed here.
            // Auto-fade toolbar using config constants
            fadeTask?.cancel()
            fadeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(WritingConfig.toolbarFadeDelay))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFadedOpacity
                }
            }
            // Pause attachment rendering during active strokes for zero lag.
            attachmentCanvas?.renderingPaused = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = false
            // Pen lifted — discard any pending hold-to-straighten.
            holdToStraightenTimer?.invalidate()
            holdToStraightenTimer = nil
            // If barrel-roll modulated the fountain-pen width during this stroke,
            // the canvas tool is left at the modulated (drifted) width.
            // Invalidate lastToolSnapshot so updateUIView resets canvas.tool to
            // the canonical width from DrawingToolStore before the next stroke,
            // preventing a compounding feedback loop where each stroke starts
            // wider than the last.
            if barrelRollBaseWidth != nil {
                lastToolSnapshot = nil
            }
            barrelRollBaseWidth = nil

            // Re-enable zoom and scroll after a short delay to prevent
            // accidental zoom when lifting the hand between rapid successive
            // strokes.  Guard `isDrawing` in the callback to handle the rare
            // case where a new stroke begins before the timer fires.
            if WritingConfig.lockZoomDuringWriting {
                postStrokeZoomUnlockTimer?.invalidate()
                postStrokeZoomUnlockTimer = Timer.scheduledTimer(
                    withTimeInterval: WritingConfig.postStrokeZoomLockDelay,
                    repeats: false
                ) { [weak self, weak canvasView] _ in
                    guard let self, !self.isDrawing else { return }
                    canvasView?.pinchGestureRecognizer?.isEnabled = true
                    canvasView?.isScrollEnabled = true
                }
                strokeStartZoomScale = nil
            }

            // Record pencil end time for palm guard (finger rejection window).
            palmGuard.pencilStrokeEnded()

            // Signal stroke pause to the adaptive effects engine so it can
            // decay the smoothed writing rate and potentially restore effects.
            Task { @MainActor [weak self] in
                self?.adaptiveEffectsEngine.reportStrokePause()
            }

            // Dispatch stroke-ended through the effects coordinator (single stroke read).
            let fallbackPt = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
            if let lastStroke = canvasView.drawing.strokes.last {
                let path = lastStroke.path
                let endPt = path.last.map {
                    viewportPoint(from: CGPoint(x: $0.location.x, y: $0.location.y), in: canvasView)
                } ?? fallbackPt
                let startPt = path.first.map {
                    viewportPoint(from: CGPoint(x: $0.location.x, y: $0.location.y), in: canvasView)
                } ?? endPt
                let bbox = lastStroke.renderBounds
                let vpOrigin = viewportPoint(from: bbox.origin, in: canvasView)
                let vpMax    = viewportPoint(from: CGPoint(x: bbox.maxX, y: bbox.maxY), in: canvasView)
                let headingBounds = CGRect(
                    x: vpOrigin.x, y: vpOrigin.y,
                    width: vpMax.x - vpOrigin.x, height: vpMax.y - vpOrigin.y
                )
                let strokeEndColor = (canvasView.tool as? PKInkingTool)?.color ?? .label
                effects.dispatch(
                    .strokeEnded(at: endPt, start: startPt,
                                 inkColor: strokeEndColor, headingBounds: headingBounds),
                    inkEffectEngine: effectEngine
                )
            } else {
                effects.dispatch(
                    .strokeEnded(at: fallbackPt, start: fallbackPt,
                                 inkColor: .label, headingBounds: .zero),
                    inkEffectEngine: effectEngine
                )
            }
            // Restore toolbar opacity after drawing ends using config constants
            fadeTask?.cancel()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(WritingConfig.toolbarRestoreDelay))
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFullOpacity
                }
            }
            // Detect lasso selection state. When the user finishes a lasso gesture
            // the canvas holds an internal selection. We set hasActiveSelection so
            // the floating toolbar morphs to show selection actions.
            if canvasView.tool is PKLassoTool {
                markLassoSelectionActive()
            } else {
                updateSelectionState(for: canvasView)
            }
            // Resume attachment rendering after a short delay (matches toolbar restore timing).
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.attachmentCanvas?.renderingPaused = false
                self?.attachmentCanvas?.setNeedsDisplay()
            }
        }

        /// Updates `toolStore.hasActiveSelection` based on whether the canvas
        /// currently holds a lasso selection. Called after tool-end events and
        /// drawing changes to keep the toolbar in sync.
        ///
        /// Detection: when the lasso tool finishes a gesture, PencilKit holds an
        /// internal selection. We track this via a simple flag that is set when
        /// `canvasViewDidEndUsingTool` fires while a PKLassoTool is active, and
        /// cleared when the drawing changes (selection committed) or the tool
        /// switches away from lasso.
        func updateSelectionState(for canvasView: PKCanvasView) {
            let isLasso = canvasView.tool is PKLassoTool
            // Only set true when lasso tool just finished a gesture (likely selected
            // something). Reset when drawing changes or tool switches.
            if !isLasso && toolStoreRef?.hasActiveSelection == true {
                Task { @MainActor [weak self] in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        self?.toolStoreRef?.hasActiveSelection = false
                    }
                }
            }
        }

        /// Marks that the lasso tool completed a selection gesture.
        /// Called from `canvasViewDidEndUsingTool` when the active tool is a lasso.
        func markLassoSelectionActive() {
            guard toolStoreRef?.hasActiveSelection != true else { return }
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self?.toolStoreRef?.hasActiveSelection = true
                }
            }
        }

        /// Clears the selection state (e.g. after the drawing changes, meaning
        /// the selection was committed or the canvas was otherwise modified).
        func clearSelectionState() {
            guard toolStoreRef?.hasActiveSelection != false else { return }
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self?.toolStoreRef?.hasActiveSelection = false
                }
            }
        }

        // MARK: - Shape Object Handlers

        /// Called when the shape canvas reports changes to shape objects.
        func handleShapesChanged(_ shapes: [ShapeInstance]) {
            shapeDebounceTimer?.invalidate()
            shapeDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: ShapeConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onShapesChanged?(shapes)
            }
        }

        /// Called when shape selection changes.
        func handleShapeSelectionChanged(_ shapeID: UUID?) {
            Task { @MainActor [weak self] in
                self?.toolStoreRef?.activeShapeSelection = shapeID
            }
        }

        // MARK: - Attachment Coordination

        /// Called when an attachment is moved or resized.
        func handleAttachmentTransformed(_ attachment: AttachmentObject) {
            guard var attachments = attachmentCanvas?.attachments else { return }
            if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                attachments[idx] = attachment
            }
            handleAttachmentsChanged(attachments)
        }

        /// Debounced persistence for attachment changes.
        func handleAttachmentsChanged(_ attachments: [AttachmentObject]) {
            attachmentDebounceTimer?.invalidate()
            attachmentDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: AttachmentConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onAttachmentsChanged?(attachments)
            }
        }

        // MARK: - Widget Coordinator

        func handleWidgetTransformed(_ widget: NoteWidget) {
            guard var widgets = widgetCanvas?.widgets else { return }
            if let idx = widgets.firstIndex(where: { $0.id == widget.id }) {
                widgets[idx] = widget
            }
            handleWidgetsChanged(widgets)
        }

        /// Debounced persistence for widget changes.
        func handleWidgetsChanged(_ widgets: [NoteWidget]) {
            widgetDebounceTimer?.invalidate()
            widgetDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: WidgetConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onWidgetsChanged?(widgets)
            }
        }

        // MARK: - Text Object Coordinator

        /// Called when a text object is moved, resized, or rotated.
        func handleTextObjectTransformed(_ textObject: TextObject) {
            guard var textObjects = textCanvas?.textObjects else { return }
            if let idx = textObjects.firstIndex(where: { $0.id == textObject.id }) {
                textObjects[idx] = textObject
            }
            handleTextObjectsChanged(textObjects)
        }

        /// Debounced persistence for text object changes.
        func handleTextObjectsChanged(_ textObjects: [TextObject]) {
            textDebounceTimer?.invalidate()
            textDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: TextObjectConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onTextObjectsChanged?(textObjects)
            }
        }

        // MARK: - Double-tap pencil to delete last stroke

        /// Removes the most recently drawn stroke from the canvas.
        /// Called when the user double-taps Apple Pencil.  Registered with the
        /// canvas's own `UndoManager` so it can be reversed with undo.
        func deleteLastStroke() {
            guard let canvas = canvasRef else { return }
            let strokes = Array(canvas.drawing.strokes)
            guard !strokes.isEmpty else { return }

            let oldDrawing = canvas.drawing
            let newDrawing = PKDrawing(strokes: Array(strokes.dropLast()))

            canvas.undoManager?.registerUndo(withTarget: canvas) { cv in
                cv.drawing = oldDrawing
            }
            canvas.undoManager?.setActionName(
                NSLocalizedString("Delete Stroke", comment: "Undo action name for pencil double-tap delete")
            )

            canvas.drawing = newDrawing

            deletionImpactGenerator.impactOccurred()
            deletionImpactGenerator.prepare()
        }

        // MARK: - Scratch-to-delete

        /// Removes every PKStroke whose render bounds intersect the scratch region
        /// described by `viewportRect` (in the canvas scroll-view's bounds coordinates).
        ///
        /// This is called by ``ScribbleDeleteRecognizer`` after it confirms that the
        /// user drew a rapid back-and-forth scratch gesture.  Because the scratch was
        /// drawn with the active inking tool it becomes a regular PKStroke — that
        /// stroke's render bounds lie within `viewportRect`, so it is included in the
        /// set of strokes to remove alongside any pre-existing strokes it overlaps.
        ///
        /// The operation is registered with the canvas's `UndoManager` so it can be
        /// reversed with a standard Undo gesture or Cmd-Z.
        func deleteScratchStrokes(in viewportRect: CGRect) {
            guard let canvas = canvasRef else { return }

            // Expand the hit region slightly to account for stroke width — strokes
            // are compared by their render bounds, which already includes the ink
            // radius, but a small inset guards against sub-pixel rounding gaps.
            let contentRect = self.contentRect(from: viewportRect, in: canvas)
            let hitRect     = contentRect.insetBy(dx: -10, dy: -10)

            let allStrokes = Array(canvas.drawing.strokes)
            let remaining  = allStrokes.filter { !$0.renderBounds.intersects(hitRect) }

            // Nothing to delete — either the scratch was over empty space or the
            // detection fired erroneously.  Bail early without touching undo stack.
            guard remaining.count < allStrokes.count else { return }

            let oldDrawing = canvas.drawing
            let newDrawing = PKDrawing(strokes: remaining)

            canvas.undoManager?.registerUndo(withTarget: canvas) { cv in
                cv.drawing = oldDrawing
            }
            canvas.undoManager?.setActionName(
                NSLocalizedString("Editor.ScratchDelete.UndoAction",
                                  comment: "Undo action name for scribble-to-delete")
            )

            canvas.drawing = newDrawing

            // Scale haptic weight with the number of strokes removed: a single
            // scratch stroke that erases only itself gets a normal impact, while
            // removing several strokes at once gets a heavier double-impact.
            let deletedCount = allStrokes.count - remaining.count
            deletionImpactGenerator.impactOccurred()
            if deletedCount > 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.deletionImpactGenerator.impactOccurred()
                }
            }
            deletionImpactGenerator.prepare()
        }

        /// Converts a rectangle from the canvas scroll-view's **viewport** (bounds)
        /// coordinate space into the PKDrawing **content** coordinate space.
        ///
        /// PKStroke.renderBounds lives in content space; gesture touch locations are
        /// reported in the scroll-view's bounds space.  The mapping is:
        ///
        ///     contentPoint.x = (viewportPoint.x + contentOffset.x) / zoomScale
        ///
        /// which is the inverse of `viewportPoint(from:in:)` defined nearby.
        private func contentRect(from viewportRect: CGRect, in canvasView: PKCanvasView) -> CGRect {
            let z = canvasView.zoomScale
            let o = canvasView.contentOffset
            let origin = CGPoint(
                x: (viewportRect.minX + o.x) / z,
                y: (viewportRect.minY + o.y) / z
            )
            let size = CGSize(
                width:  viewportRect.width  / z,
                height: viewportRect.height / z
            )
            return CGRect(origin: origin, size: size)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            editorSignposter.emitEvent("DrawingChanged")

            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

            // NOTE: effect position updates are driven by PencilNibTrackerGestureRecognizer
            // at the hardware's native touch rate.  No position dispatch is needed here.

            // Report undo/redo availability directly from the canvas's undo manager.
            // PKCanvasView inherits UIResponder.undoManager which traverses the responder
            // chain — the same manager PencilKit registers stroke actions against.
            let um = canvasView.undoManager
            onUndoStateChanged?(um?.canUndo ?? false, um?.canRedo ?? false)

            // Drawing changed — selection was committed (paste, delete, move, etc.)
            // so clear the selection state to collapse the selection toolbar.
            clearSelectionState()

            // Update stroke performance monitor for warning thresholds.
            let strokeCount = canvasView.drawing.strokes.count
            Task { @MainActor [weak self] in
                self?.strokeMonitor.update(strokeCount: strokeCount, dataSize: data.count)
                self?.adaptiveEffectsEngine.currentPageStrokeCount = strokeCount
                self?.adaptiveEffectsEngine.reportStrokeChange()
            }

            // Hold-to-straighten: restart the timer on every new drawing change
            // while the pen is still down. If drawing stops changing (user holds
            // the pen still), the timer fires and replaces the last stroke with a
            // clean straight line between its start and end points.
            if isDrawing, !isStraightening, canvasView.tool is PKInkingTool {
                holdToStraightenTimer?.invalidate()
                holdToStraightenTimer = Timer.scheduledTimer(
                    withTimeInterval: WritingConfig.holdToStraightenDelay,
                    repeats: false
                ) { [weak self, weak canvasView] _ in
                    guard let self, self.isDrawing, let canvasView else { return }
                    self.holdToStraightenTimer = nil
                    self.straightenLastStroke(in: canvasView)
                }
            }

            // Debounce disk writes using config constant.
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: WritingConfig.saveDebounceInterval, repeats: false) { [weak self] _ in
                editorSignposter.emitEvent("DrawingSaved")
                self?.onSaveRequested()
            }
        }

        /// Immediately cancels the pending debounce timer and triggers a
        /// synchronous save.  Called before page transitions so strokes
        /// drawn just before a swipe are never silently dropped.
        func flushPendingSave() {
            guard debounceTimer != nil else { return }
            debounceTimer?.invalidate()
            debounceTimer = nil
            onSaveRequested()
        }

        // MARK: - Canvas scroll / zoom → background sync
        // MARK: - Hold-to-Straighten

        /// Replaces the last stroke in `canvasView.drawing` with a clean straight
        /// line from its first point to its last point, preserving the original
        /// ink colour, tool type, and per-point pressure/tilt attributes.
        ///
        /// Called by `holdToStraightenTimer` when the user holds the pen still
        /// after drawing without lifting it. The replacement is registered with
        /// the canvas's own `UndoManager` so it can be reversed with undo.
        private func straightenLastStroke(in canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            let strokes = Array(drawing.strokes)
            guard !strokes.isEmpty else { return }
            let strokeIndex = strokes.count - 1
            let stroke = strokes[strokeIndex]
            let path = stroke.path
            guard path.count >= 2,
                  let firstPoint = path.first,
                  let lastPoint  = path.last else { return }

            let dx = lastPoint.location.x - firstPoint.location.x
            let dy = lastPoint.location.y - firstPoint.location.y
            let length = sqrt(dx * dx + dy * dy)
            guard length >= WritingConfig.holdToStraightenMinLength else { return }

            // Build a straight-line path by mapping original point attributes
            // (size, force, tilt) onto evenly-spaced locations along the new line.
            // This preserves pressure dynamics while straightening the geometry.
            let pointCount = max(3, min(path.count, WritingConfig.holdToStraightenMaxPoints))
            let straightPoints: [PKStrokePoint] = (0 ..< pointCount).map { i in
                let t = CGFloat(i) / CGFloat(pointCount - 1)
                let loc = CGPoint(
                    x: firstPoint.location.x + t * dx,
                    y: firstPoint.location.y + t * dy
                )
                // +0.5 performs nearest-neighbour rounding when mapping the
                // straight-line position t back to an original path index.
                let origIdx = min(Int(t * CGFloat(path.count - 1) + 0.5), path.count - 1)
                let orig = path[origIdx]
                return PKStrokePoint(
                    location: loc,
                    timeOffset: firstPoint.timeOffset + t * (lastPoint.timeOffset - firstPoint.timeOffset),
                    size: orig.size,
                    opacity: orig.opacity,
                    force: orig.force,
                    azimuth: orig.azimuth,
                    altitude: orig.altitude
                )
            }

            let straightPath   = PKStrokePath(controlPoints: straightPoints, creationDate: path.creationDate)
            let straightStroke = PKStroke(ink: stroke.ink, path: straightPath,
                                          transform: stroke.transform, mask: stroke.mask)

            var newStrokes = strokes
            newStrokes[strokeIndex] = straightStroke
            let newDrawing = PKDrawing(strokes: newStrokes)

            let oldDrawing = drawing
            isStraightening = true
            canvasView.undoManager?.registerUndo(withTarget: canvasView) { cv in
                cv.drawing = oldDrawing
            }
            canvasView.undoManager?.setActionName(
                NSLocalizedString("Editor.StraightenLine", comment: "Undo action name for hold-to-straighten")
            )
            canvasView.drawing = newDrawing
            isStraightening = false

            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.prepare()
            haptic.impactOccurred()
        }


        /// Start observing the canvas's contentOffset and zoomScale via KVO so
        /// the page background (ruling) follows zoom and scroll.
        func observeCanvasScroll(_ canvas: PKCanvasView) {
            contentOffsetObservation = canvas.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                self?.syncBackgroundWithCanvas(sv)
            }
            zoomScaleObservation = canvas.observe(\.zoomScale, options: [.new]) { [weak self] sv, _ in
                self?.syncBackgroundWithCanvas(sv)
                self?.centerContentDuringZoom(sv)
            }
        }

        /// Positions and scales the page background to match the canvas content.
        ///
        /// The background view sits in the container (same coordinate space as
        /// the canvas viewport). To make it visually overlay the canvas content:
        ///
        /// - **Scale** by `zoomScale` so ruling lines scale with drawing strokes.
        /// - **Translate** to compensate for `contentOffset` so the background
        ///   pans with the content.
        ///
        /// The math: a content point `(px, py)` appears in the viewport at
        /// `(px * z − o.x, py * z − o.y)`. The view's transform is applied
        /// around its center, so we derive `tx`/`ty` to make the visual frame
        /// origin land at `(−o.x, −o.y)`.
        func syncBackgroundWithCanvas(_ scrollView: UIScrollView) {
            guard let bg = pageBackground else { return }
            let z = scrollView.zoomScale
            let o = scrollView.contentOffset
            let pw = bg.bounds.width
            let ph = bg.bounds.height
            let tx = -o.x + pw * (z - 1) / 2
            let ty = -o.y + ph * (z - 1) / 2

            let xform = CGAffineTransform(scaleX: z, y: z)
                .concatenating(CGAffineTransform(translationX: tx, y: ty))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bg.transform = xform
            pdfBackgroundView?.transform = xform
            // Keep object overlay canvases (shapes, attachments, widgets)
            // in sync with the PencilKit canvas zoom/scroll so objects
            // rendered in page-local coordinates don't drift from ink.
            shapeCanvas?.transform = xform
            attachmentCanvas?.transform = xform
            widgetCanvas?.transform = xform
            CATransaction.commit()
        }

        // MARK: - UIScrollViewDelegate (zoom centering)

        /// Centers the canvas content when zoomed out below 1× so the page
        /// stays centered on screen rather than pinning to the top-left corner.
        /// Also called from the zoomScale KVO observer so the centering logic
        /// fires reliably even when PKCanvasView does not forward
        /// `UIScrollViewDelegate` callbacks.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContentDuringZoom(scrollView)
            adaptiveEffectsEngine.zoomScale = scrollView.zoomScale
            // Zoom detent haptic + visual feedback (AGENT-23).
            interactionFeedback.updateZoom(scrollView.zoomScale, on: scrollView.layer)
            // Micro-bounce visual tick on detent entry (short-circuits on first match).
            let onDetent = InteractionFeedbackEngine.zoomDetents.first(where: { abs(scrollView.zoomScale - $0) < InteractionFeedbackEngine.detentTolerance }) != nil
            if onDetent && !wasOnZoomDetent {
                microInteractionEngine.playZoomDetentTick(on: scrollView.layer)
            }
            wasOnZoomDetent = onDetent
        }

        /// Adjusts content insets so the page stays centered when the scaled
        /// content is smaller than the viewport.
        private func centerContentDuringZoom(_ scrollView: UIScrollView) {
            let boundsSize  = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            // Horizontal centering: when scaled content is narrower than viewport
            let xInset = max(0, (boundsSize.width  - contentSize.width)  / 2)
            // Vertical centering: when scaled content is shorter than viewport
            let yInset = max(0, (boundsSize.height - contentSize.height) / 2)

            scrollView.contentInset = UIEdgeInsets(
                top: yInset, left: xInset,
                bottom: yInset, right: xInset
            )

            syncBackgroundWithCanvas(scrollView)
        }
    }
}

// MARK: - PencilActionDelegate

extension CanvasView.Coordinator: PencilActionDelegate {

    // MARK: Tool switching

    func pencilDidRequestSwitchToEraser() {
        guard let canvas = canvasRef else { return }
        if !(canvas.tool is PKEraserTool) {
            // Remember current inking tool before switching to eraser.
            previousInkingTool = canvas.tool
        }
        canvas.tool = toolStoreRef?.makeEraserTool() ?? {
            if #available(iOS 16.4, *) {
                return PKEraserTool(.bitmap, width: EraserSubType.standard.defaultWidth)
            }
            return PKEraserTool(.bitmap)
        }()
        // Interaction feedback for eraser engage (AGENT-23).
        interactionFeedback.play(.eraserEngage, on: canvas.layer)
    }

    func pencilDidRequestSwitchToPreviousTool() {
        guard let canvas = canvasRef else { return }
        if let previous = previousInkingTool {
            canvas.tool = previous
            previousInkingTool = nil
        } else {
            // No previous tool recorded — toggle from eraser to default pen.
            canvas.tool = PKInkingTool(.pen, color: .label, width: 2)
        }
        // Interaction feedback for eraser disengage (AGENT-23).
        interactionFeedback.play(.eraserDisengage, on: canvas.layer)
    }

    // MARK: Contextual palette

    func pencilDidRequestContextualPalette(at anchorPoint: CGPoint) {
        guard let canvas = canvasRef,
              let window = canvas.window else { return }
        // Convert from canvas coordinates to window coordinates.
        let windowPoint = canvas.convert(anchorPoint, to: window)
        ContextualPencilPaletteView.show(
            at: windowPoint,
            in: window,
            canvas: canvas,
            eraserType: toolStoreRef?.eraserSubType.eraserMode.pkEraserType ?? .vector
        )
    }

    // MARK: Undo / redo

    func pencilDidRequestUndo() {
        canvasRef?.undoManager?.undo()
        // Interaction feedback for undo (AGENT-23).
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.undo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: true)
        }
    }

    func pencilDidRequestRedo() {
        canvasRef?.undoManager?.redo()
        // Interaction feedback for redo (AGENT-23).
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.redo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: false)
        }
    }

    // MARK: Double-tap delete

    func pencilDidRequestDeleteLastStroke() {
        deleteLastStroke()
    }

    // MARK: Hover preview

    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        let isErasing = canvasRef?.tool is PKEraserTool
        if isErasing {
            // Show sized eraser ring; hide ghost-nib overlay.
            let sub   = toolStoreRef?.eraserSubType ?? .standard
            let width = toolStoreRef?.eraserWidth   ?? sub.defaultWidth
            eraserCursorOverlay?.update(position: position, subType: sub, eraserWidth: width)
            hoverOverlay?.update(position: nil, altitude: altitude, azimuth: azimuth)
        } else {
            // Sync the ghost-nib appearance with the current tool state on every hover
            // event.  This is cheap and ensures the nib reflects a colour/width change
            // made while the pencil was already hovering.
            if let ts = toolStoreRef {
                let personality = ts.activePersonality
                let info = HoverToolInfo(
                    tool: ts.activeTool,
                    color: ts.activeColor,
                    width: CGFloat(ts.activeWidth),
                    opacity: CGFloat(ts.activeOpacity),
                    widthMultiplier: CGFloat(personality?.widthMultiplier ?? 1.0),
                    showsAzimuthLine: personality?.usesTiltShading == true
                                   || personality?.usesBarrelRoll  == true,
                    eraserMode: ts.eraserMode
                )
                hoverOverlay?.configure(with: info)
            }
            // Show ghost-nib; hide eraser ring.
            hoverOverlay?.update(position: position, altitude: altitude, azimuth: azimuth)
            eraserCursorOverlay?.update(position: nil, subType: .standard, eraserWidth: 0)
        }
    }

    // MARK: Barrel-roll fountain pen (Apple Pencil Pro, iOS 17.5+)

    func pencilBarrelRollChanged(angle: CGFloat) {
        guard #available(iOS 17.5, *), let canvas = canvasRef else { return }
        guard let inkTool = canvas.tool as? PKInkingTool,
              inkTool.inkType == .fountainPen else { return }

        // Use the stable base width captured at stroke start (not the current
        // tool width, which drifts if we've already modulated once).
        guard let baseWidth = barrelRollBaseWidth else { return }

        // Don't modulate while between strokes — let PencilKit keep its
        // native barrel-roll behaviour for the initial stroke setup.
        guard isDrawing else { return }

        // Map barrel-roll angle to a width variation that mimics a calligraphic nib:
        // • Roll  0 (neutral)       → base width
        // • Roll ±π/2 (edge-on)     → ~30 % of base width (thin stroke)
        // • Roll  π  (flipped)      → base width again (symmetrical)
        let rollFactor   = (cos(angle) + 1) / 2            // 0.0 … 1.0
        let minWidth     = max(baseWidth * 0.3, 1.0)
        let maxWidth     = baseWidth * 1.8
        let targetWidth  = minWidth + rollFactor * (maxWidth - minWidth)
        let clampedWidth = min(max(targetWidth, 1), 20)    // sane bounds

        // Only update when the change is visually meaningful to avoid
        // rebuilding PKInkingTool on every micro-movement.
        let currentWidth = inkTool.width
        if abs(clampedWidth - currentWidth) > 0.8 {
            canvas.tool = PKInkingTool(.fountainPen, color: inkTool.color, width: clampedWidth)
        }
    }
}

// MARK: - Tool Snapshot

/// Lightweight, equatable snapshot of a PKTool's identity.
/// Used to avoid redundant `canvas.tool` assignments in `updateUIView` that
/// would reset PencilKit's pressure/tilt pipeline.
struct ToolSnapshot: Equatable {
    let kind: String       // "inking", "eraser", "lasso"
    let inkType: String?   // e.g. "pen", "pencil", "marker", "fountainPen"
    let colorHash: Int?
    let width: CGFloat?

    init(_ tool: PKTool) {
        if let ink = tool as? PKInkingTool {
            kind = "inking"
            inkType = ink.inkType.rawValue
            colorHash = ink.color.hash
            width = ink.width
        } else if tool is PKEraserTool {
            kind = "eraser"
            inkType = nil
            colorHash = nil
            width = nil
        } else {
            kind = "lasso"
            inkType = nil
            colorHash = nil
            width = nil
        }
    }
}

// MARK: - Shape Overlay View

/// Transparent UIView overlay that captures pan gestures when the shape tool is
/// active. Displays a dashed CAShapeLayer preview while the user drags, then
/// converts the finished gesture path into a PKStroke and calls onShapeDrawn.
final class ShapeOverlayView: UIView {
    var shapeType: ShapeType
    var strokeColor: UIColor { didSet { previewLayer.strokeColor = strokeColor.cgColor } }
    var strokeWidth: CGFloat  { didSet { previewLayer.lineWidth  = strokeWidth } }
    private let onShapeDrawn: (PKStroke) -> Void

    private let previewLayer = CAShapeLayer()
    private var startPoint: CGPoint = .zero

    init(
        shapeType: ShapeType,
        strokeColor: UIColor,
        strokeWidth: CGFloat,
        onShapeDrawn: @escaping (PKStroke) -> Void
    ) {
        self.shapeType   = shapeType
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.onShapeDrawn = onShapeDrawn
        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false

        previewLayer.fillColor      = UIColor.clear.cgColor
        previewLayer.strokeColor    = strokeColor.cgColor
        previewLayer.lineWidth      = strokeWidth
        previewLayer.lineDashPattern = [6, 4]
        previewLayer.isHidden       = true
        layer.addSublayer(previewLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            startPoint = point
            previewLayer.isHidden = false
        case .changed:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.path = makeBezierPath(from: startPoint, to: point).cgPath
            CATransaction.commit()
        case .ended:
            previewLayer.isHidden = true
            previewLayer.path     = nil
            onShapeDrawn(makeStroke(from: startPoint, to: point))
        default:
            previewLayer.isHidden = true
            previewLayer.path     = nil
        }
    }

    // MARK: Path Construction

    private func makeBezierPath(from: CGPoint, to: CGPoint) -> UIBezierPath {
        switch shapeType {
        case .line:
            let p = UIBezierPath(); p.move(to: from); p.addLine(to: to)
            return p
        case .rectangle:
            return UIBezierPath(rect: CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            ))
        case .circle:
            return UIBezierPath(ovalIn: CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            ))
        case .arrow:
            let p = UIBezierPath(); p.move(to: from); p.addLine(to: to)
            let angle   = atan2(to.y - from.y, to.x - from.x)
            let headLen = min(24, hypot(to.x - from.x, to.y - from.y) * 0.25)
            let left  = CGPoint(x: to.x - headLen * cos(angle - .pi / 6),
                                y: to.y - headLen * sin(angle - .pi / 6))
            let right = CGPoint(x: to.x - headLen * cos(angle + .pi / 6),
                                y: to.y - headLen * sin(angle + .pi / 6))
            p.move(to: to); p.addLine(to: left)
            p.move(to: to); p.addLine(to: right)
            return p
        }
    }

    // MARK: Stroke Construction

    private func makeStroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let ink    = PKInk(.pen, color: strokeColor)
        let points = samplePath(makeBezierPath(from: from, to: to), spacing: 3)

        // Ensure at least two points so PencilKit renders a visible stroke.
        let resolved = points.count >= 2 ? points : [from, to]

        let pkPoints = resolved.enumerated().map { i, pt in
            PKStrokePoint(
                location: pt,
                timeOffset: TimeInterval(i) * 0.005,
                size: CGSize(width: strokeWidth, height: strokeWidth),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let pkPath = PKStrokePath(controlPoints: pkPoints, creationDate: Date())
        return PKStroke(ink: ink, path: pkPath, transform: .identity, mask: nil)
    }

    /// Densely samples a UIBezierPath into evenly-spaced CGPoints.
    private func samplePath(_ bezier: UIBezierPath, spacing: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []
        var prev: CGPoint = .zero

        bezier.cgPath.applyWithBlock { (ptr: UnsafePointer<CGPathElement>) in
            let el = ptr.pointee
            switch el.type {
            case .moveToPoint:
                prev = el.points[0]; result.append(prev)

            case .addLineToPoint:
                let end = el.points[0]
                linearSample(from: prev, to: end, spacing: spacing, into: &result)
                prev = end

            case .addQuadCurveToPoint:
                let ctrl = el.points[0]; let end = el.points[1]
                let steps = max(4, Int(hypot(end.x - prev.x, end.y - prev.y) / spacing))
                for i in 1...steps {
                    let t: CGFloat = CGFloat(i) / CGFloat(steps)
                    let mt: CGFloat = 1 - t
                    let px: CGFloat = mt*mt*prev.x + 2*mt*t*ctrl.x + t*t*end.x
                    let py: CGFloat = mt*mt*prev.y + 2*mt*t*ctrl.y + t*t*end.y
                    result.append(CGPoint(x: px, y: py))
                }; prev = end

            case .addCurveToPoint:
                let c1 = el.points[0]; let c2 = el.points[1]; let end = el.points[2]
                let steps = max(8, Int(hypot(end.x - prev.x, end.y - prev.y) / spacing))
                for i in 1...steps {
                    let t: CGFloat = CGFloat(i) / CGFloat(steps); let mt: CGFloat = 1 - t
                    let px: CGFloat = mt*mt*mt*prev.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x
                    let py: CGFloat = mt*mt*mt*prev.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y
                    result.append(CGPoint(x: px, y: py))
                }; prev = end

            case .closeSubpath:
                if let first = result.first {
                    linearSample(from: prev, to: first, spacing: spacing, into: &result)
                    prev = first
                }

            @unknown default: break
            }
        }
        return result
    }

    private func linearSample(from: CGPoint, to: CGPoint, spacing: CGFloat, into result: inout [CGPoint]) {
        let dist  = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(dist / spacing))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            result.append(CGPoint(
                x: from.x + t * (to.x - from.x),
                y: from.y + t * (to.y - from.y)
            ))
        }
    }
}

// MARK: - Note flashcard creation sheet

/// Sheet presented from the note editor to create flashcards linked to the current note.
/// Users can pick an existing study set or create a new one, then add one or more cards.
struct NoteFlashcardSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var selectedSetID: UUID?
    @State private var showNewSetAlert = false
    @State private var newSetTitle = ""
    @State private var front = ""
    @State private var back = ""
    @State private var tagsText = ""
    @State private var cardsCreated = 0
    @FocusState private var frontFocused: Bool

    private var canSave: Bool {
        selectedSetID != nil &&
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pre-fill the back with the note's typed text if it's short enough to be useful.
    private var suggestedBack: String {
        let text = note.typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count <= 200 ? text : ""
    }

    var body: some View {
        NavigationStack {
            Form {
                // Study set picker
                Section {
                    if noteStore.studySets.isEmpty {
                        Button {
                            showNewSetAlert = true
                        } label: {
                            Label("Create a Study Set First", systemImage: "plus.circle")
                        }
                    } else {
                        Picker("Study Set", selection: $selectedSetID) {
                            Text("Select a set…").tag(nil as UUID?)
                            ForEach(noteStore.studySets) { set in
                                Text(set.title).tag(set.id as UUID?)
                            }
                        }

                        Button {
                            showNewSetAlert = true
                        } label: {
                            Label("New Set", systemImage: "plus")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Study Set")
                }

                // Card content
                Section("Front (Question)") {
                    TextEditor(text: $front)
                        .frame(minHeight: 70)
                        .focused($frontFocused)
                }

                Section("Back (Answer)") {
                    TextEditor(text: $back)
                        .frame(minHeight: 70)
                }

                Section {
                    TextField("Tags (comma separated)", text: $tagsText)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("e.g. chapter 1, key term")
                }

                // Summary
                if cardsCreated > 0 {
                    Section {
                        Label(
                            "\(cardsCreated) card\(cardsCreated == 1 ? "" : "s") created from this note",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Create Flashcard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Card") {
                        guard let setID = selectedSetID else { return }
                        let tags = tagsText.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        noteStore.addCard(
                            toSet: setID,
                            front: front.trimmingCharacters(in: .whitespacesAndNewlines),
                            back: back.trimmingCharacters(in: .whitespacesAndNewlines),
                            noteID: note.id,
                            tags: tags
                        )
                        cardsCreated += 1
                        // Clear for next card
                        front = ""
                        back = ""
                        frontFocused = true
                    }
                    .disabled(!canSave)
                }
            }
            .alert("New Study Set", isPresented: $showNewSetAlert) {
                TextField("Set name", text: $newSetTitle)
                    .submitLabel(.done)
                Button("Create") {
                    let t = newSetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        let newSet = noteStore.addStudySet(
                            title: t,
                            notebookID: note.notebookID
                        )
                        selectedSetID = newSet.id
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                // Auto-select the most recent study set linked to this notebook.
                if let notebookID = note.notebookID {
                    selectedSetID = noteStore.studySets
                        .first { $0.notebookID == notebookID }?.id
                }
                if selectedSetID == nil {
                    selectedSetID = noteStore.studySets.first?.id
                }
                // Pre-fill front with note title if non-empty
                if front.isEmpty, !note.title.isEmpty {
                    front = note.title
                }
                // Pre-fill back with typed text if short
                if back.isEmpty, !suggestedBack.isEmpty {
                    back = suggestedBack
                }
                frontFocused = true
            }
        }
    }
}

// MARK: - Page Overview Grid

/// Full-screen grid of page thumbnails shown via pinch-to-overview gesture or
/// the page indicator button. Tap a thumbnail to jump to that page.
///
/// Each page is rendered as a miniature `PKDrawing` snapshot on a background
/// that matches the note's canvas colour.
private struct PageOverviewGrid: View {
    let note: Note
    @Binding var currentPageIndex: Int
    let canvasBackground: UIColor
    let onDismiss: () -> Void

    @EnvironmentObject var noteStore: NoteStore

    /// Thumbnails are generated asynchronously — keyed by page index.
    @State private var thumbnails: [Int: UIImage] = [:]
    /// Page index pending deletion confirmation.
    @State private var pageToDelete: Int?
    /// Whether the delete confirmation alert is shown.
    @State private var showDeleteConfirmation = false

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            pageGridContent
                .navigationTitle("Pages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { pageOverviewToolbar }
                .alert("Delete Page?", isPresented: $showDeleteConfirmation) {
                    deletePageAlertActions
                } message: {
                    deletePageAlertMessage
                }
        }
    }

    // MARK: - Extracted subviews (type-checker decomposition)

    private var pageGridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<note.pageCount, id: \.self) { index in
                        draggablePageCell(index: index)
                    }
                }
                .padding(16)
            }
            .onAppear {
                proxy.scrollTo(currentPageIndex, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func draggablePageCell(index: Int) -> some View {
        pageCell(index: index)
            .id(index)
            .draggable(String(index)) {
                Text("Page \(index + 1)")
                    .font(.caption.bold())
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let sourceStr = items.first,
                      let source = Int(sourceStr),
                      source != index else { return false }
                noteStore.reorderPageInNote(noteID: note.id, from: source, to: index)
                if currentPageIndex == source {
                    currentPageIndex = index
                } else if source < currentPageIndex && index >= currentPageIndex {
                    currentPageIndex -= 1
                } else if source > currentPageIndex && index <= currentPageIndex {
                    currentPageIndex += 1
                }
                thumbnails.removeAll()
                return true
            }
    }

    @ToolbarContentBuilder
    private var pageOverviewToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { onDismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let newIndex = noteStore.addPage(to: note.id) {
                    currentPageIndex = newIndex
                    onDismiss()
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add page")
        }
    }

    @ViewBuilder
    private var deletePageAlertActions: some View {
        Button("Cancel", role: .cancel) { pageToDelete = nil }
        Button("Delete", role: .destructive) {
            if let page = pageToDelete {
                let wasOnDeletedPage = currentPageIndex == page
                noteStore.removePage(from: note.id, at: page)
                thumbnails.removeAll()
                if wasOnDeletedPage {
                    currentPageIndex = max(0, min(currentPageIndex, note.pageCount - 2))
                } else if page < currentPageIndex {
                    currentPageIndex -= 1
                }
                pageToDelete = nil
            }
        }
    }

    @ViewBuilder
    private var deletePageAlertMessage: some View {
        if let page = pageToDelete {
            Text("Page \(page + 1) will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Page cell

    @ViewBuilder
    private func pageCell(index: Int) -> some View {
        let isSelected = index == currentPageIndex

        Button {
            currentPageIndex = index
            onDismiss()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Background matching canvas colour
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: canvasBackground))

                    if let thumb = thumbnails[index] {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    } else {
                        // Placeholder while thumbnail renders
                        ProgressView()
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color(uiColor: .separator),
                            lineWidth: isSelected ? 3 : 1
                        )
                )
                .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 4 : 2)

                Text("Page \(index + 1)")
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button {
                currentPageIndex = index
                onDismiss()
            } label: {
                Label("Go to Page", systemImage: "arrow.right")
            }

            Button {
                if let newIdx = noteStore.duplicatePageInNote(noteID: note.id, pageIndex: index) {
                    thumbnails.removeAll()
                    currentPageIndex = newIdx
                }
            } label: {
                Label("Duplicate Page", systemImage: "doc.on.doc")
            }

            if note.pageCount > 1 {
                Divider()
                Button(role: .destructive) {
                    pageToDelete = index
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            }
        }
        .task(id: "\(note.id)-\(index)-\(note.pages.indices.contains(index) ? note.pages[index].count : 0)") {
            await generateThumbnail(for: index)
        }
    }

    // MARK: - Thumbnail generation

    /// Renders a miniature image of the page's PKDrawing off the main thread.
    private func generateThumbnail(for index: Int) async {
        guard note.pages.indices.contains(index) else { return }
        let data = note.pages[index]
        guard !data.isEmpty else {
            // Blank page — no thumbnail needed
            thumbnails[index] = nil
            return
        }

        // Capture screen scale on the main actor before entering the detached task.
        let screenScale = UIScreen.main.scale

        let image = await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data) else { return nil as UIImage? }
            let bounds = drawing.bounds
            guard !bounds.isEmpty else { return nil as UIImage? }

            // Expand bounds slightly to avoid clipping edge strokes.
            let padding: CGFloat = 20
            let renderRect = bounds.insetBy(dx: -padding, dy: -padding)

            // Scale to thumbnail size (max 240pt wide).
            let maxDimension: CGFloat = 240
            let scale = min(maxDimension / renderRect.width, maxDimension / renderRect.height, 1.0)

            return drawing.image(from: renderRect, scale: scale * screenScale)
        }.value

        if let image {
            thumbnails[index] = image
        }
    }
}
