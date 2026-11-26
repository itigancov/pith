import Foundation

/// What the footer of the Stack shows: the window of dots and the counter. Pure; the view only draws it.
nonisolated public enum StackDots {
    public enum Kind: Sendable, Equatable {
        case regular
        case current
        /// The outermost position of the window, small, when there are more Notes beyond it.
        case edge
        /// The Blank, always the current position.
        case blank
    }

    public struct Dot: Sendable, Equatable {
        /// Stable across windows: the id of the Note, or `"blank"`. The view animates a shift by it.
        public var key: String
        public var kind: Kind
    }

    /// The most dots shown.
    public static let windowSize = 7
    public static let blankKey = "blank"

    /// The window of dots around `position`: up to 7, the current one in the middle unless the Stack ends first.
    public static func layout(ids: [UUID], position: Stack.Position) -> [Dot] {
        let blank = position == .blank
        let total = ids.count + (blank ? 1 : 0)
        let current: Int
        if case .note(let id) = position { current = ids.firstIndex(of: id) ?? 0 } else { current = ids.count }
        let size = min(windowSize, total)
        let start = min(max(current - windowSize / 2, 0), total - size)
        return (start..<start + size).map { index in
            let key = index < ids.count ? ids[index].uuidString : blankKey
            if index == current { return Dot(key: key, kind: blank ? .blank : .current) }
            let isWindowEdge = (index == start && start > 0) || (index == start + size - 1 && start + size < total)
            return Dot(key: key, kind: isWindowEdge ? .edge : .regular)
        }
    }

    /// "12 / 40", "Latest · 10 / 10", "New".
    public static func counter(ids: [UUID], position: Stack.Position, latest: UUID?) -> String {
        guard case .note(let id) = position, let index = ids.firstIndex(of: id) else { return "New" }
        let text = "\(index + 1) / \(ids.count)"
        return id == latest ? "Latest · " + text : text
    }

    /// What VoiceOver says: "Note 12 of 40", "Latest, note 10 of 10", "New note".
    public static func spoken(ids: [UUID], position: Stack.Position, latest: UUID?) -> String {
        guard case .note(let id) = position, let index = ids.firstIndex(of: id) else { return "New note" }
        let numbers = "\(index + 1) of \(ids.count)"
        return id == latest ? "Latest, note " + numbers : "Note " + numbers
    }
}
