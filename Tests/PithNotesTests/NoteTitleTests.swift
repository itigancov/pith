import Foundation
import Testing
@testable import PithNotes

@Suite struct NoteTitleTests {
    private func title(_ text: String) -> String {
        Note(
            id: UUID(), text: text, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
            deletedAt: nil, selection: NoteSelection(location: 0, length: 0), scrollOffset: 0
        ).title
    }

    @Test func firstLineIsTheTitle() {
        #expect(title("Groceries\nmilk") == "Groceries")
    }

    @Test func emptyTextHasEmptyTitle() {
        #expect(title("") == "")
        #expect(title("  \n\n \t\n") == "")
    }

    @Test func skipsBlankLines() {
        #expect(title("\n  \nHello  \nworld") == "Hello")
    }

    @Test(arguments: [
        ("# Heading", "Heading"),
        ("### Deep", "Deep"),
        ("- item", "item"),
        ("* star", "star"),
        ("> quote", "quote"),
        ("- [ ] task", "task"),
        ("- [x] done", "done"),
        ("  - [ ]   padded  ", "padded"),
        ("#hashtag", "#hashtag"),
    ])
    func stripsLeadingMarkers(text: String, expected: String) {
        #expect(title(text) == expected)
    }
}
