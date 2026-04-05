import SwiftUI

/// Persistent status chip that floats in the top-trailing corner of the editor
/// during an active audio recording.  Shows a pulsing red dot and elapsed time.
///
/// **Design**:
/// - `.ultraThinMaterial` capsule background matching the toolbar.
/// - Does NOT fade with `toolStore.toolbarOpacity` — always fully visible
///   so the user always knows recording is active during long writing sessions.
/// - Tap the chip to open the recordings list.
///
/// **Placement**: Overlaid in the NoteEditorView / NotebookReaderView as a
/// top-trailing aligned overlay, above the toolbar z-order.
struct RecordingIndicatorView: View {
    @ObservedObject var recordingStore: AudioRecordingStore
    var onTap: (() -> Void)?

    @State private var isPulsing = false

    var body: some View {
        if recordingStore.isRecording {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 6) {
                    // Pulsing red dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(isPulsing ? 1.0 : 0.6)

                    // Elapsed time
                    Text(recordingStore.formattedElapsedTime)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(Color(uiColor: .label))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
            .onDisappear {
                isPulsing = false
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .accessibilityLabel("Recording in progress, \(recordingStore.formattedElapsedTime)")
            .accessibilityHint("Tap to view recordings")
        }
    }
}
