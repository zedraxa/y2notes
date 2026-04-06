import Foundation
import os

// MARK: - SQLitePersistenceDriver

/// A ``PersistenceDriver`` backed by a C SQLite key-value store.
///
/// Replaces `JSONFilePersistenceDriver`'s per-file approach with a single
/// SQLite database using WAL mode.  The underlying C implementation
/// (`y2_sqlite.c`) uses prepared statements for O(1) reads/writes and
/// avoids Foundation `JSONEncoder`/`JSONDecoder` dependency in the hot path.
///
/// Usage:
/// ```swift
/// let driver = SQLitePersistenceDriver()  // ~/Documents/y2notes.db
/// try driver.write(data, forKey: "y2notes_notes")
/// ```
final class SQLitePersistenceDriver: PersistenceDriver {

    private let db: OpaquePointer  // y2_db*
    private let logger = Logger(subsystem: "com.y2notes", category: "SQLitePersistenceDriver")

    // MARK: - Init

    /// Open (or create) the database at the given path.
    /// Defaults to `~/Documents/y2notes.db`.
    init(path: String? = nil) {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            dbPath = docs.appendingPathComponent("y2notes.db").path
        }

        guard let handle = y2_db_open(dbPath) else {
            fatalError("SQLitePersistenceDriver: failed to open database at \(dbPath)")
        }
        db = handle

        logger.info("SQLite \(String(cString: y2_sqlite_version()), privacy: .public) database opened at \(dbPath, privacy: .public)")
    }

    deinit {
        y2_db_close(db)
    }

    // MARK: - PersistenceDriver

    func write(_ data: Data, forKey key: String) throws {
        let result = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int32 in
            y2_db_write(db,
                        key,
                        ptr.baseAddress,
                        UInt32(data.count))
        }
        if result != 0 {
            logger.error("SQLite write failed for key '\(key)'")
            throw SQLiteDriverError.writeFailed(key: key)
        }
    }

    func read(forKey key: String) throws -> Data? {
        var outData: UnsafeMutableRawPointer?
        var outLength: UInt32 = 0

        let result = y2_db_read(db, key, &outData, &outLength)

        switch result {
        case 0:
            guard let ptr = outData, outLength > 0 else { return nil }
            let data = Data(bytes: ptr, count: Int(outLength))
            free(ptr)
            return data
        case 1:
            return nil  // Key not found
        default:
            logger.error("SQLite read failed for key '\(key)'")
            throw SQLiteDriverError.readFailed(key: key)
        }
    }

    func delete(forKey key: String) throws {
        let result = y2_db_delete(db, key)
        if result != 0 {
            logger.error("SQLite delete failed for key '\(key)'")
            throw SQLiteDriverError.deleteFailed(key: key)
        }
    }

    func exists(forKey key: String) -> Bool {
        y2_db_exists(db, key)
    }

    // MARK: - Maintenance

    /// Explicitly checkpoint the WAL.
    func checkpoint() {
        y2_db_checkpoint(db)
    }
}

// MARK: - Errors

enum SQLiteDriverError: Error, LocalizedError {
    case writeFailed(key: String)
    case readFailed(key: String)
    case deleteFailed(key: String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let key):  return "SQLite write failed for key '\(key)'"
        case .readFailed(let key):   return "SQLite read failed for key '\(key)'"
        case .deleteFailed(let key): return "SQLite delete failed for key '\(key)'"
        }
    }
}
