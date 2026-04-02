import Foundation
import Combine
import CryptoKit
import UIKit

/// Orchestrates sync between NoteStore's local JSON files and Google Drive.
///
/// Design principles:
/// - **Local-first**: All reads come from the local store. Drive is a mirror, not the source of truth.
/// - **Non-destructive**: Local data is never overwritten without explicit user consent (import) or
///   a well-defined conflict strategy.
/// - **Offline-aware**: When offline, mutations are queued via `GoogleDriveOfflineQueue` and
///   replayed when connectivity returns.
/// - **Atomic**: Each file (notes, notebooks, sections, study) is synced as a complete JSON snapshot.
///   Partial object-level sync is intentionally avoided to keep the implementation simple and
///   corruption-resistant.
final class GoogleDriveSyncEngine: ObservableObject {

    // MARK: - Published state

    @Published private(set) var syncState: GoogleDriveSyncState = .disconnected
    @Published var conflictStrategy: ConflictStrategy {
        didSet { UserDefaults.standard.set(conflictStrategy.rawValue, forKey: "y2notes.drive.conflictStrategy") }
    }
    @Published var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: "y2notes.drive.autoSync") }
    }
    @Published private(set) var backupSnapshots: [BackupSnapshot] = []

    // MARK: - Dependencies

    let authManager: GoogleDriveAuthManager
    let offlineQueue: GoogleDriveOfflineQueue

    /// Reference to the local store. Set after init by the app entry point.
    weak var noteStore: NoteStore?

    // MARK: - Internal state

    private var manifest: SyncManifest
    private var syncCancellables = Set<AnyCancellable>()
    private var autoSyncTimer: Timer?

    /// Google Drive folder name used for Y2Notes data.
    private static let driveFolderName = "Y2Notes Backup"
    /// File names on Drive matching local JSON files.
    private static let notesFileName     = "y2notes_notes.json"
    private static let notebooksFileName = "y2notes_notebooks.json"
    private static let sectionsFileName  = "y2notes_sections.json"
    private static let studyFileName     = "y2notes_study.json"
    private static let manifestFileName  = "y2notes_sync_manifest.json"

    // MARK: - Init

    init(authManager: GoogleDriveAuthManager = GoogleDriveAuthManager()) {
        self.authManager    = authManager
        self.offlineQueue   = GoogleDriveOfflineQueue()
        self.manifest       = Self.loadManifest()

        let strategy = UserDefaults.standard.string(forKey: "y2notes.drive.conflictStrategy")
            .flatMap { ConflictStrategy(rawValue: $0) } ?? .newerWins
        self.conflictStrategy = strategy
        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: "y2notes.drive.autoSync")

        observeAuthState()
    }

    deinit {
        autoSyncTimer?.invalidate()
    }

    // MARK: - Auth observation

    private func observeAuthState() {
        authManager.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                guard let self else { return }
                if isAuth {
                    self.syncState = .idle
                    if self.autoSyncEnabled {
                        self.startAutoSync()
                    }
                } else {
                    self.syncState = .disconnected
                    self.stopAutoSync()
                }
            }
            .store(in: &syncCancellables)
    }

    // MARK: - Auto-sync timer

    private func startAutoSync() {
        stopAutoSync()
        // Sync every 5 minutes when auto-sync is active.
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.syncAll()
            }
        }
        autoSyncTimer?.tolerance = 30
        // Trigger an immediate sync on connect.
        Task { @MainActor in
            await syncAll()
        }
    }

    private func stopAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }

    // MARK: - Full sync (export local → Drive)

    /// Exports all local data files to Google Drive, creating the backup folder if necessary.
    /// This is the primary sync operation — a full push of the local-first source of truth.
    func syncAll() async {
        guard authManager.isAuthenticated else {
            syncState = .disconnected
            return
        }
        guard let token = await authManager.validAccessToken() else {
            syncState = .error("Unable to refresh Google credentials.")
            return
        }

        syncState = .syncing(progress: 0.0)

        do {
            // 1. Ensure Y2Notes folder exists on Drive.
            let folderID = try await GoogleDriveClient.ensureFolder(
                named: Self.driveFolderName,
                accessToken: token
            )
            manifest.driveFolderID = folderID
            syncState = .syncing(progress: 0.1)

            // 2. Upload each data file.
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

            let filesToSync: [(String, OfflineOperation.ResourceType)] = [
                (Self.notesFileName,     .notes),
                (Self.notebooksFileName, .notebooks),
                (Self.sectionsFileName,  .sections),
                (Self.studyFileName,     .study),
            ]

            for (i, (fileName, resourceType)) in filesToSync.enumerated() {
                let localURL = docsDir.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: localURL.path) else { continue }

                let localData = try Data(contentsOf: localURL)
                let localMD5 = md5String(localData)

                // Find existing manifest entry for this resource type.
                let existingEntry = manifest.entries.first { $0.resourceType == resourceType }

                // Skip upload if content hasn't changed since last sync.
                if let entry = existingEntry, entry.lastSyncedMD5 == localMD5 {
                    syncState = .syncing(progress: Double(i + 1) / Double(filesToSync.count + 1))
                    continue
                }

                let driveFileID = try await GoogleDriveClient.uploadFile(
                    name: fileName,
                    data: localData,
                    parentFolderID: folderID,
                    existingFileID: existingEntry?.driveFileID,
                    accessToken: token
                )

                // Update or insert manifest entry.
                let entryID = existingEntry?.id ?? UUID()
                let newEntry = SyncManifestEntry(
                    id: entryID,
                    resourceType: resourceType,
                    driveFileID: driveFileID,
                    lastSyncedAt: Date(),
                    lastSyncedMD5: localMD5
                )
                if let idx = manifest.entries.firstIndex(where: { $0.id == entryID }) {
                    manifest.entries[idx] = newEntry
                } else {
                    manifest.entries.append(newEntry)
                }

                syncState = .syncing(progress: Double(i + 1) / Double(filesToSync.count + 1))
            }

            // 3. Replay any queued offline operations.
            await replayOfflineQueue(token: token, folderID: folderID)

            // 4. Save manifest.
            manifest.lastFullSyncDate = Date()
            Self.saveManifest(manifest)

            syncState = .synced(lastSync: Date())

        } catch let error as GoogleDriveClientError {
            syncState = .error(error.localizedDescription ?? "Sync failed.")
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    // MARK: - Import from Drive

    /// Downloads all Y2Notes data files from Drive and merges them into the local store
    /// using the configured `conflictStrategy`.
    ///
    /// - Returns: `true` if data was imported, `false` if nothing was found on Drive.
    @discardableResult
    func importFromDrive() async -> Bool {
        guard let token = await authManager.validAccessToken(),
              let folderID = manifest.driveFolderID ?? (try? await GoogleDriveClient.ensureFolder(named: Self.driveFolderName, accessToken: token))
        else { return false }

        syncState = .syncing(progress: 0.0)

        do {
            let files = try await GoogleDriveClient.listFiles(
                inFolder: folderID,
                accessToken: token
            )

            guard !files.isEmpty else {
                syncState = .idle
                return false
            }

            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

            let targetFiles: [(String, OfflineOperation.ResourceType)] = [
                (Self.notesFileName,     .notes),
                (Self.notebooksFileName, .notebooks),
                (Self.sectionsFileName,  .sections),
                (Self.studyFileName,     .study),
            ]

            for (i, (fileName, resourceType)) in targetFiles.enumerated() {
                guard let driveFile = files.first(where: { $0.name == fileName }) else { continue }

                let remoteData = try await GoogleDriveClient.downloadFile(
                    fileID: driveFile.id,
                    accessToken: token
                )

                let localURL = docsDir.appendingPathComponent(fileName)
                let shouldOverwrite = resolveConflict(
                    localURL: localURL,
                    remoteModifiedTime: driveFile.modifiedTime,
                    remoteData: remoteData
                )

                if shouldOverwrite {
                    // Write remote data locally (with backup for safety).
                    let backupURL = localURL.appendingPathExtension("pre-import.bak")
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        try? FileManager.default.removeItem(at: backupURL)
                        try? FileManager.default.copyItem(at: localURL, to: backupURL)
                    }
                    try remoteData.write(to: localURL, options: .atomic)

                    // Update manifest.
                    let entryID = manifest.entries.first(where: { $0.resourceType == resourceType })?.id ?? UUID()
                    let entry = SyncManifestEntry(
                        id: entryID,
                        resourceType: resourceType,
                        driveFileID: driveFile.id,
                        lastSyncedAt: Date(),
                        lastSyncedMD5: md5String(remoteData)
                    )
                    if let idx = manifest.entries.firstIndex(where: { $0.id == entryID }) {
                        manifest.entries[idx] = entry
                    } else {
                        manifest.entries.append(entry)
                    }
                }

                syncState = .syncing(progress: Double(i + 1) / Double(targetFiles.count))
            }

            Self.saveManifest(manifest)

            // Reload local store from disk to pick up imported data.
            await MainActor.run {
                noteStore?.reloadFromDisk()
            }

            syncState = .synced(lastSync: Date())
            return true

        } catch {
            syncState = .error("Import failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Backup architecture

    /// Creates a timestamped full backup archive on Google Drive.
    /// The archive is a single JSON file containing all four data collections.
    func createBackup() async -> BackupSnapshot? {
        guard let token = await authManager.validAccessToken(),
              let folderID = manifest.driveFolderID
        else { return nil }

        syncState = .syncing(progress: 0.0)

        do {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

            // Collect all data into a single backup payload.
            var payload: [String: Data] = [:]
            for fileName in [Self.notesFileName, Self.notebooksFileName, Self.sectionsFileName, Self.studyFileName] {
                let url = docsDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    payload[fileName] = try Data(contentsOf: url)
                }
            }

            let backupData = try JSONEncoder().encode(payload)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let backupName = "Y2Notes_Backup_\(timestamp).json"

            syncState = .syncing(progress: 0.5)

            let driveFileID = try await GoogleDriveClient.uploadFile(
                name: backupName,
                data: backupData,
                parentFolderID: folderID,
                accessToken: token
            )

            let noteCount = noteStore?.notes.count ?? 0
            let nbCount   = noteStore?.notebooks.count ?? 0
            let snapshot = BackupSnapshot(
                id: UUID(),
                driveFileID: driveFileID,
                createdAt: Date(),
                label: "\(timestamp) — \(noteCount) notes, \(nbCount) notebooks",
                sizeBytes: Int64(backupData.count)
            )

            backupSnapshots.insert(snapshot, at: 0)
            saveBackupHistory()

            syncState = .synced(lastSync: Date())
            return snapshot

        } catch {
            syncState = .error("Backup failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Restores from a specific backup snapshot.
    func restoreFromBackup(_ snapshot: BackupSnapshot) async -> Bool {
        guard let token = await authManager.validAccessToken() else { return false }

        syncState = .syncing(progress: 0.0)

        do {
            let backupData = try await GoogleDriveClient.downloadFile(
                fileID: snapshot.driveFileID,
                accessToken: token
            )
            let payload = try JSONDecoder().decode([String: Data].self, from: backupData)

            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

            syncState = .syncing(progress: 0.5)

            // Write each file with pre-restore backup.
            for (fileName, data) in payload {
                let targetURL = docsDir.appendingPathComponent(fileName)
                let safetyBackup = targetURL.appendingPathExtension("pre-restore.bak")
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try? FileManager.default.removeItem(at: safetyBackup)
                    try? FileManager.default.copyItem(at: targetURL, to: safetyBackup)
                }
                try data.write(to: targetURL, options: .atomic)
            }

            // Reload the store from restored files.
            await MainActor.run {
                noteStore?.reloadFromDisk()
            }

            syncState = .synced(lastSync: Date())
            return true

        } catch {
            syncState = .error("Restore failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Offline queue replay

    private func replayOfflineQueue(token: String, folderID: String) async {
        let operations = offlineQueue.pendingOperations
        for op in operations {
            do {
                switch op.kind {
                case .upload:
                    let fileName = fileNameForResourceType(op.resourceType)
                    let existing = manifest.entries.first(where: { $0.resourceType == op.resourceType })
                    try await GoogleDriveClient.uploadFile(
                        name: fileName,
                        data: op.payload,
                        parentFolderID: folderID,
                        existingFileID: existing?.driveFileID,
                        accessToken: token
                    )
                case .delete:
                    if let driveID = String(data: op.payload, encoding: .utf8) {
                        try await GoogleDriveClient.deleteFile(fileID: driveID, accessToken: token)
                    }
                }
                offlineQueue.removeOperation(id: op.id)
            } catch {
                offlineQueue.incrementRetry(id: op.id)
                // Stop replay on auth errors; continue on transient errors.
                if case GoogleDriveClientError.unauthorized = error { break }
            }
        }
    }

    // MARK: - Conflict resolution

    private func resolveConflict(localURL: URL, remoteModifiedTime: Date, remoteData: Data) -> Bool {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return true // no local file → always import
        }
        switch conflictStrategy {
        case .localWins:
            return false
        case .remoteWins:
            return true
        case .newerWins:
            // Compare local file's modification date with remote.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
               let localModified = attrs[.modificationDate] as? Date {
                return remoteModifiedTime > localModified
            }
            return true
        }
    }

    // MARK: - Manifest persistence

    private static func manifestURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_sync_manifest.json")
    }

    private static func loadManifest() -> SyncManifest {
        let url = manifestURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(SyncManifest.self, from: data)
        else { return SyncManifest() }
        return manifest
    }

    static func saveManifest(_ manifest: SyncManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL(), options: .atomic)
    }

    // MARK: - Backup history persistence

    private static func backupHistoryURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_backup_history.json")
    }

    private func saveBackupHistory() {
        guard let data = try? JSONEncoder().encode(backupSnapshots) else { return }
        try? data.write(to: Self.backupHistoryURL(), options: .atomic)
    }

    func loadBackupHistory() {
        let url = Self.backupHistoryURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode([BackupSnapshot].self, from: data)
        else { return }
        backupSnapshots = history
    }

    // MARK: - Helpers

    private func md5String(_ data: Data) -> String {
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func fileNameForResourceType(_ type: OfflineOperation.ResourceType) -> String {
        switch type {
        case .notes:     return Self.notesFileName
        case .notebooks: return Self.notebooksFileName
        case .sections:  return Self.sectionsFileName
        case .study:     return Self.studyFileName
        case .pdf:       return "y2notes_pdfs.json"
        }
    }
}
