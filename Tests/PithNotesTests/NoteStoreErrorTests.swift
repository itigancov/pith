import Testing
@testable import PithNotes

struct NoteStoreErrorTests {
    @Test func localizedDescriptionIsASentenceForTheAlert() {
        let busy = NoteStoreError.sqlite(code: 5, message: "database is locked")
        #expect(busy.localizedDescription == "SQLite error 5: database is locked.")
        let newer = NoteStoreError.newerSchema(found: 3, supported: 1)
        #expect(newer.localizedDescription.hasSuffix("."))
        #expect(newer.localizedDescription.contains("newer version of Pith"))
    }
}
