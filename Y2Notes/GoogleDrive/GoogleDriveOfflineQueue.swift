import Foundation

/// Persists pending sync operations that could not be executed due to
/// network unavailability. Operations are serialised to disk so they
/// survive app restarts and are replayed in FIFO order when connectivity
/// returns.
///
/// The queue is intentionally simple: it stores operations as a flat JSON
/// array. Each operation carries its own payload snapshot so replay is
/// self-contained and does not depend on the current in-memory state.
///
/// **Retry policy**: Each operation tracks a `retryCount`. The sync engine
/// increments this on each failed attempt. Operations that exceed
/// `maxRetries` are discarded to prevent infinite loops on permanently
/// invalid payloads.
@MainActor
final class GoogleDriveOfflineQueue: ObservableObject {

    // MARK: - Published state

    @Published private(set) var pendingOperations: [OfflineOperation] = []

    /// Maximum number of retries before an operation is discarded.
    static let maxRetries = 5

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Queue API

    /// Enqueues a new sync operation. If the device is offline, the operation
    /// is persisted to disk and will be replayed when `replayAll` is called.
    func enqueue(_ operation: OfflineOperation) {
        pendingOperations.append(operation)
        save()
    }

    /// Convenience: enqueue an upload operation for a specific resource type.
    func enqueueUpload(resourceType: OfflineOperation.ResourceType, payload: Data) {
        let op = OfflineOperation(kind: .upload, resourceType: resourceType, payload: payload)
        enqueue(op)
    }

    /// Convenience: enqueue a delete operation.
    func enqueueDelete(resourceType: OfflineOperation.ResourceType, driveFileID: String) {
        let payload = driveFileID.data(using: .utf8) ?? Data()
        let op = OfflineOperation(kind: .delete, resourceType: resourceType, payload: payload)
        enqueue(op)
    }

    /// Removes a successfully executed operation from the queue.
    func removeOperation(id: UUID) {
        pendingOperations.removeAll { $0.id == id }
        save()
    }

    /// Increments the retry count for an operation. Discards the operation
    /// if it exceeds `maxRetries`.
    func incrementRetry(id: UUID) {
        guard let idx = pendingOperations.firstIndex(where: { $0.id == id }) else { return }
        pendingOperations[idx].retryCount += 1
        if pendingOperations[idx].retryCount > Self.maxRetries {
            pendingOperations.remove(at: idx)
        }
        save()
    }

    /// Removes all pending operations (e.g. on sign-out).
    func clearAll() {
        pendingOperations.removeAll()
        save()
    }

    /// Number of operations waiting to be synced.
    var pendingCount: Int { pendingOperations.count }

    // MARK: - Persistence

    private static func queueURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("y2notes_offline_queue.json")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pendingOperations) else { return }
        try? data.write(to: Self.queueURL(), options: .atomic)
    }

    private func load() {
        let url = Self.queueURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let ops = try? JSONDecoder().decode([OfflineOperation].self, from: data)
        else { return }
        pendingOperations = ops
    }
}
