import Combine
import Foundation

// MARK: - SyncProvider

/// Framework-agnostic protocol for cloud sync operations.
///
/// Abstracts the Google Drive sync engine so that consumers (including
/// non-SwiftUI modules) can observe sync state and trigger sync actions
/// through Combine publishers and async methods.
protocol SyncProvider: AnyObject {

    // MARK: - Reactive state

    var syncStatePublisher: AnyPublisher<GoogleDriveSyncState, Never> { get }
    var backupSnapshotsPublisher: AnyPublisher<[BackupSnapshot], Never> { get }

    // MARK: - Current values

    var syncState: GoogleDriveSyncState { get }
    var conflictStrategy: ConflictStrategy { get set }
    var autoSyncEnabled: Bool { get set }
    var backupSnapshots: [BackupSnapshot] { get }

    // MARK: - Sync actions

    func syncAll() async
    func importFromDrive() async -> Bool
    func createBackup() async -> BackupSnapshot?
    func restoreFromBackup(_ snapshot: BackupSnapshot) async -> Bool
    func loadBackupHistory()
}
