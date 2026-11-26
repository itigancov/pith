import PithNotes
import Testing
@testable import PithApp

struct SettingsTrashTests {
    @Test func labelCountsTheNotes() {
        #expect(SettingsTrash.label(count: 0) == "Empty")
        #expect(SettingsTrash.label(count: 1) == "1 note")
        #expect(SettingsTrash.label(count: 3) == "3 notes")
    }

    @Test func countFollowsTheStoreAndEmptyingIt() throws {
        let store = try NoteStore.open(at: .memory).store
        for index in 0..<3 {
            let note = try store.insert(text: "note \(index)", selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)
            _ = try store.moveToTrash(ids: [note.id])
        }
        let trash = SettingsTrash(store: { store })
        #expect(trash.label == "Empty")
        trash.refresh()
        #expect(trash.label == "3 notes")
        #expect(trash.canEmpty)
        try trash.empty()
        #expect(try store.trashCount() == 0)
        #expect(trash.label == "Empty")
        #expect(!trash.canEmpty)
    }

    @Test func withoutAStoreTheTrashIsEmpty() {
        let trash = SettingsTrash(store: { nil })
        trash.refresh()
        #expect(trash.label == "Empty")
        #expect(!trash.canEmpty)
    }
}
