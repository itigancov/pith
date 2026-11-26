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
        // Search: `folded` is the text folded in Swift, `index_dirty` marks Notes whose `folded` and index
        // entry are out of date. `search` brings them up to date; the first one does it for every old Note.
        """
        ALTER TABLE notes ADD COLUMN folded TEXT;
        ALTER TABLE notes ADD COLUMN index_dirty INTEGER NOT NULL DEFAULT 1;
        CREATE VIRTUAL TABLE notes_fts USING fts5(folded, content='notes', content_rowid='rowid', tokenize='trigram');
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
        try database.run("PRAGMA journal_mode=WAL")
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
            "SELECT id, created_at, updated_at, deleted_at FROM notes WHERE deleted_at IS NULL ORDER BY created_at, rowid",
            [], summary
        )
    }

    private func summary(_ row: Row) throws -> NoteSummary {
        guard let id = UUID(uuidString: row.text(0)) else {
            throw NoteStoreError.sqlite(code: SQLITE_CORRUPT, message: "unreadable note id \(row.text(0))")
        }
        return NoteSummary(id: id, createdAt: row.date(1), updatedAt: row.date(2), deletedAt: row.optionalDate(3))
    }

    public func note(id: UUID) throws -> Note? {
        try database.query(
            "SELECT text, created_at, updated_at, deleted_at, sel_location, sel_length, scroll_offset FROM notes WHERE id = ?",
            [.text(id.uuidString)]
        ) { row in
            Note(
                id: id, text: row.text(0),
                createdAt: row.date(1), updatedAt: row.date(2), deletedAt: row.optionalDate(3),
                selection: NoteSelection(location: Int(row.int(4)), length: Int(row.int(5))), scrollOffset: row.double(6)
            )
        }.first
    }

    /// Stores a new Note, the first write of a Blank that got text.
    public func insert(text: String, selection: NoteSelection, scrollOffset: Double) throws -> Note {
        let id = UUID()
        let time = Self.millis(now())
        try database.run(
            """
            INSERT INTO notes(id, text, created_at, updated_at, sel_location, sel_length, scroll_offset)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            """,
            [.text(id.uuidString), .text(text), .int(time), .int(time),
             .int(Int64(selection.location)), .int(Int64(selection.length)), .double(scrollOffset)]
        )
        return Note(
            id: id, text: text, createdAt: Self.date(time), updatedAt: Self.date(time), deletedAt: nil,
            selection: selection, scrollOffset: scrollOffset
        )
    }

    public func updateText(id: UUID, text: String) throws {
        try database.run(
            // `folded` stays as it is: `search` folds the text, so that typing does not.
            "UPDATE notes SET text = ?, updated_at = ?, index_dirty = 1 WHERE id = ?",
            [.text(text), .int(Self.millis(now())), .text(id.uuidString)]
        )
    }

    /// Leaves `updatedAt` alone: moving the cursor is not an edit.
    public func updateViewState(id: UUID, selection: NoteSelection, scrollOffset: Double) throws {
        try database.run(
            "UPDATE notes SET sel_location = ?, sel_length = ?, scroll_offset = ? WHERE id = ?",
            [.int(Int64(selection.location)), .int(Int64(selection.length)), .double(scrollOffset), .text(id.uuidString)]
        )
    }

    /// For a Note that was left empty. Moving a Note to the Trash is not here.
    public func deletePermanently(id: UUID) throws {
        try database.transaction {
            // The entry goes from the index first: its row number may be taken by a new Note.
            let indexed = try database.query(
                "SELECT rowid, folded FROM notes WHERE id = ? AND folded IS NOT NULL", [.text(id.uuidString)]
            ) { ($0.int(0), $0.text(1)) }
            for (rowid, folded) in indexed { try removeFromIndex(rowid: rowid, folded: folded) }
            try database.run("DELETE FROM notes WHERE id = ?", [.text(id.uuidString)])
        }
    }

    /// Deletes for good every Note of the Stack whose text is empty or only whitespace, and returns their ids.
    /// A Note in the Trash stays: it was put there on purpose.
    @discardableResult
    public func deleteEmptyNotes() throws -> [UUID] {
        let candidates = try database.query("SELECT id, text FROM notes WHERE deleted_at IS NULL") { ($0.text(0), $0.text(1)) }
        let empty = candidates.compactMap { id, text in
            Note.isEmpty(text: text) ? UUID(uuidString: id) : nil
        }
        for id in empty { try deletePermanently(id: id) }
        return empty
    }

    // MARK: Search

    /// The Notes of the Stack that contain every word of `query`, newest edit first. An empty query gives
    /// the whole Stack in that order. Case, diacritics and ё/е are ignored, й is a letter of its own.
    /// Words of 1–2 characters are looked up by a scan, longer ones by the full-text index.
    public func search(_ query: String) throws -> [NoteSummary] {
        let parsed = SearchQuery(query)
        let columns = "SELECT n.id, n.created_at, n.updated_at, n.deleted_at FROM notes n WHERE n.deleted_at IS NULL"
        let order = " ORDER BY n.updated_at DESC, n.rowid DESC"
        if parsed.isEmpty {
            return try database.query(columns + order, [], summary)
        }

        try reindex()

        var conditions = ""
        var binds: [Bind] = []
        // Words of three characters and more are phrases of one MATCH; a quote in a word is doubled.
        let long = parsed.words.filter { $0.unicodeScalars.count >= Self.trigramLength }
        if !long.isEmpty {
            conditions += " AND n.rowid IN (SELECT rowid FROM notes_fts WHERE notes_fts MATCH ?)"
            binds.append(.text(long.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")))
        }
        for word in parsed.words where word.unicodeScalars.count < Self.trigramLength {
            conditions += " AND instr(n.folded, ?) > 0"
            binds.append(.text(word))
        }
        return try database.query(columns + conditions + order, binds, summary)
    }

    /// Shorter words are not in the trigram index.
    private static let trigramLength = 3

    /// Folds the Notes that were edited since the last search and updates their entries of the index.
    private func reindex() throws {
        let stale = try database.query("SELECT rowid, text, folded FROM notes WHERE index_dirty = 1") { row in
            (rowid: row.int(0), folded: Folding.foldedString(row.text(1)), previous: row.isNull(2) ? nil : row.text(2))
        }
        if stale.isEmpty { return }
        try database.transaction {
            for note in stale {
                if let previous = note.previous { try removeFromIndex(rowid: note.rowid, folded: previous) }
                try database.run(
                    "UPDATE notes SET folded = ?, index_dirty = 0 WHERE rowid = ?", [.text(note.folded), .int(note.rowid)]
                )
                try database.run("INSERT INTO notes_fts(rowid, folded) VALUES(?, ?)", [.int(note.rowid), .text(note.folded)])
            }
        }
    }

    /// An external-content index forgets an entry only if told the text it was made of.
    private func removeFromIndex(rowid: Int64, folded: String) throws {
        try database.run(
            "INSERT INTO notes_fts(notes_fts, rowid, folded) VALUES('delete', ?, ?)", [.int(rowid), .text(folded)]
        )
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
