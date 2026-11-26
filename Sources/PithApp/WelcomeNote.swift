import Foundation

/// The text of the Note a new user finds in the Stack: the markup and the main Shortcuts, with the values they have now.
enum WelcomeNote {
    /// `label` is a Shortcut written as chips with no spaces, such as "⌥Space" or "⇧⌘[". ⌘B, ⇧⌘U, ⇧⌘J, ⌘Z and ⌘, cannot be
    /// reassigned, so they are written as they are.
    static func text(label: (ShortcutAction) -> String) -> String {
        """
        # Welcome to Pith
        A scratchpad over any app. Paste, tidy up, copy, get back to work.

        - [ ] Press \(label(.hotkey)) from any app to open Pith, Esc to hide it
        - [ ] Press \(label(.newNote)) for a new note, \(label(.previousNote)) and \(label(.nextNote)) to page through
        - [x] Read this note

        ## Markup stays visible
        Type **bold** with ⌘B, ==highlight== with ⇧⌘U, `code` with ⇧⌘J.
        - \(label(.goToLatest)) jumps to the latest note, \(label(.searchNotes)) searches them all
        - \(label(.moveToTrash)) moves a note to the Trash, ⌘Z brings it back

        > Change any shortcut in Settings, ⌘,

        ```text
        Done with this note? \(label(.moveToTrash))
        ```
        """
    }
}
