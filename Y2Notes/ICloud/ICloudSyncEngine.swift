import Foundation
import Combine
import UIKit
import os

private let iCloudLogger = Logger(subsystem: "com.y2notes", category: "ICloudSyncEngine")

// MARK: - ICloudSyncEngine

/// Orchestrates bidirectional sync between the app's local Documents directory and
/// an iCloud Drive ubiquitous container.
///
/// Design principles:
/// - **Local-first**: The local store is always the source of truth for reading.
///   iCloud is a mirror that propagates changes across the user's devices.
/// - **Non-destructive**: A backup copy is written before any local file is overwritten
///   with iCloud data.
/// - **Conflict-aware**: Conflicts are resolved using the configured `conflictStrategy`
///   (defaults to newer-wins based on filesystem modification dates).
/// - **Offline-tolerant**: The engine silently skips sync when iCloud is unavailable
///   and retries on the next foreground event.
/// - **Domain-granular**: Each sync domain (notes, study, PDFs, …) can be individually
///   enabled or disabled.
@MainActor
final class ICloudSyncEngine: ObservableObject {

    // MARK: - Published state

    @Published private(set) var syncState: ICloudSyncState = .unavailable
    @Published private(set) var isICloudAvailable: Bool = false

    @Published var conflictStrategy: ICloudConflictStrategy {
        didSet { UserDefaults.standard.set(conflictStrategy.rawValue, forKey: Keys.conflictStrategy) }
    }
    @Published var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: Keys.autoSync) }
    }

    /// Per-domain enable/disable toggles.  Keys match `ICloudSyncDomain.id`.
    @Published var enabledDomains: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(enabledDomains), forKey: Keys.enabledDomains)
        }
    }

    // MARK: - Dependencies (set by ServiceContainer after init)

    weak var noteStore: NoteStore?
    weak var pdfStore: PDFStore?
    weak var documentStore: DocumentStore?

    // MARK: - Private state

    private var metadataQuery: NSMetadataQuery?
    private var autoSyncTimer: Timer?
    private var remoteChangePendingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var manifest: ICloudSyncManifest = ICloudSyncManifest()

    // MARK: - Constants

    private enum Keys {
        static let conflictStrategy = "y2notes.icloud.conflictStrategy"
        static let autoSync         = "y2notes.icloud.autoSync"
        static let enabledDomains   = "y2notes.icloud.enabledDomains"
    }

    /// The iCloud container identifier.  Must match the entitlement in the provisioning profile.
    private static let containerID = "iCloud.com.y2notes.app"
    private static let manifestFileName = "y2notes_icloud_manifest.json"
    private static let backupSuffix = "icloud-pre-sync.bak"
    private static let autoSyncInterval: TimeInterval = 300  // 5 minutes

    // MARK: - Init

    init() {
        let strategy = UserDefaults.standard.string(forKey: Keys.conflictStrategy)
            .flatMap { ICloudConflictStrategy(rawValue: $0) } ?? .newerWins
        self.conflictStrategy = strategy
        // Use object(forKey:) so we can distinguish an explicit `false` from a missing key;
        // default to `true` so auto-sync is on from first launch.
        self.autoSyncEnabled = UserDefaults.standard.object(forKey: Keys.autoSync) as? Bool ?? true

        let stored = UserDefaults.standard.stringArray(forKey: Keys.enabledDomains)
        if let stored {
            self.enabledDomains = Set(stored)
        } else {
            // Enable all domains by default.
            self.enabledDomains = Set(ICloudSyncDomain.all.map(\.id))
        }

        checkAvailability()
        loadManifest()
        setupLifecycleObservers()
    }

    deinit {
        autoSyncTimer?.invalidate()
        remoteChangePendingTimer?.invalidate()
        stopMetadataQuery()
    }

    // MARK: - Availability check

    /// Updates `isICloudAvailable` and `syncState` based on whether iCloud Drive is
    /// accessible.  Called on init and each time the app becomes active.
    func checkAvailability() {
        let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)
        let available = url != nil
        isICloudAvailable = available
        if !available {
            syncState = .unavailable
            stopMetadataQuery()
            stopAutoSync()
        } else if case .unavailable = syncState {
            syncState = .idle
            if autoSyncEnabled { startAutoSync() }
            startMetadataQuery()
        }
    }

    // MARK: - Public API

    /// Performs a full bidirectional sync: uploads changed local files to iCloud,
    /// then downloads any newer iCloud files to local.
    func syncAll() async {
        guard isICloudAvailable else {
            syncState = .unavailable
            return
        }
        guard let containerURL = iCloudDocumentsURL() else {
            syncState = .error("iCloud container is not accessible.")
            return
        }

        syncState = .syncing(progress: 0.0)
        iCloudLogger.info("iCloud sync started.")

        do {
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)

            let enabledIDs = enabledDomains
            let domains = ICloudSyncDomain.all.filter { enabledIDs.contains($0.id) }
            let totalSteps = Double(domains.count) * 2 + 1
            var step = 0.0

            for domain in domains {
                // Upload local → iCloud
                try await uploadDomain(domain, containerURL: containerURL)
                step += 1
                syncState = .syncing(progress: step / totalSteps)

                // Download iCloud → local (if newer)
                try await downloadDomain(domain, containerURL: containerURL)
                step += 1
                syncState = .syncing(progress: step / totalSteps)
            }

            // Sync settings via NSUbiquitousKeyValueStore if enabled.
            if enabledDomains.contains(ICloudSyncDomain.settings.id) {
                NSUbiquitousKeyValueStore.default.synchronize()
            }

            manifest.lastFullSyncDate = Date()
            saveManifest()
            syncState = .synced(lastSync: Date())
            iCloudLogger.info("iCloud sync completed successfully.")

        } catch {
            iCloudLogger.error("iCloud sync failed: \(error.localizedDescription, privacy: .public)")
            syncState = .error(error.localizedDescription)
        }
    }

    /// Forces a download-only pass from iCloud.  Used for manual "pull from iCloud" actions.
    func downloadFromICloud() async {
        guard isICloudAvailable, let containerURL = iCloudDocumentsURL() else {
            syncState = .unavailable; return
        }

        syncState = .syncing(progress: 0)
        let enabledIDs = enabledDomains
        let domains = ICloudSyncDomain.all.filter { enabledIDs.contains($0.id) }

        do {
            for domain in domains {
                try await downloadDomain(domain, containerURL: containerURL)
            }
            manifest.lastFullSyncDate = Date()
            saveManifest()
            syncState = .synced(lastSync: Date())
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    /// Forces an upload-only pass to iCloud.  Used for the initial migration of
    /// existing local data to iCloud.
    func uploadToICloud() async {
        guard isICloudAvailable, let containerURL = iCloudDocumentsURL() else {
            syncState = .unavailable; return
        }

        syncState = .syncing(progress: 0)
        let enabledIDs = enabledDomains

        do {
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            let domains = ICloudSyncDomain.all.filter { enabledIDs.contains($0.id) }
            for domain in domains {
                try await uploadDomain(domain, containerURL: containerURL)
            }
            manifest.lastFullSyncDate = Date()
            saveManifest()
            syncState = .synced(lastSync: Date())
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    /// Checks whether a particular domain is enabled for sync.
    func isDomainEnabled(_ domain: ICloudSyncDomain) -> Bool {
        enabledDomains.contains(domain.id)
    }

    /// Toggles a sync domain on or off.
    func toggleDomain(_ domain: ICloudSyncDomain) {
        if enabledDomains.contains(domain.id) {
            enabledDomains.remove(domain.id)
        } else {
            enabledDomains.insert(domain.id)
        }
    }

    // MARK: - Upload

    private func uploadDomain(_ domain: ICloudSyncDomain, containerURL: URL) async throws {
        let docsDir = localDocumentsURL()

        // Sync individual files.
        if let files = ICloudSyncFileMap.filesByDomain[domain.id] {
            for relativePath in files {
                let localURL  = docsDir.appendingPathComponent(relativePath)
                let remoteURL = containerURL.appendingPathComponent(relativePath)
                guard FileManager.default.fileExists(atPath: localURL.path) else { continue }
                try await copyFile(from: localURL, to: remoteURL, direction: .upload)
            }
        }

        // Sync directories.
        if let dirs = ICloudSyncFileMap.directoriesByDomain[domain.id] {
            for dir in dirs {
                let localDir  = docsDir.appendingPathComponent(dir)
                let remoteDir = containerURL.appendingPathComponent(dir)
                guard FileManager.default.fileExists(atPath: localDir.path) else { continue }
                try await syncDirectory(localDir: localDir, remoteDir: remoteDir, direction: .upload)
            }
        }
    }

    // MARK: - Download

    private func downloadDomain(_ domain: ICloudSyncDomain, containerURL: URL) async throws {
        let docsDir = localDocumentsURL()

        if let files = ICloudSyncFileMap.filesByDomain[domain.id] {
            for relativePath in files {
                let remoteURL = containerURL.appendingPathComponent(relativePath)
                let localURL  = docsDir.appendingPathComponent(relativePath)
                guard FileManager.default.fileExists(atPath: remoteURL.path) else { continue }

                // Trigger iCloud download if the file is only a placeholder.
                try? FileManager.default.startDownloadingUbiquitousItem(at: remoteURL)

                if shouldOverwriteLocal(localURL: localURL, remoteURL: remoteURL) {
                    try safeOverwriteLocal(localURL: localURL, with: remoteURL)
                }
            }
        }

        if let dirs = ICloudSyncFileMap.directoriesByDomain[domain.id] {
            for dir in dirs {
                let localDir  = docsDir.appendingPathComponent(dir)
                let remoteDir = containerURL.appendingPathComponent(dir)
                guard FileManager.default.fileExists(atPath: remoteDir.path) else { continue }
                try await syncDirectory(localDir: localDir, remoteDir: remoteDir, direction: .download)
            }
        }

        // Reload data stores so in-memory state reflects any newly downloaded files.
        noteStore?.reloadFromDisk()
        if domain.id == ICloudSyncDomain.pdfs.id      { pdfStore?.reloadFromDisk() }
        if domain.id == ICloudSyncDomain.documents.id  { documentStore?.reloadFromDisk() }
    }

    // MARK: - Directory sync

    private enum SyncDirection { case upload, download }

    private func syncDirectory(localDir: URL, remoteDir: URL, direction: SyncDirection) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: localDir, withIntermediateDirectories: true)

        switch direction {
        case .upload:
            let localFiles = (try? fm.contentsOfDirectory(at: localDir, includingPropertiesForKeys: nil)) ?? []
            for file in localFiles {
                let dest = remoteDir.appendingPathComponent(file.lastPathComponent)
                try await copyFile(from: file, to: dest, direction: .upload)
            }
        case .download:
            let remoteFiles = (try? fm.contentsOfDirectory(at: remoteDir, includingPropertiesForKeys: nil)) ?? []
            for file in remoteFiles {
                try? fm.startDownloadingUbiquitousItem(at: file)
                let dest = localDir.appendingPathComponent(file.lastPathComponent)
                if shouldOverwriteLocal(localURL: dest, remoteURL: file) {
                    try safeOverwriteLocal(localURL: dest, with: file)
                }
            }
        }
    }

    // MARK: - File copy helpers

    private func copyFile(from source: URL, to dest: URL, direction: SyncDirection) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        if direction == .upload {
            // For uploads: overwrite iCloud copy if local is newer or iCloud copy doesn't exist.
            if fm.fileExists(atPath: dest.path) {
                let localMod  = modDate(of: source)
                let remoteMod = modDate(of: dest)
                guard let lm = localMod, let rm = remoteMod, lm > rm else { return }
            }
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        }
    }

    private func shouldOverwriteLocal(localURL: URL, remoteURL: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: remoteURL.path) else { return false }
        guard fm.fileExists(atPath: localURL.path) else { return true }

        switch conflictStrategy {
        case .localWins:
            return false
        case .remoteWins:
            return true
        case .newerWins:
            guard let localMod  = modDate(of: localURL),
                  let remoteMod = modDate(of: remoteURL)
            else { return false }
            return remoteMod > localMod
        }
    }

    private func safeOverwriteLocal(localURL: URL, with remoteURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Backup existing local file before overwriting.
        if fm.fileExists(atPath: localURL.path) {
            let backupURL = localURL.appendingPathExtension(Self.backupSuffix)
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: localURL, to: backupURL)
            try fm.removeItem(at: localURL)
        }
        try fm.copyItem(at: remoteURL, to: localURL)

        let entry = ICloudSyncManifestEntry(
            lastSyncedAt: Date(),
            localModDateAtSync: modDate(of: localURL) ?? Date(),
            remoteModDateAtSync: modDate(of: remoteURL) ?? Date()
        )
        manifest.entries[localURL.lastPathComponent] = entry
    }

    // MARK: - URL helpers

    /// Returns the iCloud ubiquitous Documents URL, or `nil` if iCloud is not available.
    func iCloudDocumentsURL() -> URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID) else {
            return nil
        }
        return base.appendingPathComponent("Documents")
    }

    private func localDocumentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func modDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - NSMetadataQuery (remote change monitoring)

    private func startMetadataQuery() {
        guard metadataQuery == nil else { return }
        let query = NSMetadataQuery()
        query.notificationBatchingInterval = 1.5
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMetadataQueryUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMetadataQueryUpdate),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        query.start()
        metadataQuery = query
    }

    private func stopMetadataQuery() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    @objc private func handleMetadataQueryUpdate(_ notification: Notification) {
        guard autoSyncEnabled, isICloudAvailable else { return }
        // Debounce: cancel any in-flight download and wait for the burst to settle
        // before triggering a full download pass.  `metadataQuery.notificationBatchingInterval`
        // already coalesces notifications; this timer adds an extra 2-second settle window.
        remoteChangePendingTimer?.invalidate()
        remoteChangePendingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.metadataQuery?.disableUpdates()
            Task { await self.downloadFromICloud() }
            self.metadataQuery?.enableUpdates()
        }
    }

    // MARK: - Auto-sync timer

    private func startAutoSync() {
        stopAutoSync()
        autoSyncTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoSyncInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.syncAll() }
        }
        autoSyncTimer?.tolerance = 30
        Task { await syncAll() }
    }

    private func stopAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }

    // MARK: - Lifecycle observers

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUbiquityIdentityDidChange),
            name: .NSUbiquityIdentityDidChange,
            object: nil
        )

        // Observe auto-sync toggle to start/stop the timer.
        $autoSyncEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled, self.isICloudAvailable { self.startAutoSync() } else { self.stopAutoSync() }
            }
            .store(in: &cancellables)
    }

    @objc private func handleAppDidBecomeActive() {
        checkAvailability()
        guard autoSyncEnabled, isICloudAvailable else { return }
        Task { await syncAll() }
    }

    @objc private func handleAppWillResignActive() {
        guard isICloudAvailable else { return }
        // Request background execution time so the upload can complete even if the
        // app is suspended immediately after the notification.
        let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "ICloudUpload") {}
        Task {
            await uploadToICloud()
            UIApplication.shared.endBackgroundTask(bgTaskID)
        }
    }

    @objc private func handleUbiquityIdentityDidChange() {
        // This notification can arrive on an arbitrary thread; dispatch to main.
        DispatchQueue.main.async { [weak self] in self?.checkAvailability() }
    }

    // MARK: - Manifest persistence

    private func manifestURL() -> URL {
        localDocumentsURL().appendingPathComponent(Self.manifestFileName)
    }

    private func loadManifest() {
        let url = manifestURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(ICloudSyncManifest.self, from: data)
        else { return }
        manifest = loaded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL(), options: .atomic)
    }
}
