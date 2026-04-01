import SwiftUI
import PencilKit

/// Full-screen note editor: editable title + PencilKit canvas.
struct NoteEditorView: View {
    @EnvironmentObject var noteStore: NoteStore
    let note: Note

    @State private var titleText: String

    init(note: Note) {
        self.note = note
        _titleText = State(initialValue: note.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleField
            Divider()
            CanvasView(
                noteID: note.id,
                drawingData: note.drawingData,
                onDrawingChanged: { data in
                    noteStore.updateDrawing(for: note.id, data: data)
                },
                onSaveRequested: {
                    noteStore.save()
                }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            noteStore.save()
        }
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
private struct CanvasView: UIViewRepresentable {
    let noteID: UUID
    let drawingData: Data
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
        canvas.backgroundColor = .systemBackground

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
        // No-op: mutations flow through the Coordinator delegate.
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
