import Foundation

// MARK: - ICloud Sync State

/// Overall iCloud sync state presented to the user.
enum ICloudSyncState: Equatable {
    /// iCloud Drive is not available — the user has not signed in or has disabled iCloud Drive.
    case unavailable
    /// iCloud is available and configured, no sync is currently running.
    case idle
    /// A sync operation is in progress.
    case syncing(progress: Double)
    /// The last sync completed successfully at the given date.
    case synced(lastSync: Date)
    /// A recoverable error occurred.
    case error(String)
}

// MARK: - Conflict Strategy

/// Determines how a conflict between the local and iCloud versions of a file is resolved.
enum ICloudConflictStrategy: String, Codable, CaseIterable, Identifiable {
    /// Keep the version with the newer filesystem modification date.
    case newerWins = "newer_wins"
    /// Local changes always win — the iCloud copy is overwritten.
    case localWins = "local_wins"
    /// iCloud changes always win — the local copy is overwritten.
    case remoteWins = "remote_wins"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newerWins:  return "Keep Newer"
        case .localWins:  return "Keep Local"
        case .remoteWins: return "Keep iCloud"
        }
    }
}

// MARK: - Sync Domain

/// Identifies a logical grouping of data that can be individually enabled or disabled for sync.
struct ICloudSyncDomain: Identifiable, Equatable {
    let id: String
    let displayName: String
    let systemImage: String
    /// Human-readable description of what this domain contains.
    let description: String

    static let notes = ICloudSyncDomain(
        id: "notes",
        displayName: "Notes & Notebooks",
        systemImage: "note.text",
        description: "All notes, notebooks, sections, and handwriting data."
    )
    static let study = ICloudSyncDomain(
        id: "study",
        displayName: "Study & Flashcards",
        systemImage: "graduationcap",
        description: "Study sets, flashcards, progress, and review history."
    )
    static let pdfs = ICloudSyncDomain(
        id: "pdfs",
        displayName: "PDFs & Annotations",
        systemImage: "doc.richtext",
        description: "Imported PDFs with per-page PencilKit annotations."
    )
    static let documents = ICloudSyncDomain(
        id: "documents",
        displayName: "Imported Documents",
        systemImage: "folder",
        description: "Imported DOCX, EPUB, PPTX, Keynote, and ODP files."
    )
    static let stickers = ICloudSyncDomain(
        id: "stickers",
        displayName: "Custom Stickers",
        systemImage: "star.square.on.square",
        description: "User-imported sticker images and favourites."
    )
    static let settings = ICloudSyncDomain(
        id: "settings",
        displayName: "Preferences & Settings",
        systemImage: "gear",
        description: "App preferences, theme, and tool defaults."
    )

    static let all: [ICloudSyncDomain] = [.notes, .study, .pdfs, .documents, .stickers, .settings]
}

// MARK: - Sync Manifest

/// Root container for the per-device iCloud sync manifest.
/// Tracks the last-synced modification date for each file so the engine can
/// detect changes since the last successful sync.
struct ICloudSyncManifest: Codable {
    var entries: [String: ICloudSyncManifestEntry] = [:]
    var lastFullSyncDate: Date?
    /// Stable device identifier used to prevent a device from overwriting its own uploads.
    var deviceIdentifier: String = UIDeviceIdentifier.current
}

/// Per-file tracking entry inside the manifest.
struct ICloudSyncManifestEntry: Codable {
    /// Date of the last successful sync for this file.
    var lastSyncedAt: Date
    /// Modification date of the local file at the time of the last sync.
    var localModDateAtSync: Date
    /// Modification date of the iCloud file at the time of the last sync.
    var remoteModDateAtSync: Date
}

// MARK: - Device Identifier

private enum UIDeviceIdentifier {
    /// Returns a stable, device-scoped identifier stored in UserDefaults.
    /// This is not the IDFV — it is a randomly generated UUID persisted on first launch.
    static var current: String {
        let key = "y2notes.icloud.deviceID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

// MARK: - Sync File Map

/// Maps each sync domain to the list of relative paths (within Documents) that belong to it.
enum ICloudSyncFileMap {
    /// JSON / database data files — always synced as part of their domain.
    static let filesByDomain: [String: [String]] = [
        ICloudSyncDomain.notes.id: [
            "y2notes_notes.json",
            "y2notes_notebooks.json",
            "y2notes_sections.json",
            "y2notes_bookmarks.json",
            "y2notes.db",
        ],
        ICloudSyncDomain.study.id: [
            "y2notes_study.json",
        ],
        ICloudSyncDomain.pdfs.id: [
            "y2notes_pdfs.json",
        ],
        ICloudSyncDomain.documents.id: [
            "imported_documents.json",
        ],
        ICloudSyncDomain.stickers.id: [
            "Stickers/custom_stickers.json",
            "Stickers/favorites.json",
            "Stickers/recents.json",
        ],
    ]

    /// Directories whose entire contents are synced as part of their domain.
    static let directoriesByDomain: [String: [String]] = [
        ICloudSyncDomain.pdfs.id:       ["PDFNotes"],
        ICloudSyncDomain.documents.id:  ["ImportedDocs"],
        ICloudSyncDomain.stickers.id:   ["Stickers/CustomStickers"],
        ICloudSyncDomain.notes.id:      ["NoteMedia", "AudioClips", "Scans"],
    ]
}
