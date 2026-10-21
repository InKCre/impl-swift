import CSQLite
import Foundation
import PeerCore

// Only CaptureStore's actor accesses this connection; the wrapper closes it on deallocation.
private final class SQLiteConnection: @unchecked Sendable {
    private let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(
            url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard status == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw PeerError.storage("无法打开本地采集数据库。")
        }
        handle = database
        sqlite3_busy_timeout(handle, 5000)
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw error()
        }
    }

    func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else { throw error() }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    func error() -> PeerError {
        .storage("本地保存失败：\(String(cString: sqlite3_errmsg(handle)))")
    }
}

public actor CaptureStore {
    private let database: SQLiteConnection
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    // Late tasks only live in this process; retain IDs, never deleted records or materials.
    private var deletedIDs: Set<UUID> = []

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        database = try SQLiteConnection(url: url)
        let version = try database.statement("PRAGMA user_version") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { throw database.error() }
            return sqlite3_column_int(statement, 0)
        }
        guard version == 0 || version == 1 else {
            throw PeerError.storage("本地数据来自较新版本，请更新 InKCre 后再打开。")
        }
        try database.execute(
            """
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=FULL;
            CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, body BLOB NOT NULL);
            PRAGMA user_version=1;
            """)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func records() throws -> [CaptureRecord] {
        try database.statement("SELECT body FROM records") { statement in
            var records: [CaptureRecord] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw database.error() }
                records.append(try CaptureJSON.decode(CaptureRecord.self, from: data(statement)))
            }
            return records.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func record(_ id: UUID) throws -> CaptureRecord? {
        try database.statement("SELECT body FROM records WHERE id=?") { statement in
            sqlite3_bind_text(statement, 1, id.uuidString, -1, transient)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw database.error() }
            return try CaptureJSON.decode(CaptureRecord.self, from: data(statement))
        }
    }

    public func saveDraft(_ record: CaptureRecord) throws {
        guard !deletedIDs.contains(record.id) else { return }
        let previous = try self.record(record.id)
        guard record.state == .draft,
            previous?.state ?? .draft == .draft
        else {
            throw PeerError.invalid("已提交的材料不能作为草稿覆盖。")
        }
        try save(record)
    }

    public func freeze(_ draft: CaptureRecord, target: ConnectionTarget) throws -> CaptureRecord {
        guard !deletedIDs.contains(draft.id), draft.state == .draft,
            let payload = draft.payload, payload.submissionID == draft.id
        else {
            throw PeerError.invalid("草稿状态不正确。")
        }
        try payload.validate()
        try target.validate()
        try database.execute("BEGIN IMMEDIATE")
        do {
            if let old = try record(draft.id), old.state != .draft {
                throw PeerError.invalid("这份材料已经进入待办，请查看原提交。")
            }
            var frozen = draft
            frozen.target = target
            frozen.state = .pending
            frozen.message = nil
            frozen.updatedAt = Date()
            try save(frozen)
            try database.execute("COMMIT")
            return frozen
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    public func markDispatch(_ id: UUID) throws -> CaptureRecord {
        guard var value = try record(id), [.pending, .unknown].contains(value.state),
            value.payload != nil, value.target != nil
        else {
            throw PeerError.invalid("待办当前不能发送。")
        }
        // Persist uncertainty before network dispatch, so process death never loses it.
        value.state = .unknown
        value.attempts += 1
        value.updatedAt = Date()
        try save(value)
        return value
    }

    public func report(_ id: UUID, state: CaptureRecord.State, message: String) throws {
        guard !deletedIDs.contains(id) else { return }
        guard var value = try record(id) else { throw PeerError.invalid("找不到待办。") }
        // A late failure must not resume an intention the user already cancelled or deleted.
        guard value.state != .cancelled else { return }
        guard value.state != .draft, value.state != .confirmed,
            [.pending, .unknown, .needsAction].contains(state)
        else {
            throw PeerError.invalid("待办状态不可变更。")
        }
        value.state = state
        value.message = message
        value.updatedAt = Date()
        try save(value)
    }

    public func retry(_ id: UUID) throws {
        guard var value = try record(id),
            value.state != .draft, value.state != .confirmed
        else {
            throw PeerError.invalid("这份材料无需重试。")
        }
        value.state = value.attempts == 0 ? .pending : .unknown
        value.message = "使用原提交身份重新确认。"
        value.updatedAt = Date()
        try save(value)
    }

    @discardableResult
    public func cancel(_ id: UUID) throws -> CaptureRecord {
        guard var value = try record(id),
            [.pending, .unknown, .needsAction, .cancelled].contains(value.state)
        else {
            throw PeerError.invalid("这份材料已经收入或不是待办，请刷新后查看。")
        }
        value.state = .cancelled
        value.message =
            value.attempts == 0
            ? "尚未发送。材料保留在本机，可继续收入。"
            : "已停止后续发送；此前请求可能已收入。继续收入时会先确认原回执。"
        value.updatedAt = Date()
        try save(value)
        return value
    }

    public func deleteRecord(_ id: UUID) throws {
        try deleteRow(id)
        deletedIDs.insert(id)
    }

    public func confirm(_ id: UUID, result: CaptureResult) throws {
        guard !deletedIDs.contains(id) else { return }
        guard var value = try record(id), value.state != .draft,
            result.submissionID == id
        else {
            throw PeerError.invalid("提交回执与本机记录不匹配。")
        }
        value.result = result
        value.state = .confirmed
        value.message = nil
        value.payload = nil
        value.updatedAt = Date()
        // One row replacement atomically keeps the receipt while discarding local material.
        try save(value)
    }

    public func discardDraft(_ id: UUID) throws {
        guard !deletedIDs.contains(id), let value = try record(id) else { return }
        guard value.state == .draft else {
            throw PeerError.invalid("只能丢弃尚未提交的草稿。")
        }
        try deleteRow(id)
    }

    private func deleteRow(_ id: UUID) throws {
        try database.statement("DELETE FROM records WHERE id=?") { statement in
            sqlite3_bind_text(statement, 1, id.uuidString, -1, transient)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw database.error() }
        }
    }

    private func save(_ record: CaptureRecord) throws {
        let encoded = try CaptureJSON.encode(record)
        try database.statement("INSERT OR REPLACE INTO records(id,body) VALUES (?,?)") { statement in
            sqlite3_bind_text(statement, 1, record.id.uuidString, -1, transient)
            let result = encoded.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), transient)
            }
            guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
                throw database.error()
            }
        }
    }

    private func data(_ statement: OpaquePointer) -> Data {
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard let pointer = sqlite3_column_blob(statement, 0) else { return Data() }
        return Data(bytes: pointer, count: count)
    }
}
