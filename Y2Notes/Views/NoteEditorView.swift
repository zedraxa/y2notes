import SwiftUI
import PencilKit

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
                onDrawingChanged: { data in
                    noteStore.updateDrawing(for: note.id, data: data)
                },
                onSaveRequested: {
                    noteStore.save()
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
                // Hide the badge after 2 s so it doesn't crowd the toolbar permanently.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showSavedBadge = false
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
/// Handles Apple Pencil, finger drawing, and gracefully runs without a Pencil.
///
/// - `backgroundColor`: canvas background colour provided by the active theme.
/// - `defaultInkColor`: contrasting ink colour applied when first creating the canvas,
///   ensuring strokes are visible regardless of the theme's canvas background.
private struct CanvasView: UIViewRepresentable {
    let noteID: UUID
    let drawingData: Data
    let backgroundColor: UIColor
    let defaultInkColor: UIColor
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        // Allow any input (finger + Apple Pencil); requires no special hardware.
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = true
        canvas.backgroundColor = backgroundColor

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

        // Become first responder so the tool picker appears automatically.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update canvas background when the theme changes.
        if uiView.backgroundColor != backgroundColor {
            uiView.backgroundColor = backgroundColor
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (Data) -> Void
        let onSaveRequested: () -> Void
        var toolPicker: PKToolPicker?
        private var debounceTimer: Timer?

        init(onDrawingChanged: @escaping (Data) -> Void, onSaveRequested: @escaping () -> Void) {
            self.onDrawingChanged = onDrawingChanged
            self.onSaveRequested = onSaveRequested
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

            // Debounce disk writes: flush 0.8 s after the last stroke.
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                self?.onSaveRequested()
            }
        }
    }
}

