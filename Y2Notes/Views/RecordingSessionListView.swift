import SwiftUI

/// Session browser sheet that lists all recorded audio sessions with inline
/// playback controls.
///
/// **Pattern**: Follows `StickerLibraryView` — NavigationStack with toolbar
/// Close button, list with swipe-to-delete and rename.
///
/// Tap a session to begin playback with an inline progress bar and
/// play/pause/seek controls. Swipe-left to delete. Long-press to rename.
struct RecordingSessionListView: View {
    @ObservedObject var recordingStore: AudioRecordingStore
    @Environment(\.dismiss) private var dismiss

    @State private var renamingSessionID: UUID?
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var sessionToDelete: UUID?
    /// Timeline events loaded for the currently playing session.
    /// Used to render tick marks on the scrubber.
    @State private var playingEvents: [TimelineEvent] = []

    private let selectionFeedback = UISelectionFeedbackGenerator()

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
            .navigationTitle(NSLocalizedString("Recording.ListTitle", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Common.Close", comment: "")) { dismiss() }
                }
            }
            .alert(
                NSLocalizedString("Recording.RenameTitle", comment: ""),
                isPresented: $showRenameAlert
            ) {
                TextField(NSLocalizedString("Recording.RenameField", comment: ""), text: $renameText)
                Button(NSLocalizedString("Common.Cancel", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("Common.Save", comment: "")) {
                    if let id = renamingSessionID {
                        recordingStore.renameSession(id, to: renameText)
                    }
                }
            } message: {
                Text(NSLocalizedString("Recording.RenameMessage", comment: ""))
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
        .onDisappear {
            // Don't stop playback when sheet dismisses — let it continue.
        }
        // Load timeline events whenever the playing session changes so
        // the scrubber can render page-change and stroke tick marks.
        .task(id: recordingStore.playingSession?.id) {
            guard let session = recordingStore.playingSession else {
                playingEvents = []
                return
            }
            playingEvents = recordingStore.loadEvents(for: session.id)
        }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionList: some View {
        List {
            // Now-playing section
            if let playing = recordingStore.playingSession {
                Section {
                    nowPlayingRow(playing)
                }
            }

            // All sessions section
            Section {
                ForEach(recordingStore.sessions) { session in
                    sessionRow(session)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if recordingStore.playingSession?.id == session.id {
                                    recordingStore.stopPlayback()
                                }
                                recordingStore.deleteSession(session.id)
                            } label: {
                                Label(
                                    NSLocalizedString("Common.Delete", comment: ""),
                                    systemImage: "trash"
                                )
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                renamingSessionID = session.id
                                renameText = session.title
                                showRenameAlert = true
                            } label: {
                                Label(
                                    NSLocalizedString("Recording.Rename", comment: ""),
                                    systemImage: "pencil"
                                )
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                renamingSessionID = session.id
                                renameText = session.title
                                showRenameAlert = true
                            } label: {
                                Label(
                                    NSLocalizedString("Recording.Rename", comment: ""),
                                    systemImage: "pencil"
                                )
                            }
                            Button {
                                shareSession(session)
                            } label: {
                                Label(
                                    NSLocalizedString("Recording.Share", comment: ""),
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                            Button(role: .destructive) {
                                if recordingStore.playingSession?.id == session.id {
                                    recordingStore.stopPlayback()
                                }
                                recordingStore.deleteSession(session.id)
                            } label: {
                                Label(
                                    NSLocalizedString("Common.Delete", comment: ""),
                                    systemImage: "trash"
                                )
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Now Playing Row

    @ViewBuilder
    private func nowPlayingRow(_ session: AudioSession) -> some View {
        VStack(spacing: 10) {
            // Title + controls
            HStack(spacing: 12) {
                // Waveform icon with playing indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(NSLocalizedString("Recording.NowPlaying", comment: ""))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.red)
                }

                Spacer()

                // Play / Pause
                Button {
                    selectionFeedback.selectionChanged()
                    recordingStore.togglePlayback(session: session)
                } label: {
                    Image(systemName: recordingStore.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    recordingStore.isPlaying
                        ? NSLocalizedString("Recording.Pause", comment: "")
                        : NSLocalizedString("Recording.Play", comment: "")
                )

                // Stop
                Button {
                    recordingStore.stopPlayback()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Recording.Stop", comment: ""))
            }

            // Progress bar
            VStack(spacing: 4) {
                // Scrubber
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(Color(uiColor: .systemGray4))
                            .frame(height: 4)

                        // Event tick marks drawn in a single Canvas pass for efficiency.
                        // Page events appear in orange, stroke/other events in gray.
                        // Rendered between track and fill so the red fill overlaps played marks.
                        if !playingEvents.isEmpty && recordingStore.playbackDuration > 0 {
                            let inverseDuration = 1.0 / recordingStore.playbackDuration
                            Canvas { context, size in
                                for event in playingEvents {
                                    let x = size.width * (event.offset * inverseDuration)
                                    let color: Color = event.kind == .page
                                        ? Color.orange.opacity(0.85)
                                        : Color(uiColor: .systemGray2).opacity(0.7)
                                    let rect = CGRect(x: x - 1, y: 0, width: 2, height: size.height)
                                    let path = Path(roundedRect: rect, cornerRadius: 1)
                                    context.fill(path, with: .color(color))
                                }
                            }
                            .allowsHitTesting(false)
                        }

                        // Fill
                        Capsule()
                            .fill(Color.red)
                            .frame(
                                width: geo.size.width * recordingStore.playbackProgress,
                                height: 4
                            )
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                let target = fraction * recordingStore.playbackDuration
                                recordingStore.seekPlayback(to: target)
                            }
                    )
                }
                .frame(height: 10)

                // Time labels
                HStack {
                    Text(recordingStore.formattedPlaybackPosition)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(recordingStore.formattedPlaybackRemaining)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Session Row

    @ViewBuilder
    private func sessionRow(_ session: AudioSession) -> some View {
        Button {
            selectionFeedback.selectionChanged()
            recordingStore.togglePlayback(session: session)
        } label: {
            HStack(spacing: 12) {
                // Waveform icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: playingIconName(for: session))
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                }

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

                Image(systemName: playingIconName(for: session))
                    .font(.system(size: 22))
                    .foregroundStyle(.red)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.title), \(formattedDuration(session.duration))")
        .accessibilityHint("Tap to play this recording")
    }

    /// Icon name for the play/pause indicator on a session row.
    private func playingIconName(for session: AudioSession) -> String {
        if recordingStore.playingSession?.id == session.id && recordingStore.isPlaying {
            return "pause.circle.fill"
        }
        return "play.circle.fill"
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.tertiary)
            Text(NSLocalizedString("Recording.EmptyTitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("Recording.EmptyHint", comment: ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sharing

    private func shareSession(_ session: AudioSession) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        let url = dir.appendingPathComponent("\(session.id.uuidString).m4a")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            // Present from topmost presented VC so the sheet doesn't hide behind.
            var top = root
            while let presented = top.presentedViewController { top = presented }
            activityVC.popoverPresentationController?.sourceView = top.view
            top.present(activityVC, animated: true)
        }
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
