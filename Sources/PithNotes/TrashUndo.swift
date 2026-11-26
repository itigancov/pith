import Foundation

/// The toast after Notes went to the Trash: what it says, which Notes Undo brings back, and how long it lasts. No AppKit
/// and no timers: the caller gives the time and calls `tick` when the term may have ended.
nonisolated public struct TrashUndo: Sendable, Equatable {
    /// `toast.duration`, in seconds.
    public static let duration: TimeInterval = 5

    private var ids: [UUID] = []
    private var expiresAt: Date?
    private var isPaused = false

    public init() {}

    /// A toast is up and Undo works.
    public var isShowing: Bool { !ids.isEmpty }

    /// "Note moved to Trash", "3 notes moved to Trash"; `nil` without a toast.
    public var text: String? {
        switch ids.count {
        case 0: nil
        case 1: "Note moved to Trash"
        default: "\(ids.count) notes moved to Trash"
        }
    }

    /// `ids` went to the Trash: a new toast replaces the one before, with a full term from `now`.
    public mutating func deleted(ids: [UUID], now: Date) {
        self.ids = ids
        isPaused = false
        expiresAt = now.addingTimeInterval(Self.duration)
    }

    /// The mouse is on the toast: it does not end.
    public mutating func pause() {
        isPaused = true
    }

    /// The mouse left: a full term from `now`.
    public mutating func resume(now: Date) {
        guard isPaused else { return }
        isPaused = false
        expiresAt = now.addingTimeInterval(Self.duration)
    }

    /// Ends the toast if its term is over.
    public mutating func tick(now: Date) {
        guard !isPaused, let expiresAt, now >= expiresAt else { return }
        dismiss()
    }

    public mutating func dismiss() {
        ids = []
        expiresAt = nil
        isPaused = false
    }

    /// The Notes to bring back and the end of the toast; `nil` when there is no toast (or its term is over).
    public mutating func undo(now: Date) -> [UUID]? {
        tick(now: now)
        guard isShowing else { return nil }
        let restored = ids
        dismiss()
        return restored
    }
}
