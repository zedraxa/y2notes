import Foundation

// MARK: - Sync state

/// Overall sync connection state presented to the user.
enum GoogleDriveSyncState: Equatable {
    /// No Google account linked.
    case disconnected
    /// Auth tokens present, awaiting first sync or idle between syncs.
    case idle
    /// Actively uploading or downloading.
    case syncing(progress: Double)
    /// Last sync completed successfully at the given date.
    case synced(lastSync: Date)
    /// A recoverable error occurred (network timeout, quota, etc.).
    case error(String)
}

// MARK: - Auth tokens

/// Persisted OAuth 2.0 token pair. Stored in Keychain via `GoogleDriveAuthManager`.
struct GoogleDriveTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60) // refresh 60 s early
    }
}

// MARK: - Drive file metadata

/// Lightweight representation of a Google Drive file used during listing and sync.
struct DriveFileMetadata: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var mimeType: String
    var modifiedTime: Date
    var size: Int64?
    /// MD5 checksum provided by Drive for binary files.
    var md5Checksum: String?
}

// MARK: - Conflict strategy

/// Determines how a conflict between local and remote versions is resolved.
enum ConflictStrategy: String, Codable, CaseIterable, Identifiable {
    /// Local changes always win — the remote copy is overwritten.
    case localWins = "local_wins"
    /// Remote changes always win — the local copy is overwritten.
    case remoteWins = "remote_wins"
    /// Keep the version with the newer `modifiedAt` timestamp.
    case newerWins = "newer_wins"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localWins:  return "Keep Local"
        case .remoteWins: return "Keep Remote"
        case .newerWins:  return "Keep Newer"
        }
    }
}

// MARK: - Offline queue operation

/// A pending sync operation queued while offline. Persisted to disk so
/// operations survive app restarts and are replayed when connectivity returns.
struct OfflineOperation: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: OperationKind
    let resourceType: ResourceType
    /// Serialised payload (JSON-encoded model snapshot at queue time).
    let payload: Data
    let queuedAt: Date
    var retryCount: Int

    init(kind: OperationKind, resourceType: ResourceType, payload: Data) {
        self.id = UUID()
        self.kind = kind
        self.resourceType = resourceType
        self.payload = payload
        self.queuedAt = Date()
        self.retryCount = 0
    }

    enum OperationKind: String, Codable {
        case upload
        case delete
    }

    enum ResourceType: String, Codable {
        case notes
        case notebooks
        case sections
        case study
        case pdf
    }
}

// MARK: - Storage quota

/// Represents the user's Google Drive storage quota.
struct DriveStorageQuota: Equatable {
    /// Total storage limit in bytes (–1 if unlimited).
    var limitBytes: Int64
    /// Total bytes used across Drive, Gmail, and Photos.
    var usageBytes: Int64
    /// Bytes used specifically in Google Drive.
    var usageInDriveBytes: Int64
    /// Bytes used in Trash.
    var usageInDriveTrashBytes: Int64

    var usedFraction: Double {
        guard limitBytes > 0 else { return 0 }
        return Double(usageBytes) / Double(limitBytes)
    }
}

// MARK: - Paged file listing

/// A paginated result from the Drive Files API.
struct DrivePagedFileList {
    var files: [DriveFileMetadata]
    /// Token for fetching the next page. `nil` when there are no more results.
    var nextPageToken: String?
}

// MARK: - Breadcrumb entry

/// A lightweight entry representing a folder in the navigation stack.
struct DriveBreadcrumb: Identifiable, Equatable {
    let id: String   // Drive folder ID
    let name: String // Display name
}

// MARK: - Sync manifest

/// Per-resource metadata that tracks the last synced version so the engine can
/// detect local or remote changes since the last successful sync.
struct SyncManifestEntry: Identifiable, Codable, Equatable {
    /// Matches the local resource UUID (note, notebook, etc.).
    let id: UUID
    var resourceType: OfflineOperation.ResourceType
    /// Google Drive file ID for this resource, if uploaded.
    var driveFileID: String?
    /// Date of the last successful sync for this resource.
    var lastSyncedAt: Date?
    /// MD5 of the locally persisted JSON at last sync time, used for dirty detection.
    var lastSyncedMD5: String?
}

/// Root container for the sync manifest file.
struct SyncManifest: Codable {
    var entries: [SyncManifestEntry] = []
    var lastFullSyncDate: Date?
    /// Google Drive folder ID used as the Y2Notes backup root.
    var driveFolderID: String?
}

// MARK: - Backup snapshot

/// A timestamped backup snapshot uploaded to Google Drive.
struct BackupSnapshot: Identifiable, Codable {
    let id: UUID
    var driveFileID: String
    var createdAt: Date
    /// Human-readable label (e.g. "2026-04-02 01:48 — 12 notes, 3 notebooks").
    var label: String
    /// Byte size of the backup archive.
    var sizeBytes: Int64
}
