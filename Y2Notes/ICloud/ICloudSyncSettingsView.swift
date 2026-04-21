import SwiftUI

// MARK: - ICloud Sync Status View

/// Compact iCloud sync status indicator for use in navigation bars or toolbars.
struct ICloudSyncStatusView: View {
    @EnvironmentObject var iCloudEngine: ICloudSyncEngine

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
        switch iCloudEngine.syncState {
        case .unavailable:
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
        switch iCloudEngine.syncState {
        case .unavailable:
            Text("iCloud unavailable")
                .foregroundStyle(.secondary)
        case .idle:
            Text("iCloud ready")
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

// MARK: - ICloud Sync Settings View

/// Full settings screen for iCloud Drive synchronization.
///
/// Surfaces per-domain toggles, conflict strategy picker, account status,
/// and manual sync / upload / download actions.
struct ICloudSyncSettingsView: View {
    @EnvironmentObject var iCloudEngine: ICloudSyncEngine
    @State private var showUploadConfirmation = false
    @State private var showDownloadConfirmation = false

    var body: some View {
        List {
            accountSection
            if iCloudEngine.isICloudAvailable {
                syncBehaviourSection
                domainsSection
                actionsSection
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { iCloudEngine.checkAvailability() }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            HStack {
                Image(systemName: iCloudEngine.isICloudAvailable ? "icloud.fill" : "icloud.slash")
                    .font(.title2)
                    .foregroundStyle(iCloudEngine.isICloudAvailable ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(iCloudEngine.isICloudAvailable ? "iCloud Drive" : "iCloud Unavailable")
                        .font(.headline)
                    Text(iCloudEngine.isICloudAvailable
                         ? "Connected — data syncs across your devices."
                         : "Sign in to iCloud in Settings and enable iCloud Drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ICloudSyncStatusView()
                    .environmentObject(iCloudEngine)
            }
        } header: {
            Text("Account")
        } footer: {
            if !iCloudEngine.isICloudAvailable {
                Text("Go to Settings → [Your Name] → iCloud → iCloud Drive and ensure it is enabled.")
            }
        }
    }

    // MARK: - Sync Behaviour

    private var syncBehaviourSection: some View {
        Section {
            Toggle("Auto-Sync", isOn: $iCloudEngine.autoSyncEnabled)
                .accessibilityLabel("Automatically sync to iCloud every 5 minutes and on app launch.")

            Picker("Conflict Strategy", selection: $iCloudEngine.conflictStrategy) {
                ForEach(ICloudConflictStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .accessibilityLabel("How to resolve conflicts between local and iCloud versions of the same file.")
        } header: {
            Text("Sync Behaviour")
        } footer: {
            Text("\"Keep Newer\" resolves conflicts by choosing the version with the most recent modification date.")
        }
    }

    // MARK: - Domains

    private var domainsSection: some View {
        Section {
            ForEach(ICloudSyncDomain.all) { domain in
                Toggle(isOn: Binding(
                    get: { iCloudEngine.isDomainEnabled(domain) },
                    set: { _ in iCloudEngine.toggleDomain(domain) }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(domain.displayName)
                            Text(domain.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: domain.systemImage)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .accessibilityLabel("\(domain.displayName). \(domain.description)")
            }
        } header: {
            Text("What to Sync")
        } footer: {
            Text("Preferences are synced via iCloud Key-Value Store (small values). All other domains use iCloud Drive file copying.")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                Task { await iCloudEngine.syncAll() }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    Text("Sync Now")
                }
            }
            .disabled(isSyncing)
            .accessibilityLabel("Sync all enabled domains with iCloud now.")

            Button {
                showUploadConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "icloud.and.arrow.up")
                    Text("Upload Local Data to iCloud")
                }
            }
            .disabled(isSyncing)
            .confirmationDialog(
                "Upload to iCloud?",
                isPresented: $showUploadConfirmation,
                titleVisibility: .visible
            ) {
                Button("Upload") { Task { await iCloudEngine.uploadToICloud() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All enabled local data will be copied to your iCloud Drive container. This is useful for the initial migration to iCloud sync.")
            }
            .accessibilityLabel("Copy all local data to iCloud Drive.")

            Button {
                showDownloadConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                    Text("Download from iCloud")
                }
            }
            .disabled(isSyncing)
            .confirmationDialog(
                "Download from iCloud?",
                isPresented: $showDownloadConfirmation,
                titleVisibility: .visible
            ) {
                Button("Download") { Task { await iCloudEngine.downloadFromICloud() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Data from iCloud will be merged into your local store using the \"\(iCloudEngine.conflictStrategy.displayName)\" strategy. Existing local files are backed up before overwriting.")
            }
            .accessibilityLabel("Merge iCloud data into the local store.")

            if case let .synced(date) = iCloudEngine.syncState {
                HStack {
                    Image(systemName: "checkmark.icloud")
                        .foregroundStyle(.green)
                    Text("Last synced \(date, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case let .error(message) = iCloudEngine.syncState {
                HStack {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Syncing copies JSON metadata and binary assets between local storage and your iCloud Drive container (iCloud.com.y2notes.app). Large files (PDFs, audio) are only synced when enabled in the domain list above.")
        }
    }

    private var isSyncing: Bool {
        if case .syncing = iCloudEngine.syncState { return true }
        return false
    }
}
