import Observation
import PithNotes

/// The Trash row of Settings: how many Notes are in the Trash, and Empty Trash.
@Observable
final class SettingsTrash {
    private(set) var count = 0

    @ObservationIgnored private let store: () -> NoteStore?

    init(store: @escaping () -> NoteStore?) {
        self.store = store
    }

    /// "Empty", "1 note", "3 notes".
    static func label(count: Int) -> String {
        count == 0 ? "Empty" : count == 1 ? "1 note" : "\(count) notes"
    }

    var label: String { Self.label(count: count) }
    var canEmpty: Bool { count > 0 }

    /// Deletes every Note of the Trash for good and reads the count again.
    func empty() throws {
        defer { refresh() }
        try store()?.emptyTrash()
    }

    /// Reads the count again; without a store (the Notes did not open) the Trash is empty.
    func refresh() {
        count = (try? store()?.trashCount()) ?? 0
    }
}
