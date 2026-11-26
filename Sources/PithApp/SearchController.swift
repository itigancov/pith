import AppKit
import PithNotes

/// Opens Search over the Note and finds the next match of the last query in it: the owner of what Find in the menu does.
final class SearchController: NSObject, NSMenuItemValidation {
    private let stack: ScreenStack
    private let note: NoteScreen
    /// The last non-empty query Search was closed with, by any way; ⌘G looks for it. Kept for the session only.
    private(set) var lastQuery: SearchQuery?

    /// What ⌘G does when there is nothing to find.
    var beep: () -> Void = { NSSound.beep() }
    /// Whether an alert about the notes is up: Find waits until it is answered.
    var isBlocked: () -> Bool = { false }
    /// "Now" for the times of the rows.
    var now: () -> Date = Date.init
    var locale: Locale = .current
    var calendar: Calendar = .current

    init(stack: ScreenStack, note: NoteScreen) {
        self.stack = stack
        self.note = note
    }

    private var search: SearchScreen? { stack.top as? SearchScreen }

    /// ⌘F: Search over the Note, or the text of its field selected when it is already open.
    @objc func find(_ sender: Any?) {
        guard !isBlocked() else { return }
        if let search {
            search.selectQueryText()
            return
        }
        guard stack.top === note, let store = note.store else { return }
        // The Note's last keystrokes are in the store before the first search.
        note.flush()
        let screen = SearchScreen(store: store, now: now, locale: locale, calendar: calendar)
        screen.onDismiss = { [weak self] raw in
            let query = SearchQuery(raw)
            if !query.isEmpty { self?.lastQuery = query }
        }
        screen.onOpen = { [weak self, weak screen] id, query in
            guard let self, let screen else { return }
            self.stack.pop(screen)
            self.note.open(id: id, query: query.isEmpty ? nil : query)
        }
        screen.close = { [weak self, weak screen] in
            guard let self, let screen else { return }
            self.stack.pop(screen)
        }
        stack.push(screen)
    }

    /// ⌘G.
    @objc func findNext(_ sender: Any?) { findMatch(backwards: false) }

    /// ⇧⌘G.
    @objc func findPrevious(_ sender: Any?) { findMatch(backwards: true) }

    private func findMatch(backwards: Bool) {
        guard !isBlocked(), stack.top === note else { return }
        guard let lastQuery, note.findNext(lastQuery, backwards: backwards) else {
            beep()
            return
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if isBlocked() { return false }
        switch item.action {
        case #selector(find(_:)): return note.store != nil && (stack.top === note || search != nil)
        case #selector(findNext(_:)), #selector(findPrevious(_:)): return stack.top === note
        default: return true
        }
    }
}
