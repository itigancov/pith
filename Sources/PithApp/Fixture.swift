import Foundation
import PithNotes

/// Notes for `-PithFixture`: a `.json` file with several, each with the time of its last edit.
enum Fixture {
    struct Entry: Equatable {
        var text: String
        var updatedAt: Date
    }

    private struct RawEntry: Decodable {
        var text: String
        var updatedAt: String
    }

    struct InvalidDate: Error, CustomStringConvertible {
        var value: String
        var description: String { "not an ISO 8601 date: \(value)" }
    }

    /// `[{"text": "…", "updatedAt": "2026-11-26T10:42:00"}, …]`, oldest first: the order of creation.
    static func parse(json: Data) throws -> [Entry] {
        try JSONDecoder().decode([RawEntry].self, from: json).map { raw in
            guard let date = date(from: raw.updatedAt) else { throw InvalidDate(value: raw.updatedAt) }
            return Entry(text: raw.text, updatedAt: date)
        }
    }

    /// ISO 8601; without a zone (`2026-11-26T10:42:00`) it is the time on this Mac's clock.
    static func date(from string: String) -> Date? {
        let withZone = ISO8601DateFormatter()
        if let date = withZone.date(from: string) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: string)
    }

    /// An in-memory database with these Notes, each created and last edited at its `updatedAt`.
    static func openStore(entries: [Entry]) throws -> (store: NoteStore, recovery: CorruptionRecovery?) {
        let clock = Clock()
        let opened = try NoteStore.open(at: .memory, now: { clock.date ?? Date() })
        for entry in entries {
            clock.date = entry.updatedAt
            _ = try opened.store.insert(text: entry.text, selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)
        }
        // Real time again for whatever is edited next.
        clock.date = nil
        return opened
    }

    private final class Clock {
        var date: Date?
    }
}
