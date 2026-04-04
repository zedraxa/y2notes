import SwiftUI

/// Compact sync status indicator shown in the navigation bar.
/// Displays the current `GoogleDriveSyncState` with an appropriate icon and label.
struct GoogleDriveSyncStatusView: View {
    @EnvironmentObject var syncEngine: GoogleDriveSyncEngine

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
            statusLabel
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch syncEngine.syncState {
        case .disconnected:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
        case .idle:
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
        case .syncing:
            ProgressView()
                .controlSize(.mini)
        case .synced:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch syncEngine.syncState {
        case .disconnected:
            Text("Not connected")
                .foregroundStyle(.secondary)
        case .idle:
            Text("Drive ready")
                .foregroundStyle(.secondary)
        case .syncing(let progress):
            Text("Syncing \(Int(progress * 100))%")
                .foregroundStyle(.primary)
        case .synced(let date):
            Text("Synced \(date, style: .relative)")
                .foregroundStyle(.secondary)
        case .error(let message):
            Text(message)
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }
}

/// Full settings and connection management view for Google Drive integration.
struct GoogleDriveSettingsView: View {
    @EnvironmentObject var syncEngine: GoogleDriveSyncEngine
    @State private var showBackupConfirmation = false
    @State private var showRestoreSheet = false
    @State private var showSignOutConfirmation = false
    @State private var showImportConfirmation = false

    // swiftlint:disable:next function_body_length
    var body: some View {
        List {
            // MARK: - Account section
            Section {
                if syncEngine.authManager.isAuthenticated {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Google Drive")
                                .font(.headline)
                            if let email = syncEngine.authManager.userEmail {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        GoogleDriveSyncStatusView()
                            .environmentObject(syncEngine)
                    }
                } else {
                    Button {
                        startAuth()
                    } label: {
                        HStack {
                            Image(systemName: "link.badge.plus")
                            Text("Connect Google Drive")
                        }
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                if !syncEngine.authManager.isAuthenticated {
                    Text("Connect your Google account to back up notes and sync across devices. Y2Notes uses the Drive Files scope — it can only access files it creates.")
                }
            }

            if syncEngine.authManager.isAuthenticated {
                // MARK: - Sync section
                Section("Sync") {
                    Toggle("Auto-sync", isOn: $syncEngine.autoSyncEnabled)

                    Picker("Conflict strategy", selection: $syncEngine.conflictStrategy) {
                        ForEach(ConflictStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }

                    Button {
                        Task { await syncEngine.syncAll() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                        }
                    }
                    .disabled(isSyncing)

                    Button {
                        showImportConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import from Drive")
                        }
                    }
                    .disabled(isSyncing)
                    .confirmationDialog(
                        "Import from Google Drive?",
                        isPresented: $showImportConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Import") {
                            Task { await syncEngine.importFromDrive() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will download your notes from Google Drive. Conflicts will be resolved using the \"\(syncEngine.conflictStrategy.displayName)\" strategy.")
                    }

                    if syncEngine.offlineQueue.pendingCount > 0 {
                        HStack {
                            Image(systemName: "tray.full")
                                .foregroundStyle(.orange)
                            Text("\(syncEngine.offlineQueue.pendingCount) pending operations")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Backup section
                Section("Backups") {
                    Button {
                        showBackupConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive.badge.plus")
                            Text("Create Backup Now")
                        }
                    }
                    .disabled(isSyncing)
                    .confirmationDialog(
                        "Create a full backup?",
                        isPresented: $showBackupConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Back Up") {
                            Task { await syncEngine.createBackup() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("A timestamped snapshot of all your notes, notebooks, and study sets will be uploaded to Google Drive.")
                    }

                    if !syncEngine.backupSnapshots.isEmpty {
                        Button {
                            showRestoreSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Restore from Backup")
                            }
                        }
                        .sheet(isPresented: $showRestoreSheet) {
                            BackupRestoreSheet()
                                .environmentObject(syncEngine)
                        }
                    }

                    ForEach(syncEngine.backupSnapshots.prefix(3)) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.label)
                                    .font(.caption)
                                Text(snapshot.createdAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: snapshot.sizeBytes, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Sign out
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.minus")
                            Text("Disconnect Google Drive")
                        }
                    }
                    .confirmationDialog(
                        "Disconnect Google Drive?",
                        isPresented: $showSignOutConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Disconnect", role: .destructive) {
                            syncEngine.offlineQueue.clearAll()
                            syncEngine.authManager.signOut()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Your local notes will not be affected. Backups on Google Drive will remain.")
                    }
                }
            }
        }
        .navigationTitle("Google Drive")
        .onAppear {
            syncEngine.loadBackupHistory()
        }
    }

    private var isSyncing: Bool {
        if case .syncing = syncEngine.syncState { return true }
        return false
    }

    private func startAuth() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first
        else { return }
        syncEngine.authManager.startAuthFlow(anchor: window)
    }
}

/// Sheet listing available backup snapshots for restore.
struct BackupRestoreSheet: View {
    @EnvironmentObject var syncEngine: GoogleDriveSyncEngine
    @Environment(\.dismiss) private var dismiss
    @State private var restoring: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(syncEngine.backupSnapshots) { snapshot in
                    Button {
                        restoring = snapshot.id
                        Task {
                            let success = await syncEngine.restoreFromBackup(snapshot)
                            restoring = nil
                            if success { dismiss() }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.label)
                                    .font(.subheadline)
                                Text(snapshot.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: snapshot.sizeBytes, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if restoring == snapshot.id {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .disabled(restoring != nil)
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
