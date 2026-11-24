import Foundation
import SQLite3

nonisolated public enum NoteStoreError: Error, Equatable, CustomStringConvertible {
    /// A failure of SQLite: its result code and message.
    case sqlite(code: Int32, message: String)
    /// The file was written by a newer Pith: its `user_version` is above the last migration this build knows.
    case newerSchema(found: Int, supported: Int)

    public var description: String {
        switch self {
        case .sqlite(let code, let message): "SQLite error \(code): \(message)"
        case .newerSchema(let found, let supported):
            "The notes were saved by a newer version of Pith (schema \(found), this version reads up to \(supported))"
        }
    }

    /// The file is not a database or its pages are damaged.
    var isCorruption: Bool {
        guard case .sqlite(let code, _) = self else { return false }
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
    }
}

/// A value bound to a `?` of a statement.
enum Bind {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    init(_ value: Int64?) { self = value.map(Bind.int) ?? .null }
}

/// The current row of a statement being read.
struct Row {
    let statement: OpaquePointer

    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
    func optionalInt(_ column: Int32) -> Int64? { isNull(column) ? nil : int(column) }

    func text(_ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }
}

/// A thin wrapper of one `sqlite3` connection with a cache of prepared statements.
final class Database {
    nonisolated(unsafe) private var handle: OpaquePointer?
    nonisolated(unsafe) private var statements: [String: OpaquePointer] = [:]

    init(path: String) throws {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        guard code == SQLITE_OK else {
            let error = NoteStoreError.sqlite(code: code, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open")
            sqlite3_close_v2(handle)
            throw error
        }
        self.handle = handle
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    private func error(_ code: Int32) -> NoteStoreError {
        .sqlite(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }

    /// Runs statements that need neither binds nor results.
    func execute(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw error(code) }
    }

    /// Runs one statement with binds and maps every row it returns.
    @discardableResult
    func query<T>(_ sql: String, _ binds: [Bind] = [], _ map: (Row) -> T) throws -> [T] {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        for (index, bind) in binds.enumerated() {
            let position = Int32(index + 1)
            let code: Int32 = switch bind {
            case .int(let value): sqlite3_bind_int64(statement, position, value)
            case .double(let value): sqlite3_bind_double(statement, position, value)
            case .text(let value): sqlite3_bind_text(statement, position, value, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, position)
            }
            guard code == SQLITE_OK else { throw error(code) }
        }
        var rows: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                rows.append(map(Row(statement: statement)))
            } else if code == SQLITE_DONE {
                return rows
            } else {
                throw error(code)
            }
        }
    }

    func queryInt(_ sql: String) throws -> Int {
        try query(sql) { Int($0.int(0)) }.first ?? 0
    }

    /// Runs `body` in one transaction: committed when it returns, rolled back when it throws.
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let cached = statements[sql] { return cached }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw error(code) }
        statements[sql] = statement
        return statement
    }

    /// Makes SQLite copy the bound text, since Swift frees its buffer after the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
