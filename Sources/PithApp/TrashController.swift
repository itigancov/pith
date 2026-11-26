import AppKit
import PithNotes

/// Moves the open Note to the Trash and opens the Trash over the Note or Search: the owner of Move to Trash and Show Trash
/// in the menu.
final class TrashController: NSObject, NSMenuItemValidation {
    private let stack: ScreenStack
    private let note: NoteScreen

    /// Whether an alert about the notes is up: the Trash waits until it is answered.
    var isBlocked: () -> Bool = { false }
    /// Puts an alert on the Panel; the Panel's queue in the app.
    var presentAlert: (NSAlert, @escaping (NSApplication.ModalResponse) -> Void) -> Void = { _, _ in }
    /// A write failed: the alert of the Panel says why.
    var presentFailure: (String) -> Void = { _ in }
    /// "Now" for the times of the rows.
    var now: () -> Date = Date.init
    var locale: Locale = .current
    var calendar: Calendar = .current

    init(stack: ScreenStack, note: NoteScreen) {
        self.stack = stack
        self.note = note
    }

    /// ⌘⌫.
    @objc func moveToTrash(_ sender: Any?) {
        guard !isBlocked() else { return }
        if let search = stack.top as? SearchScreen {
            search.moveSelectionToTrash()
            return
        }
        guard stack.top === note else { return }
        note.moveToTrash()
    }

    /// Note › Show Trash: the Trash over the Note, or over Search.
    @objc func showTrash(_ sender: Any?) {
        guard !isBlocked(), canShowTrash, let store = note.store else { return }
        // The Note's last keystrokes are in the store before the Trash reads it.
        note.flush()
        let screen = TrashScreen(store: store, now: now, locale: locale, calendar: calendar)
        screen.presentAlert = { [weak self] alert, answer in self?.presentAlert(alert, answer) }
        screen.onFailure = { [weak self] reason in self?.presentFailure(reason) }
        screen.onClose = { [weak self] restoredAny in self?.note.reloadStack(activateFooter: restoredAny) }
        screen.close = { [weak self, weak screen] in
            guard let self, let screen else { return }
            self.stack.pop(screen)
        }
        stack.push(screen)
    }

    private var canShowTrash: Bool {
        note.isAvailable && (stack.top === note || stack.top is SearchScreen)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if isBlocked() { return false }
        switch item.action {
        case #selector(moveToTrash(_:)):
            if let search = stack.top as? SearchScreen { return search.canMoveToTrash }
            return stack.top === note && note.isAvailable
        case #selector(showTrash(_:)): return canShowTrash
        default: return true
        }
    }
}
