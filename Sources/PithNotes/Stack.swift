import Foundation

/// Which Note ⌘1 jumps to (`LatestMeans` in the settings).
nonisolated public enum Latest: String, Sendable {
    case newest
    case lastEdited = "last-edited"

    /// The Latest Note among `notes`, given in Stack order; `nil` when there are none. A tie on `updatedAt` goes to the later `createdAt`.
    public func id(in notes: [NoteSummary]) -> UUID? {
        switch self {
        case .newest:
            return notes.last?.id
        case .lastEdited:
            return notes.max { ($0.updatedAt, $0.createdAt) < ($1.updatedAt, $1.createdAt) }?.id
        }
    }
}

/// The order the user pages through and where they are in it. A Blank is not in `ids`: it is a position past the last Note.
nonisolated public struct Stack: Sendable, Equatable {
    public enum Position: Sendable, Equatable {
        case note(UUID)
        case blank

        /// The id of the Note; `nil` for the Blank.
        public var noteID: UUID? {
            if case .note(let id) = self { return id }
            return nil
        }
    }

    /// What an operation did.
    public enum Move: Sendable, Equatable {
        /// The open Note changes.
        case moved(from: Position, to: Position)
        /// The same Note stays; the footer shows itself anyway.
        case edge
        /// Nothing at all.
        case none
    }

    /// The Notes in the order they were created.
    public private(set) var ids: [UUID]
    public private(set) var position: Position

    /// - Parameter position: Where to start; the last Note, or a Blank for an empty Stack, by default.
    public init(ids: [UUID], position: Position? = nil) {
        self.ids = ids
        self.position = position ?? ids.last.map { .note($0) } ?? .blank
    }

    private var index: Int? {
        if case .note(let id) = position { return ids.firstIndex(of: id) }
        return nil
    }

    public mutating func next() -> Move {
        guard let index else { return .edge }
        return move(to: index + 1 < ids.count ? .note(ids[index + 1]) : .blank)
    }

    public mutating func previous() -> Move {
        if position == .blank { return ids.last.map { move(to: .note($0)) } ?? .edge }
        guard let index, index > 0 else { return .edge }
        return move(to: .note(ids[index - 1]))
    }

    public mutating func newNote() -> Move {
        position == .blank ? .none : move(to: .blank)
    }

    /// Goes to `id`, the Latest Note; `nil` when there is none.
    public mutating func latest(_ id: UUID?) -> Move {
        guard let id else { return .none }
        return show(id)
    }

    /// Goes to the Note `id`, for Search and the Trash.
    public mutating func show(_ id: UUID) -> Move {
        guard ids.contains(id) else { return .none }
        return position == .note(id) ? .edge : move(to: .note(id))
    }

    /// The Blank got its first text: it is the last Note now.
    public mutating func noteCreated(_ id: UUID) {
        ids.append(id)
        position = .note(id)
    }

    /// The Note left the Stack (it was left empty). The open one gives way to the next, else the previous, else the Blank.
    public mutating func remove(_ id: UUID) {
        guard let removed = ids.firstIndex(of: id) else { return }
        ids.remove(at: removed)
        guard position == .note(id) else { return }
        position = ids.indices.contains(removed) ? .note(ids[removed]) : ids.last.map { .note($0) } ?? .blank
    }

    /// Several Notes left the Stack (they went to the Trash). The open one, if among them, gives way to the next that stays,
    /// else the previous, else the Blank.
    public mutating func remove(_ gone: [UUID]) {
        let gone = Set(gone)
        guard case .note(let open) = position, gone.contains(open), let at = ids.firstIndex(of: open) else {
            ids.removeAll { gone.contains($0) }
            return
        }
        let staying = ids.enumerated().filter { !gone.contains($0.element) }
        if let next = staying.first(where: { $0.offset > at }) ?? staying.last {
            position = .note(next.element)
        } else {
            position = .blank
        }
        ids = staying.map(\.element)
    }

    /// The Stack as the store has it now, after Notes came back from the Trash. The Note on screen stays open.
    public mutating func reload(ids new: [UUID]) {
        ids = new
        if case .note(let id) = position, !new.contains(id) { position = new.last.map { .note($0) } ?? .blank }
    }

    private mutating func move(to new: Position) -> Move {
        let old = position
        position = new
        return .moved(from: old, to: new)
    }
}
