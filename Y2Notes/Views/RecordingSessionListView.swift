import SwiftUI

/// Session browser sheet that lists all recorded audio sessions.
///
/// **Pattern**: Follows `StickerLibraryView` — NavigationStack with toolbar
/// Close button, list with swipe-to-delete and rename.
///
/// Tap a session to enter playback mode (wires into AudioTimelineLinkingController).
/// Swipe-left to delete.  Long-press to rename.
struct RecordingSessionListView: View {
    @ObservedObject var recordingStore: AudioRecordingStore
    @Environment(\.dismiss) private var dismiss

    @State private var renamingSessionID: UUID?
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var sessionToDelete: UUID?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if recordingStore.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Rename Recording", isPresented: $showRenameAlert) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if let id = renamingSessionID {
                        recordingStore.renameSession(id, to: renameText)
                    }
                }
            } message: {
                Text("Enter a new name for this recording.")
            }
            .confirmationDialog(
                "Delete Recording",
                isPresented: Binding(
                    get: { sessionToDelete != nil },
                    set: { if !$0 { sessionToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = sessionToDelete {
                        recordingStore.deleteSession(id)
                    }
                    sessionToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this recording? This action cannot be undone.")
            }
        }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionList: some View {
        List {
            ForEach(recordingStore.sessions) { session in
                sessionRow(session)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            sessionToDelete = session.id
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            renamingSessionID = session.id
                            renameText = session.title
                            showRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            renamingSessionID = session.id
                            renameText = session.title
                            showRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            sessionToDelete = session.id
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Session Row

    @ViewBuilder
    private func sessionRow(_ session: AudioSession) -> some View {
        HStack(spacing: 12) {
            // Waveform icon
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDuration(session.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.quaternary)

                    Text(formattedDate(session.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityLabel("\(session.title), \(formattedDuration(session.duration))")
        .accessibilityHint("Tap to play this recording")
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("No recordings yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap the microphone button in the toolbar to start recording.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Formatting

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
