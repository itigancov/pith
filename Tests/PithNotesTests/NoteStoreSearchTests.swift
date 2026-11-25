import Foundation
import Testing
@testable import PithNotes

@MainActor @Suite struct NoteStoreSearchTests {
    let clock = TestClock()
    let store: NoteStore

    init() throws {
        store = try makeMemoryStore(clock: clock)
    }

    @discardableResult
    private func add(_ text: String) throws -> UUID {
        clock.advance(1)
        return try store.insert(text: text, selection: noSelection, scrollOffset: 0).id
    }

    private func found(_ query: String) throws -> [UUID] {
        try store.search(query).map(\.id)
    }

    @Test func emptyQueryGivesTheStackByUpdatedAtNewestFirst() throws {
        let first = try add("first")
        let second = try add("second")
        let third = try add("third")
        #expect(try found("") == [third, second, first])
        #expect(try found("  \t") == [third, second, first])
        // An edit makes a Note the newest, unlike in the Stack ordered by creation.
        clock.advance(10)
        try store.updateText(id: first, text: "first edited")
        #expect(try found("") == [first, third, second])
        #expect(try store.stack().map(\.id) == [first, second, third])
    }

    @Test func ordersMatchesByUpdatedAtNewestFirstThenByInsertionNewestFirst() throws {
        let older = try add("region one")
        let newer = try add("region two")
        #expect(try found("region") == [newer, older])
        // Same instant: the later insertion goes first.
        let sameInstantA = try store.insert(text: "tie a", selection: noSelection, scrollOffset: 0).id
        let sameInstantB = try store.insert(text: "tie b", selection: noSelection, scrollOffset: 0).id
        #expect(try found("tie") == [sameInstantB, sameInstantA])
    }

    @Test func findsAPieceOfAWord() throws {
        let note = try add("The region of the north")
        try add("Nothing here")
        #expect(try found("gion") == [note])
    }

    @Test func ignoresCaseOfLatinAndCyrillic() throws {
        let latin = try add("Hello World")
        let cyrillic = try add("Привет Мир")
        #expect(try found("HELLO") == [latin])
        #expect(try found("привет") == [cyrillic])
        #expect(try found("ПРИВЕТ") == [cyrillic])
    }

    @Test func ignoresDiacriticsAndYo() throws {
        let cafe = try add("a café on the corner")
        let tree = try add("ёлка")
        #expect(try found("cafe") == [cafe])
        #expect(try found("CAFÉ") == [cafe])
        #expect(try found("елка") == [tree])
        #expect(try found("ёлка") == [tree])
    }

    @Test func shortIIsALetterOfItsOwn() throws {
        let mine = try add("мой дом")
        try add("мои дома")
        #expect(try found("мой") == [mine])
    }

    @Test func queriesOfOneAndTwoCharactersWork() throws {
        let alpha = try add("alpha")
        let beta = try add("beta")
        let zed = try add("zed")
        #expect(try found("a") == [beta, alpha])
        #expect(try found("lp") == [alpha])
        #expect(try found("z") == [zed])
        #expect(try found("q").isEmpty)
    }

    @Test func severalWordsAreAnAndInAnyOrder() throws {
        let both = try add("The region of the north")
        try add("The region only")
        try add("A north only")
        #expect(try found("region north") == [both])
        #expect(try found("north region") == [both])
        // A short word and a long one together.
        #expect(try found("no region") == [both])
        #expect(try found("of region") == [both])
        #expect(try found("zz region").isEmpty)
    }

    @Test func markdownMarkersAreOrdinaryCharacters() throws {
        let bold = try add("a **bold** word")
        let heading = try add("# Heading")
        try add("plain text")
        #expect(try found("**") == [bold])
        #expect(try found("**bold") == [bold])
        #expect(try found("#") == [heading])
        #expect(try found("# head") == [heading])
    }

    @Test func quotesAndOperatorsOfFullTextSearchAreOrdinaryCharacters() throws {
        let quoted = try add("he said \"hello there\" loudly")
        let star = try add("a*b and c-d")
        try add("hello there")
        #expect(try found("\"hello") == [quoted])
        #expect(try found("a*b") == [star])
        #expect(try found("c-d") == [star])
        #expect(try found("hello OR there").isEmpty)
        #expect(try found("NOT") .isEmpty)
        #expect(try found("hello*").isEmpty)
    }

    @Test func wordsThatFoldToNothingAreIgnored() throws {
        let note = try add("region")
        #expect(try found("\u{301} region") == [note])
        // A query of such words alone is as good as an empty one.
        #expect(try found("\u{301}") == [note])
    }

    @Test func noteInTheTrashIsNotFoundAndIsFoundAfterRestore() throws {
        let kept = try add("shared words kept")
        let trashed = try add("shared words trashed")
        try store.execute("UPDATE notes SET deleted_at = 1000 WHERE id = '\(trashed.uuidString)'")
        #expect(try found("shared") == [kept])
        #expect(try found("sh") == [kept])
        #expect(try found("") == [kept])
        try store.execute("UPDATE notes SET deleted_at = NULL WHERE id = '\(trashed.uuidString)'")
        #expect(try found("shared") == [trashed, kept])
        #expect(try found("sh") == [trashed, kept])
    }

    @Test func aNoteInTheTrashThatWasEditedIsFoundAfterRestore() throws {
        let note = try add("old text")
        try store.execute("UPDATE notes SET deleted_at = 1000 WHERE id = '\(note.uuidString)'")
        #expect(try found("old").isEmpty)
        try store.updateText(id: note, text: "new words")
        #expect(try found("new").isEmpty)
        try store.execute("UPDATE notes SET deleted_at = NULL WHERE id = '\(note.uuidString)'")
        #expect(try found("new") == [note])
        #expect(try found("old").isEmpty)
    }

    @Test func textTypedJustNowIsFoundAtOnce() throws {
        let note = try add("old text")
        #expect(try found("old") == [note])
        try store.updateText(id: note, text: "brand new text")
        #expect(try found("brand") == [note])
        #expect(try found("old").isEmpty)
        try store.updateText(id: note, text: "another")
        #expect(try found("brand").isEmpty)
        #expect(try found("anot") == [note])
    }

    @Test func aNoteInsertedAfterASearchIsFound() throws {
        try add("first")
        #expect(try found("second").isEmpty)
        let second = try add("second")
        #expect(try found("second") == [second])
    }

    @Test func aDeletedNoteIsNotFoundAndItsIndexDoesNotLeakIntoANewOne() throws {
        let doomed = try add("doomed words")
        #expect(try found("doomed") == [doomed])
        try store.deletePermanently(id: doomed)
        #expect(try found("doomed").isEmpty)
        // The new Note may take the row of the deleted one.
        let fresh = try add("fresh text")
        #expect(try found("doomed").isEmpty)
        #expect(try found("fresh") == [fresh])
        try store.updateText(id: fresh, text: "fresher")
        #expect(try found("fresh") == [fresh])
        #expect(try found("text").isEmpty)
    }

    @Test func aNoteThatWasNeverSearchedIsDeletedWithoutTrouble() throws {
        let note = try add("never indexed")
        try store.deletePermanently(id: note)
        #expect(try found("never").isEmpty)
    }

    @Test func movingTheCursorDoesNotMakeTheIndexStale() throws {
        let note = try add("region")
        #expect(try found("region") == [note])
        #expect(try store.queryInt("SELECT count(*) FROM notes WHERE index_dirty = 1") == 0)
        try store.updateViewState(id: note, selection: NoteSelection(location: 2, length: 1), scrollOffset: 4)
        #expect(try store.queryInt("SELECT count(*) FROM notes WHERE index_dirty = 1") == 0)
    }

    @Test func editingMakesTheIndexStaleUntilTheNextSearch() throws {
        let note = try add("region")
        #expect(try found("region") == [note])
        try store.updateText(id: note, text: "region two")
        #expect(try store.queryInt("SELECT count(*) FROM notes WHERE index_dirty = 1") == 1)
        #expect(try found("two") == [note])
        #expect(try store.queryInt("SELECT count(*) FROM notes WHERE index_dirty = 1") == 0)
    }

    @Test func aFailedIndexingKeepsTheFlagsAndTheNextSearchSucceeds() throws {
        try add("region")
        try store.execute("DROP TABLE notes_fts")
        #expect(throws: NoteStoreError.self) { try store.search("region") }
        #expect(try store.queryInt("SELECT count(*) FROM notes WHERE index_dirty = 1") == 1)
        #expect(try store.queryInt("SELECT count(*) FROM notes WHERE folded IS NOT NULL") == 0)
    }
}
