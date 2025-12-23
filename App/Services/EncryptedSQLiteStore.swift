import CryptoKit
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor EncryptedSQLiteStore {
    enum StoreError: Error, LocalizedError {
        case sqlite(String)
        case encryption(String)

        var errorDescription: String? {
            switch self {
            case .sqlite(let msg): return "SQLite error: \(msg)"
            case .encryption(let msg): return "Encryption error: \(msg)"
            }
        }
    }

    private let key: SymmetricKey
    private let dbURL: URL
    private var db: OpaquePointer?

    init(databaseFileName: String = "scalinity_bio.sqlite3", keyMaterial: Data) throws {
        self.key = SymmetricKey(data: keyMaterial)

        let dir = try FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            .unwrap(or: StoreError.sqlite("Could not resolve Application Support directory."))
            .appendingPathComponent("scalinity.bio", isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        self.dbURL = dir.appendingPathComponent(databaseFileName)

        // Initialize the SQLite connection inside init (avoids Swift 6 actor-isolation warnings).
        var dbPtr: OpaquePointer?
        if sqlite3_open(dbURL.path, &dbPtr) != SQLITE_OK {
            throw StoreError.sqlite("Unable to open DB at \(dbURL.path)")
        }
        self.db = dbPtr

        let migrateSQL = """
        CREATE TABLE IF NOT EXISTS secure_kv (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_secure_kv_type ON secure_kv(type);
        """
        var err: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(dbPtr, migrateSQL, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "Unknown sqlite error"
            sqlite3_free(err)
            throw StoreError.sqlite(msg)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func put(type: String, id: String, payload: Data) throws {
        let encrypted = try encrypt(payload)
        let now = Date().timeIntervalSince1970

        let sql = """
        INSERT INTO secure_kv (id, type, created_at, updated_at, payload)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            type=excluded.type,
            updated_at=excluded.updated_at,
            payload=excluded.payload;
        """

        var stmt: OpaquePointer?
        try prepare(sql, stmt: &stmt)
        defer { sqlite3_finalize(stmt) }

        _ = id.withCString { cStr in
            sqlite3_bind_text(stmt, 1, cStr, -1, SQLITE_TRANSIENT)
        }
        _ = type.withCString { cStr in
            sqlite3_bind_text(stmt, 2, cStr, -1, SQLITE_TRANSIENT)
        }
        sqlite3_bind_double(stmt, 3, now)
        sqlite3_bind_double(stmt, 4, now)
        _ = encrypted.withUnsafeBytes { bytes in
            sqlite3_bind_blob(stmt, 5, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
        }

        try step(stmt)
    }

    func get(type: String, id: String) throws -> Data? {
        let sql = "SELECT payload FROM secure_kv WHERE id=? AND type=? LIMIT 1;"
        var stmt: OpaquePointer?
        try prepare(sql, stmt: &stmt)
        defer { sqlite3_finalize(stmt) }

        _ = id.withCString { cStr in
            sqlite3_bind_text(stmt, 1, cStr, -1, SQLITE_TRANSIENT)
        }
        _ = type.withCString { cStr in
            sqlite3_bind_text(stmt, 2, cStr, -1, SQLITE_TRANSIENT)
        }

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(stmt, 0) else { return nil }
            let size = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: blob, count: size)
            return try decrypt(data)
        }
        if rc == SQLITE_DONE {
            return nil
        }
        throw StoreError.sqlite(sqlite3_errmsg_string(db))
    }

    // MARK: - Encryption

    private func encrypt(_ plaintext: Data) throws -> Data {
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else {
                throw StoreError.encryption("Could not create combined sealed box.")
            }
            return combined
        } catch {
            throw StoreError.encryption(error.localizedDescription)
        }
    }

    private func decrypt(_ ciphertext: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw StoreError.encryption(error.localizedDescription)
        }
    }

    // MARK: - SQLite

    private func exec(_ sql: String) throws {
        guard let db else { throw StoreError.sqlite("DB not open") }
        var err: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "Unknown sqlite error"
            sqlite3_free(err)
            throw StoreError.sqlite(msg)
        }
    }

    private func prepare(_ sql: String, stmt: inout OpaquePointer?) throws {
        guard let db else { throw StoreError.sqlite("DB not open") }
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            throw StoreError.sqlite(sqlite3_errmsg_string(db))
        }
    }

    private func step(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            throw StoreError.sqlite(sqlite3_errmsg_string(db))
        }
    }
}

private func sqlite3_errmsg_string(_ db: OpaquePointer?) -> String {
    guard let db, let c = sqlite3_errmsg(db) else { return "Unknown sqlite error" }
    return String(cString: c)
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        switch self {
        case .some(let x): return x
        case .none: throw error()
        }
    }
}


