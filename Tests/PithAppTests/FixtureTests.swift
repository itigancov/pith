import Foundation
import Testing
@testable import PithApp
@testable import PithNotes

@MainActor
struct FixtureTests {
    @Test func parsesNotesWithTheirTimes() throws {
        let json = #"[{"text": "First\nline", "updatedAt": "2026-11-12T09:00:00Z"}, {"text": "Second", "updatedAt": "2026-11-26T10:42:00Z"}]"#
        let entries = try Fixture.parse(json: Data(json.utf8))
        #expect(entries.map(\.text) == ["First\nline", "Second"])
        #expect(entries[0].updatedAt == Date(timeIntervalSince1970: 1_794_474_000))
    }

    @Test func aTimeWithoutAZoneIsLocal() throws {
        let date = try #require(Fixture.date(from: "2026-11-26T10:42:00"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect((parts.year, parts.month, parts.day, parts.hour, parts.minute) == (2026, 11, 26, 10, 42))
    }

    @Test func anInvalidTimeIsAnError() {
        #expect(throws: Fixture.InvalidDate.self) {
            try Fixture.parse(json: Data(#"[{"text": "x", "updatedAt": "yesterday"}]"#.utf8))
        }
    }

    @Test func theStoreHoldsEveryNoteWithItsTime() throws {
        let early = Date(timeIntervalSince1970: 1_000_000)
        let late = Date(timeIntervalSince1970: 2_000_000)
        let (store, _) = try Fixture.openStore(entries: [Fixture.Entry(text: "Early", updatedAt: early), Fixture.Entry(text: "Late", updatedAt: late)])
        let found = try store.search("")
        #expect(found.map(\.updatedAt) == [late, early])
        #expect(try found.compactMap { try store.note(id: $0.id)?.text } == ["Late", "Early"])
    }
}
