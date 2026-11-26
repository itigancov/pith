import AppKit

/// The alerts about the Trash that more than one screen shows.
enum TrashAlerts {
    /// "Empty Trash?" with the number of Notes; the destructive answer is the second button.
    static func makeEmptyAlert(count: Int) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = "\(count == 1 ? "1 note will" : "\(count) notes will") be deleted for good. You can’t undo this."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Empty Trash").hasDestructiveAction = true
        return alert
    }

    /// Asks as a sheet on `window`; `completion` gets whether the user confirmed.
    static func confirmEmpty(count: Int, in window: NSWindow, completion: @escaping (Bool) -> Void) {
        makeEmptyAlert(count: count).beginSheetModal(for: window) { response in
            completion(response == .alertSecondButtonReturn)
        }
    }

    /// The answer of an alert from `makeEmptyAlert`: whether it confirmed.
    static func confirms(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertSecondButtonReturn
    }
}
