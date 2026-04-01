import SwiftUI
import PencilKit
import OSLog

// MARK: - Performance instrumentation

/// Human-readable editor lifecycle messages — visible in Console.app.
private let editorLogger = Logger(subsystem: "com.y2notes.app", category: "editor")

/// Instruments-visible signposts for canvas setup, drawing changes, and save flushes.
private let editorSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "editor.perf")

// MARK: - NoteEditorView

/// Full-screen note editor: editable title + PencilKit canvas.
struct NoteEditorView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var themeStore: ThemeStore
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

    init(note: Note) {
        self.note = note
        _titleText = State(initialValue: note.title)
    }

    // MARK: - Effective theme

    /// The theme that governs this note's canvas.
    /// A per-note override takes precedence over the global app theme.
    private var effectiveTheme: AppTheme {
        note.themeOverride ?? themeStore.selectedTheme
    }

    private var effectiveDefinition: ThemeDefinition {
        effectiveTheme.definition
    }

    var body: some View {
        VStack(spacing: 0) {
            titleField
            if effectiveDefinition.canvasIsDark {
                contrastBanner
            }
            Divider()
            CanvasView(
                noteID: note.id,
                drawingData: note.drawingData,
                backgroundColor: effectiveDefinition.canvasBackground,
                defaultInkColor: effectiveDefinition.contrastingInkColor,
                drawingPolicy: pencilOnlyDrawing ? .pencilOnly : .anyInput,
                zoomResetTrigger: zoomResetTrigger,
                onDrawingChanged: { data in
                    noteStore.updateDrawing(for: note.id, data: data)
                },
                onSaveRequested: {
                    noteStore.save()
                },
                onUndoStateChanged: { canUndoVal, canRedoVal in
                    canUndo = canUndoVal
                    canRedo = canRedoVal
                }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                saveStateIndicator
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                noteThemeMenu

                // Finger / Pencil drawing policy toggle.
                // When pencil-only mode is active the icon is a filled pencil tip;
                // tapping it re-enables finger drawing (shows hand+pencil icon).
                Button {
                    pencilOnlyDrawing.toggle()
                } label: {
                    Image(systemName: pencilOnlyDrawing ? "pencil.tip" : "hand.and.pencil")
                }
                // Labels describe the *action* the button performs, not the current state.
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
        .onAppear {
            refreshUndoRedoState()
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
            noteStore.save()
        }
    }

    // MARK: - Per-note theme menu

    /// Compact toolbar menu for overriding the theme on this note only.
    private var noteThemeMenu: some View {
        Menu {
            // "Use app theme" option — clears any override.
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

    // MARK: - Contrast banner

    /// Thin informational strip shown when the canvas background is dark,
    /// reminding users to use a light ink colour for visibility.
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
            // Single-parameter onChange is the correct form for iOS 16 (deployment target).
            // The two-parameter form requires iOS 17+; a future agent can migrate once the
            // minimum deployment target is raised.
            .onChange(of: titleText) { newValue in
                noteStore.updateTitle(for: note.id, title: newValue)
            }
    }
}

// MARK: - PencilKit canvas bridge

/// UIViewRepresentable wrapper around PKCanvasView with PKToolPicker.
///
/// Features
/// - Finger vs Pencil drawing policy: controlled by `drawingPolicy`.
///   `.pencilOnly` — Apple Pencil draws; finger pans/zooms (recommended for handwriting).
///   `.anyInput`   — both finger and Pencil draw (accessible default).
/// - Zoom/pan: pinch-to-zoom from 0.25× to 5×; zoom-reset via `zoomResetTrigger`.
/// - Performance: `OSSignposter` intervals for canvas setup; events for drawing changes
///   and save flushes — all visible in Instruments → os_signpost.
/// - Undo/redo state: reports (canUndo, canRedo) from the canvas's own undo manager
///   after every drawing change via `onUndoStateChanged`.
private struct CanvasView: UIViewRepresentable {
    let noteID: UUID
    let drawingData: Data
    let backgroundColor: UIColor
    let defaultInkColor: UIColor
    /// Controls whether finger touches draw or pan/zoom the canvas.
    let drawingPolicy: PKCanvasViewDrawingPolicy
    /// Flip this value to trigger an animated reset to 1× zoom scale.
    let zoomResetTrigger: Bool
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void
    /// Called after each stroke with updated (canUndo, canRedo) from the canvas undo manager.
    let onUndoStateChanged: ((Bool, Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let setupState = editorSignposter.beginInterval("CanvasSetup")
        editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - begin")

        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = drawingPolicy
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = backgroundColor

        // Zoom/pan: PKCanvasView inherits UIScrollView zoom support.
        // 0.25× minimum lets users step back for a full-page view.
        // 5×   maximum provides fine-detail writing precision.
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.bouncesZoom = true

        // Seed a contrasting default inking tool so strokes are visible on first use.
        canvas.tool = PKInkingTool(.pen, color: defaultInkColor, width: 2)

        // Restore previously saved drawing, if any.
        if !drawingData.isEmpty, let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }

        // Attach the tool picker — it floats above the canvas on iPad.
        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        context.coordinator.toolPicker = picker

        // Seed coordinator state so the first updateUIView call does not misfire.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder so the tool picker appears automatically.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            editorSignposter.endInterval("CanvasSetup", setupState)
            editorLogger.debug("[\(noteID, privacy: .public)] canvas setup - complete")
        }

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Sync background colour when the theme changes.
        if uiView.backgroundColor != backgroundColor {
            uiView.backgroundColor = backgroundColor
        }

        // Sync drawing policy when the user toggles the finger/pencil preference.
        if uiView.drawingPolicy != drawingPolicy {
            uiView.drawingPolicy = drawingPolicy
        }

        // Zoom reset: animate to 1× when the trigger value flips.
        if context.coordinator.lastZoomResetTrigger != zoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            // Dispatch to avoid mutating scroll state mid-layout-pass.
            DispatchQueue.main.async {
                uiView.setZoomScale(1.0, animated: true)
                editorLogger.debug("[\(noteID, privacy: .public)] zoom reset to 1×")
            }
        }

        // Keep the undo state callback current (closures capture SwiftUI state by value).
        context.coordinator.onUndoStateChanged = onUndoStateChanged
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (Data) -> Void
        let onSaveRequested: () -> Void
        /// Updated by updateUIView to always hold the freshest closure.
        var onUndoStateChanged: ((Bool, Bool) -> Void)?
        var toolPicker: PKToolPicker?
        /// Tracks the last zoom-reset trigger seen so we only react to flips.
        var lastZoomResetTrigger: Bool = false
        private var debounceTimer: Timer?

        init(onDrawingChanged: @escaping (Data) -> Void, onSaveRequested: @escaping () -> Void) {
            self.onDrawingChanged = onDrawingChanged
            self.onSaveRequested = onSaveRequested
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            editorSignposter.emitEvent("DrawingChanged")

            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

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
    }
}

