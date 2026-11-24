import Foundation
import SQLite3

/// What `NoteStore.open` did about a damaged database: the alert of the app shows where the old file went.
nonisolated public struct CorruptionRecovery: Sendable, Equatable {
    public var movedFile: URL

    public init(movedFile: URL) {
        self.movedFile = movedFile
    }
}

/// Notes in one SQLite database. Synchronous, on the main actor: an autosave of a 5k-line Note takes milliseconds.
public final class NoteStore {
    public enum Location {
        case memory
        case file(URL)
    }

    /// Ordered SQL steps; `PRAGMA user_version` is the number of those applied.
    static let migrations: [String] = [
        """
        CREATE TABLE notes(
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            sel_location INTEGER NOT NULL DEFAULT 0,
            sel_length INTEGER NOT NULL DEFAULT 0,
            scroll_offset REAL NOT NULL DEFAULT 0
        );
        CREATE INDEX notes_created_at ON notes(created_at);
        CREATE INDEX notes_updated_at ON notes(updated_at);
        """,
    ]

    public static var schemaVersion: Int { migrations.count }

    /// `~/Library/Application Support/io.github.itigancov.pith/notes.sqlite`
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("io.github.itigancov.pith", isDirectory: true)
            .appendingPathComponent("notes.sqlite")
    }

    private let database: Database
    private let now: () -> Date

    private init(database: Database, now: @escaping () -> Date) {
        self.database = database
        self.now = now
    }

    /// Opens the database, creating or migrating it. A damaged file is moved aside and replaced by an empty
    /// database, which `recovery` reports. Any other failure is thrown and the file stays as it is.
    public static func open(
        at location: Location, now: @escaping () -> Date = Date.init
    ) throws -> (store: NoteStore, recovery: CorruptionRecovery?) {
        switch location {
        case .memory:
            return (try prepare(path: ":memory:", now: now), nil)
        case .file(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                return (try prepare(path: url.path, now: now), nil)
            } catch let error as NoteStoreError where error.isCorruption {
                let moved = try moveAside(url, at: now())
                return (try prepare(path: url.path, now: now), CorruptionRecovery(movedFile: moved))
            }
        }
    }

    private static func prepare(path: String, now: @escaping () -> Date) throws -> NoteStore {
        let database = try Database(path: path)
        // The first read of the file: a file that is not a database fails here.
        try database.query("PRAGMA journal_mode=WAL") { _ in }
        try database.execute("PRAGMA synchronous=NORMAL")
        try database.execute("PRAGMA foreign_keys=ON")
        let verdict = try database.query("PRAGMA quick_check") { $0.text(0) }
        if verdict.first != "ok" {
            throw NoteStoreError.sqlite(code: SQLITE_CORRUPT, message: verdict.first ?? "quick_check returned nothing")
        }
        try migrate(database)
        return NoteStore(database: database, now: now)
    }

    private static func migrate(_ database: Database) throws {
        let current = try database.queryInt("PRAGMA user_version")
        guard current <= migrations.count else {
            throw NoteStoreError.newerSchema(found: current, supported: migrations.count)
        }
        for step in current..<migrations.count {
            try database.transaction {
                try database.execute(migrations[step])
                try database.execute("PRAGMA user_version = \(step + 1)")
            }
        }
    }

    /// Renames the database and its `-wal`/`-shm` to `notes-corrupt-<date>.sqlite(-wal/-shm)` beside it.
    private static func moveAside(_ url: URL, at date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let stem = url.deletingPathExtension().lastPathComponent
        let moved = url.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-corrupt-\(formatter.string(from: date)).\(url.pathExtension)")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.moveItem(at: source, to: URL(fileURLWithPath: moved.path + suffix))
        }
        return moved
    }

    // MARK: Notes

    /// The Notes of the Stack: not in the Trash, in the order they were created.
    public func stack() throws -> [NoteSummary] {
        try database.query(
            "SELECT id, created_at, updated_at, deleted_at FROM notes WHERE deleted_at IS NULL ORDER BY created_at, rowid"
        ) { row in
            NoteSummary(
                id: UUID(uuidString: row.text(0)) ?? UUID(),
                createdAt: Self.date(row.int(1)), updatedAt: Self.date(row.int(2)),
                deletedAt: row.optionalInt(3).map(Self.date)
            )
        }
    }

    public func note(id: UUID) throws -> Note? {
        try database.query(
            "SELECT text, created_at, updated_at, deleted_at, sel_location, sel_length, scroll_offset FROM notes WHERE id = ?",
            [.text(id.uuidString)]
        ) { row in
            Note(
                id: id, text: row.text(0),
                createdAt: Self.date(row.int(1)), updatedAt: Self.date(row.int(2)), deletedAt: row.optionalInt(3).map(Self.date),
                selection: NoteSelection(location: Int(row.int(4)), length: Int(row.int(5))), scrollOffset: row.double(6)
            )
        }.first
    }

    /// Stores a new Note, the first write of a Blank that got text.
    public func insert(text: String, selection: NoteSelection, scrollOffset: Double) throws -> Note {
        let id = UUID()
        let time = Self.millis(now())
        try database.query(
            """
            INSERT INTO notes(id, text, created_at, updated_at, sel_location, sel_length, scroll_offset)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            """,
            [.text(id.uuidString), .text(text), .int(time), .int(time),
             .int(Int64(selection.location)), .int(Int64(selection.length)), .double(scrollOffset)]
        ) { _ in }
        return Note(
            id: id, text: text, createdAt: Self.date(time), updatedAt: Self.date(time), deletedAt: nil,
            selection: selection, scrollOffset: scrollOffset
        )
    }

    public func updateText(id: UUID, text: String) throws {
        try database.query(
            "UPDATE notes SET text = ?, updated_at = ? WHERE id = ?",
            [.text(text), .int(Self.millis(now())), .text(id.uuidString)]
        ) { _ in }
    }

    /// Leaves `updatedAt` alone: moving the cursor is not an edit.
    public func updateViewState(id: UUID, selection: NoteSelection, scrollOffset: Double) throws {
        try database.query(
            "UPDATE notes SET sel_location = ?, sel_length = ?, scroll_offset = ? WHERE id = ?",
            [.int(Int64(selection.location)), .int(Int64(selection.length)), .double(scrollOffset), .text(id.uuidString)]
        ) { _ in }
    }

    /// For a Note that was left empty. Moving a Note to the Trash is not here.
    public func deletePermanently(id: UUID) throws {
        try database.query("DELETE FROM notes WHERE id = ?", [.text(id.uuidString)]) { _ in }
    }

    // MARK: Helpers

    /// Raw SQL for the tests.
    func execute(_ sql: String) throws {
        try database.execute(sql)
    }

    func queryInt(_ sql: String) throws -> Int {
        try database.queryInt(sql)
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    private static func date(_ millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }
}
