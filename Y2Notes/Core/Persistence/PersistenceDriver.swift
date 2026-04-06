import Foundation

// MARK: - PersistenceDriver

/// Abstracts file-level persistence so that stores are independent of the
/// storage backend.  The default implementation is `JSONFilePersistenceDriver`;
/// future backends may include SQLite, Core Data, or CloudKit.
///
/// All methods are synchronous and intended to be called on a background queue
/// if the caller requires non-blocking I/O.
protocol PersistenceDriver: AnyObject {

    /// Write raw data to the given logical key (e.g. `"y2notes_notes"`).
    func write(_ data: Data, forKey key: String) throws

    /// Read raw data for the given logical key.  Returns `nil` when no data
    /// has been written for that key yet.
    func read(forKey key: String) throws -> Data?

    /// Delete data for the given logical key.
    func delete(forKey key: String) throws

    /// Whether data exists for the given key.
    func exists(forKey key: String) -> Bool
}

// MARK: - Typed convenience

extension PersistenceDriver {

    /// Encode a `Codable` value and write it to the given key.
    func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        try write(data, forKey: key)
    }

    /// Read and decode a `Codable` value from the given key.
    func decode<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = try read(forKey: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}
