import Foundation

/// A selection in UTF-16 units, as `NSRange`, without the Foundation type in the model.
nonisolated public struct NoteSelection: Sendable, Equatable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

nonisolated public struct Note: Sendable, Equatable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var selection: NoteSelection
    public var scrollOffset: Double

    public init(
        id: UUID, text: String, createdAt: Date, updatedAt: Date, deletedAt: Date?,
        selection: NoteSelection, scrollOffset: Double
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.selection = selection
        self.scrollOffset = scrollOffset
    }

    /// Whether `text` makes an empty Note: nothing, or only spaces and line breaks. One that is left so stops being a Note.
    public static func isEmpty(text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The first non-empty line without its leading Block Marker, trimmed. Empty for an empty text.
    public var title: String {
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            return Self.withoutMarker(trimmed).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    static func withoutMarker(_ line: String) -> String {
        var rest = Substring(line)
        if rest.first == ">" {
            return rest.dropFirst().first == " " ? String(rest.dropFirst(2)) : line
        }
        if rest.first == "#" {
            let hashes = rest.prefix { $0 == "#" }
            guard hashes.count <= 6, rest.dropFirst(hashes.count).first == " " else { return line }
            return String(rest.dropFirst(hashes.count + 1))
        }
        guard let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " else { return line }
        rest = rest.dropFirst(2)
        let trimmed = rest.drop { $0 == " " }
        for box in ["[ ] ", "[x] ", "[X] "] where trimmed.hasPrefix(box) {
            return String(trimmed.dropFirst(box.count))
        }
        return String(rest)
    }
}

/// What the Stack needs of a Note: no text.
nonisolated public struct NoteSummary: Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
