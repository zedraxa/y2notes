import SwiftUI
import PencilKit
import OSLog

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
    @Environment(\.undoManager) private var undoManager
    let note: Note

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

    /// Zero-based index of the currently displayed page.
    @State private var currentPageIndex = 0

    private let searchService = SearchService()

    init(note: Note) {
        self.note = note
        _titleText = State(initialValue: note.title)
        _typedTextContent = State(initialValue: note.typedText)
    }

    // MARK: - Notebook context

    /// The notebook this note belongs to (nil for unfiled notes).
    private var notebook: Notebook? {
        guard let id = note.notebookID else { return nil }
        return noteStore.notebooks.first { $0.id == id }
    }

    /// Page ruling style: note-level override → notebook setting → `.blank` fallback.
    private var effectivePageType: PageType {
        note.pageType ?? notebook?.pageType ?? .blank
    }

    /// Paper material: note-level override → notebook setting → `.standard` fallback.
    private var effectivePaperMaterial: PaperMaterial {
        note.paperMaterial ?? notebook?.paperMaterial ?? .standard
    }

    // MARK: - Effective theme

    private var effectiveTheme: AppTheme {
        note.themeOverride ?? themeStore.selectedTheme
    }

    private var effectiveDefinition: ThemeDefinition {
        effectiveTheme.definition
    }

    /// Canvas background blended with the paper material's tint colour.
    private var canvasBackgroundColor: UIColor {
        blendedBackground(
            base: effectiveDefinition.canvasBackground,
            tint: effectivePaperMaterial.pageTint
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                titleField
                if effectiveDefinition.canvasIsDark && !isTextMode {
                    contrastBanner
                }
                Divider()
                if !isTextMode {
                    DrawingToolbarView(toolStore: toolStore, inkStore: inkStore, onOpenInspector: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showAdvancedPanel.toggle()
                        }
                    })
                }
                if showFindBar {
                    findBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if isTextMode {
                    textLayer
                } else {
                    let safePageIndex: Int = {
                        guard !note.pages.isEmpty else { return 0 }
                        return min(currentPageIndex, note.pages.count - 1)
                    }()
                    let currentPageData = note.pages.indices.contains(safePageIndex)
                        ? note.pages[safePageIndex] : Data()

                    CanvasView(
                        noteID: note.id,
                        drawingData: currentPageData,
                        backgroundColor: canvasBackgroundColor,
                        defaultInkColor: effectiveDefinition.contrastingInkColor,
                        currentTool: inkStore.activePreset?.pkTool ?? toolStore.pkTool,
                        isShapeToolActive: toolStore.activeTool == .shape,
                        activeShapeType: toolStore.activeShapeType,
                        shapeColor: toolStore.activeColor,
                        shapeWidth: toolStore.activeWidth,
                        drawingPolicy: pencilOnlyDrawing ? .pencilOnly : .anyInput,
                        zoomResetTrigger: zoomResetTrigger,
                        pageType: effectivePageType,
                        paperMaterial: effectivePaperMaterial,
                        activeFX: inkStore.resolvedFX,
                        fxColor: inkStore.activePreset?.uiColor ?? toolStore.activeColor,
                        pageIndex: safePageIndex,
                        onDrawingChanged: { data in
                            noteStore.updateDrawing(for: note.id, pageIndex: safePageIndex, data: data)
                        },
                        onSaveRequested: {
                            noteStore.save()
                        },
                        onUndoStateChanged: { canUndoVal, canRedoVal in
                            canUndo = canUndoVal
                            canRedo = canRedoVal
                        },
                        onPageSwipe: { direction in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if direction > 0 {
                                    currentPageIndex = min(note.pageCount - 1, currentPageIndex + 1)
                                } else {
                                    currentPageIndex = max(0, currentPageIndex - 1)
                                }
                            }
                        },
                        onPinchToOverview: {
                            showPageOverview = true
                        }
                    )
                    // Force recreation on page change so makeUIView loads the new drawing.
                    .id("\(note.id)-\(safePageIndex)")
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                    .padding(.horizontal, 1)

                    // Page navigation bar — book-like experience
                    pageNavigationBar
                }
            }  // end VStack

            // Advanced tools inspector — slides in from the right
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
        }  // end ZStack
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showAdvancedPanel)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(duration: 0.25), value: showFindBar)
        .animation(.spring(duration: 0.25), value: isTextMode)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                saveStateIndicator
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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

                // Draw ↔ Type mode toggle.
                // "keyboard" switches to text mode; "pencil" returns to drawing mode.
                Button {
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
                    .accessibilityLabel("Reset zoom to 100%")

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
        }
        .onAppear {
            refreshUndoRedoState()
            toolStore.currentPaperMaterial = effectivePaperMaterial
        }
        .onDisappear {
            toolStore.currentPaperMaterial = .standard
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
                showSavedBadge = true
                let now = Date()
                badgeShownAt = now
                // Each rapid save updates `badgeShownAt`; only the last scheduled
                // callback will actually hide the badge, avoiding premature dismissal.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if badgeShownAt == now {
                        showSavedBadge = false
                    }
                }
            }
        }
        .onDisappear {
            flushTextNow()
            toolStore.currentPaperMaterial = .standard
            noteStore.save()
        }
        .sheet(isPresented: $showCreateFlashcard) {
            NoteFlashcardSheet(note: note)
        }
        .sheet(isPresented: $showPageOverview) {
            PageOverviewGrid(
                note: note,
                currentPageIndex: $currentPageIndex,
                canvasBackground: canvasBackgroundColor,
                onDismiss: { showPageOverview = false }
            )
        }
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
        Menu {
            // Paper type section
            Section("Paper Type") {
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
        } label: {
            Image(systemName: "doc.richtext")
                .accessibilityLabel("Page setup")
        }
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
                .accessibilityLabel("Saved")
        default:
            EmptyView()
        }
    }

    private func refreshUndoRedoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
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
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPageIndex = newIndex
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

private struct CanvasView: UIViewRepresentable {
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
    /// Called when a three-finger pinch gesture requests the page overview.
    let onPinchToOverview: (() -> Void)?

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

    func makeUIView(context: Context) -> UIView {
        let setupState = editorSignposter.beginInterval("CanvasSetup")
        editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - begin")

        let container = UIView()
        container.backgroundColor = backgroundColor
        container.clipsToBounds = true

        // ── Page background (ruling + paper tint, sits behind the canvas) ──────
        // Frame-based layout sized to the fixed page dimensions so the ruling
        // zooms and scrolls together with the PencilKit drawing content.
        let ps = Self.pageSize
        let pageBackground = PageBackgroundView(frame: CGRect(origin: .zero, size: ps))
        pageBackground.pageColor    = backgroundColor
        pageBackground.pageType     = pageType
        pageBackground.lineColor    = Self.rulingLineColor(for: backgroundColor)
        pageBackground.showGrain    = paperMaterial.hasGrainTexture
        pageBackground.isUserInteractionEnabled = false

        container.addSubview(pageBackground)
        context.coordinator.pageBackground = pageBackground

        // ── PencilKit canvas ─────────────────────────────────────────────────
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = drawingPolicy
        canvas.alwaysBounceVertical = true
        // Canvas is transparent so the page background shows through.
        canvas.backgroundColor = .clear
        canvas.tool = currentTool

        // Zoom/pan: PKCanvasView inherits UIScrollView zoom support.
        // 0.25× minimum lets users step back for a full-page view.
        // 5×   maximum provides fine-detail writing precision.
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.bouncesZoom = true

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

        // ── Apple Pencil interaction coordinator ─────────────────────────────
        let pencilCoordinator = PencilInteractionCoordinator()
        pencilCoordinator.delegate = context.coordinator
        pencilCoordinator.attach(to: canvas)
        context.coordinator.pencilCoordinator = pencilCoordinator
        context.coordinator.canvasRef = canvas

        // ── Ink effect engine (fire / sparkle / glitch / ripple) ────────────
        let engine = InkEffectEngine(tier: DeviceCapabilityTier.current)
        engine.configure(fx: activeFX, color: fxColor)
        engine.attach(to: container)
        context.coordinator.effectEngine = engine

        // ── Page gestures (two-finger swipe + three-finger pinch) ─────────
        // Two-finger swipe left/right to navigate pages — avoids conflict
        // with Apple Pencil drawing (single touch) and canvas zoom (pinch).
        let swipeLeft = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePageSwipe(_:))
        )
        swipeLeft.direction = .left
        swipeLeft.numberOfTouchesRequired = 2
        container.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePageSwipe(_:))
        )
        swipeRight.direction = .right
        swipeRight.numberOfTouchesRequired = 2
        container.addGestureRecognizer(swipeRight)

        // Three-finger pinch-in opens page overview grid.
        let pinchOverview = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinchToOverview(_:))
        )
        container.addGestureRecognizer(pinchOverview)
        context.coordinator.pinchOverviewGesture = pinchOverview

        // ── Book feel: page shadow ──────────────────────────────────────────
        container.layer.shadowColor   = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.12
        container.layer.shadowRadius  = 8
        container.layer.shadowOffset  = CGSize(width: 0, height: 2)

        // Seed coordinator state so the first updateUIView call does not misfire.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder so Apple Pencil is ready immediately.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            editorSignposter.endInterval("CanvasSetup", setupState)
            editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - complete")
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        // Sync container background colour when the theme/material changes.
        if uiView.backgroundColor != backgroundColor {
            uiView.backgroundColor = backgroundColor
        }

        // Sync page background (ruling view).
        if let bg = context.coordinator.pageBackground {
            if bg.pageColor != backgroundColor {
                bg.pageColor  = backgroundColor
                bg.lineColor  = Self.rulingLineColor(for: backgroundColor)
            }
            if bg.pageType != pageType {
                bg.pageType = pageType
            }
            let grainWanted = paperMaterial.hasGrainTexture
            if bg.showGrain != grainWanted {
                bg.showGrain = grainWanted
            }
            // Re-sync position/scale in case SwiftUI re-rendered while
            // the canvas was scrolled or zoomed.
            context.coordinator.syncBackgroundWithCanvas(canvas)
        }

        // Sync drawing policy when the user toggles the finger/pencil preference.
        if canvas.drawingPolicy != drawingPolicy {
            canvas.drawingPolicy = drawingPolicy
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

        // Zoom reset: animate to 1× when the trigger value flips.
        if context.coordinator.lastZoomResetTrigger != zoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            // Dispatch to avoid mutating scroll state mid-layout-pass.
            DispatchQueue.main.async {
                canvas.setZoomScale(1.0, animated: true)
                editorLogger.debug("[\(noteID, privacy: .public)] zoom reset to 1×")
            }
        }

        // Keep the undo state callback current (closures capture SwiftUI state by value).
        context.coordinator.onUndoStateChanged = onUndoStateChanged

        // Sync ink effect engine configuration when FX type or colour changes.
        if let engine = context.coordinator.effectEngine {
            engine.configure(fx: activeFX, color: fxColor)
        }
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

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
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
        /// Updated by updateUIView to always hold the freshest closure.
        var onUndoStateChanged: ((Bool, Bool) -> Void)?
        /// Tracks the last zoom-reset trigger seen so we only react to flips.
        var lastZoomResetTrigger: Bool = false
        private var debounceTimer: Timer?

        // Apple Pencil support
        var pencilCoordinator: PencilInteractionCoordinator?
        var hoverOverlay: PencilHoverOverlayView?
        weak var canvasRef: PKCanvasView?

        /// Ink effect engine that renders fire/sparkle/glitch/ripple overlays.
        var effectEngine: InkEffectEngine?

        /// Pinch gesture recognizer for page overview.
        var pinchOverviewGesture: UIPinchGestureRecognizer?

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

        // KVO observers that keep the page background in sync with canvas
        // scroll offset and zoom scale. Invalidated automatically on dealloc.
        private var contentOffsetObservation: NSKeyValueObservation?
        private var zoomScaleObservation: NSKeyValueObservation?

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

        // MARK: - Page gesture handlers

        /// Two-finger swipe handler for page navigation.
        @objc func handlePageSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard !isDrawing else { return }
            switch gesture.direction {
            case .left:
                onPageSwipe?(1)   // Next page
            case .right:
                onPageSwipe?(-1)  // Previous page
            default:
                break
            }
        }

        /// Three-finger pinch-in handler for page overview.
        @objc func handlePinchToOverview(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .ended else { return }
            // Only trigger on pinch-in (scale < 1) with 3+ fingers.
            if gesture.scale < 0.7 && gesture.numberOfTouches >= 2 {
                onPinchToOverview?()
            }
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
            // Capture base width for barrel-roll modulation at stroke start.
            if let inkTool = canvasView.tool as? PKInkingTool {
                barrelRollBaseWidth = inkTool.width
            }
            // Notify effect engine of stroke start for fire/sparkle/glitch overlays.
            // At stroke-begin the new stroke hasn't been committed to the drawing
            // yet, so we use the viewport center as a reasonable start point.
            // The next onStrokeUpdated call will snap the emitter to the real nib.
            if let engine = effectEngine {
                let center = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
                engine.onStrokeBegan(at: center)
            }
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = false
            barrelRollBaseWidth = nil
            // Notify effect engine of stroke end for ripple / fire cooldown.
            if let engine = effectEngine {
                let lastStroke = canvasView.drawing.strokes.last
                let point = lastStroke?.path.last.map {
                    viewportPoint(from: CGPoint(x: $0.location.x, y: $0.location.y), in: canvasView)
                } ?? CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
                engine.onStrokeEnded(at: point)
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            editorSignposter.emitEvent("DrawingChanged")

            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

            // Feed latest stroke point to the effect engine for fire/sparkle tracking.
            // Convert from PKDrawing content coordinates to the overlay's viewport
            // coordinates so particles appear at the correct on-screen position.
            if let engine = effectEngine {
                let lastStroke = canvasView.drawing.strokes.last
                if let lastPoint = lastStroke?.path.last {
                    let vp = viewportPoint(
                        from: CGPoint(x: lastPoint.location.x, y: lastPoint.location.y),
                        in: canvasView
                    )
                    engine.onStrokeUpdated(at: vp)
                }
            }

            // Report undo/redo availability directly from the canvas's undo manager.
            // PKCanvasView inherits UIResponder.undoManager which traverses the responder
            // chain — the same manager PencilKit registers stroke actions against.
            let um = canvasView.undoManager
            onUndoStateChanged?(um?.canUndo ?? false, um?.canRedo ?? false)

            // Debounce disk writes: flush 0.8 s after the last stroke.
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                editorSignposter.emitEvent("DrawingSaved")
                self?.onSaveRequested()
            }
        }

        // MARK: - Canvas scroll / zoom → background sync

        /// Start observing the canvas's contentOffset and zoomScale via KVO so
        /// the page background (ruling) follows zoom and scroll.
        func observeCanvasScroll(_ canvas: PKCanvasView) {
            contentOffsetObservation = canvas.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                self?.syncBackgroundWithCanvas(sv)
            }
            zoomScaleObservation = canvas.observe(\.zoomScale, options: [.new]) { [weak self] sv, _ in
                self?.syncBackgroundWithCanvas(sv)
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

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bg.transform = CGAffineTransform(scaleX: z, y: z)
                .concatenating(CGAffineTransform(translationX: tx, y: ty))
            CATransaction.commit()
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
        canvas.tool = PKEraserTool(.vector)
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
            canvas: canvas
        )
    }

    // MARK: Undo / redo

    func pencilDidRequestUndo() {
        canvasRef?.undoManager?.undo()
    }

    func pencilDidRequestRedo() {
        canvasRef?.undoManager?.redo()
    }

    // MARK: Hover preview

    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        hoverOverlay?.update(position: position, altitude: altitude, azimuth: azimuth)
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

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(0..<note.pageCount, id: \.self) { index in
                            pageCell(index: index)
                                .id(index)
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    proxy.scrollTo(currentPageIndex, anchor: .center)
                }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        .task(id: note.pages.indices.contains(index) ? note.pages[index].hashValue : 0) {
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
            let targetSize = CGSize(
                width: ceil(renderRect.width * scale),
                height: ceil(renderRect.height * scale)
            )

            return drawing.image(from: renderRect, scale: scale * UIScreen.main.scale)
        }.value

        if let image {
            thumbnails[index] = image
        }
    }
}
