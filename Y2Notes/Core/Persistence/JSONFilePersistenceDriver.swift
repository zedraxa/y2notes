import Foundation
import os

// MARK: - JSONFilePersistenceDriver

/// Persists data as individual JSON files inside a directory (default:
/// `~/Documents/`).  This replicates the existing Y2Notes persistence
/// strategy while abstracting it behind `PersistenceDriver`.
///
/// Each logical key maps to a file named `<key>.json`.  A single-generation
/// `.bak` backup is maintained automatically for crash recovery.
final class JSONFilePersistenceDriver: PersistenceDriver {

    private let directory: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.y2notes", category: "JSONFilePersistenceDriver")

    // MARK: - Init

    /// Creates a driver rooted at the given directory.
    /// - Parameter directory: The directory where JSON files are stored.
    ///   Defaults to the user's Documents directory.
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        }

        // Ensure the directory exists.
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    // MARK: - PersistenceDriver

    func write(_ data: Data, forKey key: String) throws {
        let url = fileURL(for: key)
        let bakURL = backupURL(for: key)

        // Promote current file to .bak before overwriting.
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: bakURL)
            try? fileManager.copyItem(at: url, to: bakURL)
        }

        try data.write(to: url, options: .atomic)
    }

    func read(forKey key: String) throws -> Data? {
        let url = fileURL(for: key)

        if fileManager.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }

        // Fall back to .bak if the primary is missing or corrupt.
        let bakURL = backupURL(for: key)
        if fileManager.fileExists(atPath: bakURL.path) {
            logger.warning("Primary file missing for key '\(key)', falling back to backup.")
            return try Data(contentsOf: bakURL)
        }

        return nil
    }

    func delete(forKey key: String) throws {
        let url = fileURL(for: key)
        let bakURL = backupURL(for: key)
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: bakURL)
    }

    func exists(forKey key: String) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: key).path)
            || fileManager.fileExists(atPath: backupURL(for: key).path)
    }

    // MARK: - Helpers

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    private func backupURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json.bak")
    }
}
