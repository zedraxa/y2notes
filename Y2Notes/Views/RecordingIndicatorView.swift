import SwiftUI

/// Persistent status chip that floats in the top-trailing corner of the editor
/// during an active audio recording.  Shows a pulsing red dot, live audio level
/// bars, and elapsed time.
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

                    // Live audio level bars
                    audioLevelBars

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
            .accessibilityLabel(
                NSLocalizedString("Recording.InProgress", comment: "")
                + ", \(recordingStore.formattedElapsedTime)"
            )
            .accessibilityHint(NSLocalizedString("Recording.TapToViewList", comment: ""))
        }
    }

    // MARK: - Audio Level Bars

    /// Three small bars whose height tracks the normalised audio level.
    private var audioLevelBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                let barLevel = barHeight(for: index)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red)
                    .frame(width: 2, height: barLevel)
                    .animation(.easeOut(duration: 0.12), value: barLevel)
            }
        }
        .frame(height: 12)
    }

    /// Returns a height (3…12 pt) for each bar based on the current audio level
    /// with slight offsets per bar index for a staggered wave look.
    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(recordingStore.audioLevel)
        let offsets: [CGFloat] = [0.0, 0.15, -0.1]
        let adjusted = min(1, max(0, level + offsets[index]))
        return 3 + adjusted * 9 // 3…12 pt range
    }
}
