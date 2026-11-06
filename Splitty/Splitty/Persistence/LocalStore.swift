import Foundation
import SQLite3

/// What this device keeps per signed-in user so the app works without a network: the last
/// groups list, each group's last snapshot, and the writes not yet confirmed (ADR 0008).
///
/// SQLite through the system `libsqlite3`, not a dependency. Values are Codable blobs keyed
/// by name: nothing queries inside them, and a group is always read whole. What SQLite adds
/// over files is a transaction, so confirming a write and saving the snapshot it changed
/// commit together.
///
/// Every call runs on one serial queue, so the store can be used from any actor.
final class LocalStore: @unchecked Sendable {
    /// The app's store in Application Support. Nil storage (an in-memory database) when the
    /// file cannot be opened, so a broken disk costs offline support, not the app.
    static let shared = LocalStore(url: LocalStore.defaultURL)

    private let queue = DispatchQueue(label: "com.splitty.local-store")
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// `url` nil opens an in-memory database, which is what tests use.
    init(url: URL?) {
        let path = url?.path ?? ":memory:"
        if let url {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            sqlite3_close(db)
            db = nil
            sqlite3_open(":memory:", &db)
        }
        if let url { Self.excludeFromBackup(url) }
        execute("PRAGMA journal_mode = WAL")
        execute("""
            CREATE TABLE IF NOT EXISTS value (
                user_id INTEGER NOT NULL,
                key TEXT NOT NULL,
                json BLOB NOT NULL,
                PRIMARY KEY (user_id, key)
            )
            """)
        execute("""
            CREATE TABLE IF NOT EXISTS pending_write (
                user_id INTEGER NOT NULL,
                position INTEGER NOT NULL,
                id TEXT NOT NULL,
                json BLOB NOT NULL,
                PRIMARY KEY (user_id, id)
            )
            """)
    }

    deinit { sqlite3_close(db) }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Splitty", isDirectory: true)
            .appendingPathComponent("local.sqlite")
    }

    // MARK: - Values

    func value<T: Decodable>(_ type: T.Type, user: Int, key: String) -> T? {
        queue.sync {
            let statement = prepare("SELECT json FROM value WHERE user_id = ? AND key = ?")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(user))
            bind(statement, 2, key)
            guard sqlite3_step(statement) == SQLITE_ROW, let data = column(statement, 0) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    func set<T: Encodable>(_ value: T, user: Int, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        queue.sync { upsert(data, user: user, key: key) }
    }

    func removeValue(user: Int, key: String) {
        queue.sync {
            let statement = prepare("DELETE FROM value WHERE user_id = ? AND key = ?")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(user))
            bind(statement, 2, key)
            sqlite3_step(statement)
        }
    }

    // MARK: - Pending writes

    func pendingWrites(user: Int) -> [PendingWrite] {
        queue.sync {
            let statement = prepare("SELECT json FROM pending_write WHERE user_id = ? ORDER BY position")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(user))
            var writes: [PendingWrite] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                // A write this build can no longer read is dropped rather than blocking the
                // queue behind it forever.
                if let data = column(statement, 0), let write = try? decoder.decode(PendingWrite.self, from: data) {
                    writes.append(write)
                }
            }
            return writes
        }
    }

    /// Replaces the user's queue with `writes`, in order, and saves `values` in the same
    /// transaction.
    func savePendingWrites(_ writes: [PendingWrite], user: Int, alongWith values: [String: Data] = [:]) {
        let encoded: [(UUID, Data)] = writes.compactMap { write in
            guard let data = try? encoder.encode(write) else { return nil }
            return (write.id, data)
        }
        queue.sync {
            execute("BEGIN IMMEDIATE")
            let delete = prepare("DELETE FROM pending_write WHERE user_id = ?")
            sqlite3_bind_int64(delete, 1, Int64(user))
            sqlite3_step(delete)
            sqlite3_finalize(delete)
            for (position, (id, data)) in encoded.enumerated() {
                let insert = prepare("INSERT INTO pending_write (user_id, position, id, json) VALUES (?, ?, ?, ?)")
                sqlite3_bind_int64(insert, 1, Int64(user))
                sqlite3_bind_int64(insert, 2, Int64(position))
                bind(insert, 3, id.uuidString)
                bind(insert, 4, data)
                sqlite3_step(insert)
                sqlite3_finalize(insert)
            }
            for (key, data) in values { upsert(data, user: user, key: key) }
            execute("COMMIT")
        }
    }

    func encode<T: Encodable>(_ value: T) -> Data? { try? encoder.encode(value) }

    // MARK: - Removal

    /// Everything kept for `user`: what signing out or deleting the account leaves behind.
    func removeAll(user: Int) {
        queue.sync {
            for table in ["value", "pending_write"] {
                let statement = prepare("DELETE FROM \(table) WHERE user_id = ?")
                sqlite3_bind_int64(statement, 1, Int64(user))
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    // MARK: - SQLite

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ text: String) {
        sqlite3_bind_text(statement, index, text, -1, Self.transient)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ data: Data) {
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), Self.transient)
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func upsert(_ data: Data, user: Int, key: String) {
        let statement = prepare("""
            INSERT INTO value (user_id, key, json) VALUES (?, ?, ?)
            ON CONFLICT (user_id, key) DO UPDATE SET json = excluded.json
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(user))
        bind(statement, 2, key)
        bind(statement, 3, data)
        sqlite3_step(statement)
    }

    private static func excludeFromBackup(_ url: URL) {
        // The cache is rebuilt from the server, and the queued writes are tied to this
        // device's sign-in, whose credentials are not backed up either.
        var directory = url.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }
}

/// One group as this device last read it.
struct GroupSnapshot: Codable {
    var group: GroupDetail?
    var expenses: [Expense]
    var summary: GroupBalanceSummary?
    var savedAt: Date

    static func key(groupId: Int) -> String { "group.\(groupId)" }
}

/// The groups list as this device last read it.
struct GroupsSnapshot: Codable {
    var groups: [Group]
    var savedAt: Date

    static let key = "groups"
}
