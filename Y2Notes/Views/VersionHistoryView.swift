import SwiftUI

// MARK: - Version History View
//
// A sheet presenting a chronological list of snapshots for a note.
// Supports preview, full restore, single-page restore, and copy-to-new-note.

struct VersionHistoryView: View {
    @EnvironmentObject var noteStore: NoteStore

    let noteID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var snapshots: [NoteSnapshot] = []
    @State private var selectedSnapshot: NoteSnapshot?
    @State private var showRestoreConfirmation = false
    @State private var restoreMode: RestoreMode = .entireNote
    @State private var showRestoredToast = false
    @State private var restoredTimestamp: String = ""
    @State private var rowsAppeared = false

    enum RestoreMode {
        case entireNote
        case singlePage(Int)
        case copyToNew
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshots.isEmpty {
                    emptyState
                } else {
                    snapshotList
                }
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if showRestoredToast {
                    restoredToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            loadSnapshots()
            rowsAppeared = true
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .scaleEffect(rowsAppeared ? 1 : 0.5)
                .opacity(rowsAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: rowsAppeared)
            Text("No Version History")
                .font(.headline)
                .opacity(rowsAppeared ? 1 : 0)
                .offset(y: rowsAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.35).delay(0.1), value: rowsAppeared)
            Text("Versions are saved automatically as you edit. Check back after making changes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(rowsAppeared ? 1 : 0)
                .offset(y: rowsAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: rowsAppeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snapshotList: some View {
        List {
            ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                SnapshotRow(snapshot: snapshot)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedSnapshot = snapshot }
                    .swipeActions(edge: .leading) {
                        Button {
                            togglePin(snapshot)
                        } label: {
                            Label(
                                snapshot.isPinned ? "Unpin" : "Pin",
                                systemImage: snapshot.isPinned ? "pin.slash" : "pin"
                            )
                        }
                        .tint(.orange)
                    }
                    .opacity(rowsAppeared ? 1 : 0)
                    .offset(y: rowsAppeared ? 0 : 12)
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.8)
                            .delay(Double(index) * 0.05),
                        value: rowsAppeared
                    )
            }
        }
        .listStyle(.plain)
        .sheet(item: $selectedSnapshot) { snapshot in
            SnapshotDetailView(
                noteID: noteID,
                snapshot: snapshot,
                onRestore: { mode in
                    restoreMode = mode
                    showRestoreConfirmation = true
                }
            )
            .environmentObject(noteStore)
        }
        .confirmationDialog(
            "Restore Version",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            restoreActions
        } message: {
            Text("A backup of your current version will be created before restoring.")
        }
    }

    @ViewBuilder
    private var restoreActions: some View {
        if let snapshot = selectedSnapshot {
            Button("Restore Entire Note") {
                performRestore(snapshot: snapshot, mode: .entireNote)
            }
            if snapshot.changedPageIndices.count == 1,
               let pageIdx = snapshot.changedPageIndices.first {
                Button("Restore Page \(pageIdx + 1) Only") {
                    performRestore(snapshot: snapshot, mode: .singlePage(pageIdx))
                }
            }
            Button("Copy to New Note") {
                performRestore(snapshot: snapshot, mode: .copyToNew)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var restoredToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Restored to \(restoredTimestamp)")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func loadSnapshots() {
        snapshots = SnapshotStore.shared.snapshots(for: noteID)
    }

    private func togglePin(_ snapshot: NoteSnapshot) {
        SnapshotStore.shared.togglePin(noteID: noteID, snapshotID: snapshot.id)
        loadSnapshots()
    }

    private func performRestore(snapshot: NoteSnapshot, mode: RestoreMode) {
        guard let note = noteStore.notes.first(where: { $0.id == noteID }) else { return }

        // Create a pre-restore safety snapshot synchronously so it completes
        // before the restore overwrites the current state.
        _ = PerformanceConstraints.storageQueue.sync {
            SnapshotStore.shared.createSnapshot(
                for: note,
                dirtyPages: Set(0 ..< note.pages.count),
                trigger: .preRestore
            )
        }

        switch mode {
        case .entireNote:
            guard let restored = SnapshotStore.shared.reconstructNote(
                from: snapshot.id, noteID: noteID, currentNote: note
            ) else { return }
            noteStore.replaceNote(restored)

        case .singlePage(let pageIndex):
            guard let pageResult = SnapshotStore.shared.reconstructPage(
                from: snapshot.id, noteID: noteID, pageIndex: pageIndex
            ) else { return }
            noteStore.restorePage(
                noteID: noteID,
                pageIndex: pageIndex,
                data: pageResult.data,
                stickers: pageResult.stickers,
                shapes: pageResult.shapes,
                attachments: pageResult.attachments
            )

        case .copyToNew:
            guard let restored = SnapshotStore.shared.reconstructNote(
                from: snapshot.id, noteID: noteID, currentNote: note
            ) else { return }
            let copy = Note(
                title: "\(restored.title) (Restored)",
                createdAt: Date(),
                modifiedAt: Date(),
                pages: restored.pages,
                isFavorited: false,
                notebookID: restored.notebookID,
                sectionID: nil,
                sortOrder: 0,
                templateID: restored.templateID,
                pageType: restored.pageType,
                paperMaterial: restored.paperMaterial
            )
            noteStore.insertRestoredNote(copy)
        }

        // Show toast.
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        restoredTimestamp = formatter.localizedString(for: snapshot.createdAt, relativeTo: Date())
        selectedSnapshot = nil

        withAnimation(.easeInOut(duration: 0.3)) {
            showRestoredToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showRestoredToast = false
            }
        }

        // Reload snapshots to include the pre-restore backup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadSnapshots()
        }
    }
}

// MARK: - Snapshot Row

private struct SnapshotRow: View {
    let snapshot: NoteSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(relativeTime)
                        .font(.subheadline.weight(.medium))
                    if snapshot.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    triggerBadge
                }
                Text(snapshot.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: snapshot.createdAt, relativeTo: Date())
    }

    @ViewBuilder
    private var triggerBadge: some View {
        switch snapshot.trigger {
        case .manual:
            Text("Manual")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(.blue)
        case .preRestore:
            Text("Pre-restore")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
        case .preDestructive:
            Text("Backup")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.15), in: Capsule())
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}

// MARK: - Snapshot Detail View (preview + restore)

private struct SnapshotDetailView: View {
    @EnvironmentObject var noteStore: NoteStore
    let noteID: UUID
    let snapshot: NoteSnapshot
    let onRestore: (VersionHistoryView.RestoreMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header info
                VStack(spacing: 8) {
                    Text(snapshot.title)
                        .font(.headline)
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(snapshot.summary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(snapshot.totalPageCount) page\(snapshot.totalPageCount == 1 ? "" : "s") • \(formattedSize)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()

                Divider()

                // Page list showing which pages are in this snapshot
                List {
                    Section("Changed Pages") {
                        ForEach(snapshot.changedPageIndices, id: \.self) { pageIdx in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text("Page \(pageIdx + 1)")
                                Spacer()
                                if snapshot.changedPageIndices.count > 1 {
                                    Button("Restore") {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            onRestore(.singlePage(pageIdx))
                                        }
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Snapshot Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onRestore(.entireNote)
                            }
                        } label: {
                            Label("Restore Note", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onRestore(.copyToNew)
                            }
                        } label: {
                            Label("Copy to New", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: snapshot.createdAt)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(snapshot.dataSizeBytes), countStyle: .file)
    }
}
