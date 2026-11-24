import Foundation
import Testing
@testable import PithNotes

/// The tests that need a file: reopening, migrations of an existing database, damaged and unreadable files.
@MainActor @Suite struct NoteStoreFileTests {
    let directory: URL
    let databaseURL: URL
    let clock = TestClock()

    init() throws {
        directory = try makeTemporaryDirectory()
        databaseURL = directory.appendingPathComponent("notes.sqlite")
    }

    private func open() throws -> (store: NoteStore, recovery: CorruptionRecovery?) {
        try NoteStore.open(at: .file(databaseURL), now: { clock.date })
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func corruptFiles() throws -> [String] {
        try files().filter { $0.hasPrefix("notes-corrupt-") }
    }

    /// A database with a few Notes of the size that takes several pages, closed.
    private func makeDatabase() throws {
        let (store, _) = try open()
        for index in 0..<20 {
            _ = try store.insert(text: String(repeating: "note \(index) ", count: 2000), selection: noSelection, scrollOffset: 0)
        }
    }

    /// Checks the store opened after a recovery is empty and takes writes.
    private func expectWorkingEmptyStore(_ store: NoteStore) throws {
        #expect(try store.stack().isEmpty)
        let note = try store.insert(text: "fresh", selection: noSelection, scrollOffset: 0)
        #expect(try store.note(id: note.id)?.text == "fresh")
    }

    // MARK: Opening

    @Test func createsTheDirectoryAndTheFile() throws {
        let nested = directory.appendingPathComponent("a/b/notes.sqlite")
        let (_, recovery) = try NoteStore.open(at: .file(nested))
        #expect(recovery == nil)
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test func notesSurviveReopening() throws {
        let id: UUID
        do {
            let (store, _) = try open()
            id = try store.insert(text: "kept", selection: NoteSelection(location: 2, length: 1), scrollOffset: 7).id
        }
        let (store, recovery) = try open()
        #expect(recovery == nil)
        #expect(try store.note(id: id)?.text == "kept")
        #expect(try store.note(id: id)?.selection == NoteSelection(location: 2, length: 1))
        // A migration applied twice would fail on its CREATE TABLE.
        #expect(try store.queryInt("PRAGMA user_version") == NoteStore.schemaVersion)
    }

    @Test func databaseOfANewerSchemaIsLeftAlone() throws {
        do {
            let (store, _) = try open()
            try store.execute("PRAGMA user_version = \(NoteStore.schemaVersion + 1)")
        }
        let before = try Data(contentsOf: databaseURL)
        #expect(throws: NoteStoreError.newerSchema(found: NoteStore.schemaVersion + 1, supported: NoteStore.schemaVersion)) {
            try open()
        }
        #expect(try corruptFiles().isEmpty)
        #expect(try Data(contentsOf: databaseURL) == before)
    }

    @Test func unwritableDirectoryIsAnErrorNotACorruption() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        #expect(throws: NoteStoreError.self) { try open() }
        #expect(try corruptFiles().isEmpty)
    }

    // MARK: Damaged databases

    @Test func fileOfGarbageIsMovedAside() throws {
        let garbage = Data(repeating: 0x5A, count: 8192)
        try garbage.write(to: databaseURL)
        let (store, recovery) = try open()
        let moved = try #require(recovery?.movedFile)
        #expect(moved.lastPathComponent.hasPrefix("notes-corrupt-"))
        #expect(moved.pathExtension == "sqlite")
        #expect(try Data(contentsOf: moved) == garbage)
        try expectWorkingEmptyStore(store)
    }

    @Test func movedFileIsNamedAfterTheTime() throws {
        try Data(repeating: 0x5A, count: 8192).write(to: databaseURL)
        let (_, recovery) = try open()
        let name = try #require(recovery?.movedFile.lastPathComponent)
        #expect(try /^notes-corrupt-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.sqlite$/.wholeMatch(in: name) != nil)
    }

    @Test func walAndShmMoveWithTheFile() throws {
        try Data(repeating: 0x5A, count: 8192).write(to: databaseURL)
        try Data("wal".utf8).write(to: directory.appendingPathComponent("notes.sqlite-wal"))
        try Data("shm".utf8).write(to: directory.appendingPathComponent("notes.sqlite-shm"))
        let (store, recovery) = try open()
        let moved = try #require(recovery?.movedFile)
        // SQLite may touch the pair while it tries the file, so only their move is checked, not their bytes.
        #expect(FileManager.default.fileExists(atPath: moved.path + "-wal"))
        #expect(FileManager.default.fileExists(atPath: moved.path + "-shm"))
        try expectWorkingEmptyStore(store)
    }

    @Test func truncatedFileIsMovedAside() throws {
        try makeDatabase()
        let handle = try FileHandle(forWritingTo: databaseURL)
        try handle.truncate(atOffset: 6000)
        try handle.close()
        let (store, recovery) = try open()
        let moved = try #require(recovery?.movedFile)
        #expect(FileManager.default.fileExists(atPath: moved.path))
        try expectWorkingEmptyStore(store)
    }

    @Test func damagedPageBehindAValidHeaderIsMovedAside() throws {
        try makeDatabase()
        let handle = try FileHandle(forUpdating: databaseURL)
        // Page 1 keeps the header and the schema; the damage is in a page after it.
        try handle.seek(toOffset: 4096 * 2)
        try handle.write(contentsOf: Data(repeating: 0xFF, count: 4096))
        try handle.close()
        let (store, recovery) = try open()
        let moved = try #require(recovery?.movedFile)
        #expect(FileManager.default.fileExists(atPath: moved.path))
        try expectWorkingEmptyStore(store)
    }
}
