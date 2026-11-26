import Foundation
import Testing
@testable import PithNotes

@MainActor @Suite struct NoteStoreTrashTests {
    let clock = TestClock()
    let store: NoteStore

    init() throws {
        store = try makeMemoryStore(clock: clock)
    }

    @discardableResult
    private func insert(_ text: String) throws -> Note {
        clock.advance(10)
        return try store.insert(text: text, selection: noSelection, scrollOffset: 0)
    }

    @Test func movingToTheTrashGivesEveryNoteTheSameDeletedAtAndLeavesUpdatedAt() throws {
        let a = try insert("alpha")
        let b = try insert("beta")
        let c = try insert("gamma")
        clock.advance(100)
        let deletedAt = try store.moveToTrash(ids: [a.id, c.id])
        #expect(deletedAt == clock.date)
        #expect(try store.note(id: a.id)?.deletedAt == deletedAt)
        #expect(try store.note(id: c.id)?.deletedAt == deletedAt)
        #expect(try store.note(id: a.id)?.updatedAt == a.updatedAt)
        #expect(try store.note(id: b.id)?.deletedAt == nil)
    }

    @Test func aNoteInTheTrashIsNotInTheStackOrSearch() throws {
        let a = try insert("alpha invoice")
        let b = try insert("beta invoice")
        try store.moveToTrash(ids: [a.id])
        #expect(try store.stack().map(\.id) == [b.id])
        #expect(try store.search("invoice").map(\.id) == [b.id])
        #expect(try store.search("").map(\.id) == [b.id])
    }

    @Test func missingAndAlreadyTrashedIdsAreSkipped() throws {
        let a = try insert("alpha")
        clock.advance(10)
        let first = try store.moveToTrash(ids: [a.id])
        clock.advance(10)
        try store.moveToTrash(ids: [a.id, UUID()])
        #expect(try store.note(id: a.id)?.deletedAt == first)
    }

    @Test func restoringPutsTheNoteBackInItsPlaceWithItsUpdatedAt() throws {
        let a = try insert("alpha invoice")
        let b = try insert("beta")
        let c = try insert("gamma")
        // Searching indexes the Notes, so the entry of `a` must come back too.
        #expect(try store.search("invoice").count == 1)
        clock.advance(100)
        try store.moveToTrash(ids: [a.id])
        clock.advance(100)
        try store.restore(ids: [a.id])
        #expect(try store.stack().map(\.id) == [a.id, b.id, c.id])
        #expect(try store.note(id: a.id)?.deletedAt == nil)
        #expect(try store.note(id: a.id)?.updatedAt == a.updatedAt)
        #expect(try store.search("invoice").map(\.id) == [a.id])
    }

    @Test func theTrashListsTheNewestDeletionFirstAndCountsIt() throws {
        let a = try insert("alpha")
        let b = try insert("beta")
        let c = try insert("gamma")
        #expect(try store.trashCount() == 0)
        clock.advance(10)
        try store.moveToTrash(ids: [b.id])
        clock.advance(10)
        // Same instant: the later row first.
        try store.moveToTrash(ids: [a.id, c.id])
        let trash = try store.trash()
        #expect(trash.map(\.id) == [c.id, a.id, b.id])
        #expect(trash.allSatisfy { $0.deletedAt != nil })
        #expect(try store.trashCount() == 3)
    }

    @Test func emptyingTheTrashDeletesOnlyTheTrashAndItsIndexEntries() throws {
        let a = try insert("alpha secret")
        let b = try insert("beta")
        #expect(try store.search("secret").count == 1)
        try store.moveToTrash(ids: [a.id])
        #expect(try store.emptyTrash() == 1)
        #expect(try store.trash().isEmpty)
        #expect(try store.note(id: a.id) == nil)
        #expect(try store.stack().map(\.id) == [b.id])
        // The new Note may take the row number of the old one; the old text must not find it.
        let fresh = try insert("something else")
        #expect(try store.search("secret").isEmpty)
        #expect(try store.search("else").map(\.id) == [fresh.id])
        #expect(try store.emptyTrash() == 0)
    }

    @Test func deletingEmptyNotesLeavesTheTrash() throws {
        let a = try insert("   ")
        try store.moveToTrash(ids: [a.id])
        try store.deleteEmptyNotes()
        #expect(try store.trashCount() == 1)
    }
}
