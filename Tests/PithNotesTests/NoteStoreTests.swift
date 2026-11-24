import Foundation
import Testing
@testable import PithNotes

@MainActor @Suite struct NoteStoreTests {
    let clock = TestClock()
    let store: NoteStore

    init() throws {
        store = try makeMemoryStore(clock: clock)
    }

    @Test func insertedNoteReadsBack() throws {
        let selection = NoteSelection(location: 3, length: 2)
        let note = try store.insert(text: "Hello\nworld", selection: selection, scrollOffset: 12.5)
        #expect(note.text == "Hello\nworld")
        #expect(note.createdAt == clock.date)
        #expect(note.updatedAt == clock.date)
        #expect(note.deletedAt == nil)
        #expect(try store.note(id: note.id) == note)
        #expect(try store.note(id: note.id)?.selection == selection)
        #expect(try store.note(id: note.id)?.scrollOffset == 12.5)
    }

    @Test func unknownNoteIsNil() throws {
        #expect(try store.note(id: UUID()) == nil)
    }

    @Test func textSurvivesUnicodeAndLongInput() throws {
        let text = String(repeating: "Ёж 🙂 é\n", count: 20_000)
        let note = try store.insert(text: text, selection: noSelection, scrollOffset: 0)
        #expect(try store.note(id: note.id)?.text == text)
    }

    @Test func stackOrdersByCreationThenInsertion() throws {
        let first = try store.insert(text: "a", selection: noSelection, scrollOffset: 0)
        // Same instant: the order of insertion decides.
        let second = try store.insert(text: "b", selection: noSelection, scrollOffset: 0)
        clock.advance(10)
        let third = try store.insert(text: "c", selection: noSelection, scrollOffset: 0)
        #expect(try store.stack().map(\.id) == [first.id, second.id, third.id])
    }

    @Test func editingDoesNotMoveANoteInTheStack() throws {
        let first = try store.insert(text: "a", selection: noSelection, scrollOffset: 0)
        clock.advance(10)
        let second = try store.insert(text: "b", selection: noSelection, scrollOffset: 0)
        clock.advance(10)
        try store.updateText(id: first.id, text: "a edited")
        #expect(try store.stack().map(\.id) == [first.id, second.id])
    }

    @Test func stackSkipsNotesInTheTrash() throws {
        let kept = try store.insert(text: "kept", selection: noSelection, scrollOffset: 0)
        let trashed = try store.insert(text: "trashed", selection: noSelection, scrollOffset: 0)
        try store.execute("UPDATE notes SET deleted_at = 1000 WHERE id = '\(trashed.id.uuidString)'")
        #expect(try store.stack().map(\.id) == [kept.id])
        #expect(try store.note(id: trashed.id)?.deletedAt == Date(timeIntervalSince1970: 1))
    }

    @Test func rowWithAnUnreadableIDIsAnErrorNotARandomID() throws {
        try store.execute("INSERT INTO notes(id, text, created_at, updated_at) VALUES('not-a-uuid', '', 0, 0)")
        #expect(throws: NoteStoreError.self) { try store.stack() }
    }

    @Test func stackSummariesCarryDatesOnly() throws {
        let note = try store.insert(text: "a", selection: noSelection, scrollOffset: 0)
        #expect(try store.stack() == [NoteSummary(id: note.id, createdAt: note.createdAt, updatedAt: note.updatedAt, deletedAt: nil)])
    }

    @Test func updateTextTouchesUpdatedAt() throws {
        let note = try store.insert(text: "a", selection: noSelection, scrollOffset: 0)
        clock.advance(5)
        try store.updateText(id: note.id, text: "ab")
        let read = try #require(try store.note(id: note.id))
        #expect(read.text == "ab")
        #expect(read.updatedAt == clock.date)
        #expect(read.createdAt == note.createdAt)
    }

    @Test func updateViewStateLeavesUpdatedAtAlone() throws {
        let note = try store.insert(text: "a", selection: noSelection, scrollOffset: 0)
        clock.advance(5)
        try store.updateViewState(id: note.id, selection: NoteSelection(location: 1, length: 0), scrollOffset: 40)
        let read = try #require(try store.note(id: note.id))
        #expect(read.selection == NoteSelection(location: 1, length: 0))
        #expect(read.scrollOffset == 40)
        #expect(read.updatedAt == note.updatedAt)
        #expect(read.text == "a")
    }

    @Test func deletePermanentlyRemovesTheNote() throws {
        let note = try store.insert(text: "a", selection: noSelection, scrollOffset: 0)
        let other = try store.insert(text: "b", selection: noSelection, scrollOffset: 0)
        try store.deletePermanently(id: note.id)
        #expect(try store.note(id: note.id) == nil)
        #expect(try store.stack().map(\.id) == [other.id])
    }

    @Test func freshDatabaseIsAtTheLatestSchemaVersion() throws {
        #expect(try store.queryInt("PRAGMA user_version") == NoteStore.schemaVersion)
        #expect(NoteStore.schemaVersion >= 1)
    }
}
