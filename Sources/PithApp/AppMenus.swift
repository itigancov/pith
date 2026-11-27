import AppKit
import PithEditor
import PithNotes

/// What the menus need from the Panel; `PanelController` is the live one, tests substitute a fake.
protocol PanelHosting: AnyObject {
    var screens: ScreenStack { get }
    /// Shown or on its way in.
    var isShown: Bool { get }
    /// The Panel is the key window: the keys and menu items of the Panel work only then.
    var isKey: Bool { get }
    /// An alert waits in the Panel or is up on it.
    var hasAlert: Bool { get }
    /// Shows the Panel, or just brings it forward if it is shown already.
    func reveal()
    func hide()
    func resetPanelFrame(_ sender: Any?)
}

/// The menus of the app: the main menu, the menu of the menu bar icon and the context menu of the editor, built from
/// one place and wired to the Panel, the Note screen, Search, the Trash and the Shortcuts. They are the target of every
/// item of their own, so that one validation decides whether an item is on.
final class AppMenus: NSObject, NSMenuItemValidation, NSMenuDelegate {
    static let repositoryURL = URL(string: "https://github.com/itigancov/pith")!

    private let shortcuts: ShortcutStore
    private let panel: PanelHosting
    private let note: NoteScreen
    private let search: SearchController
    private let trash: TrashController
    private let textSize: TextSizeModel
    /// The menus built so far that the Shortcuts apply to, until they are gone.
    private let live = NSHashTable<NSMenu>.weakObjects()

    /// Opens Settings; while it is `nil` (there is no Settings window yet) the Settings… items are off.
    var openSettings: (() -> Void)?

    init(shortcuts: ShortcutStore, panel: PanelHosting, note: NoteScreen, search: SearchController, trash: TrashController, textSize: TextSizeModel) {
        self.shortcuts = shortcuts
        self.panel = panel
        self.note = note
        self.search = search
        self.trash = trash
        self.textSize = textSize
        super.init()
        note.contextMenu = { [weak self] in self?.makeContextMenu() ?? NSMenu() }
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutsDidChange), name: .shortcutsDidChange, object: shortcuts)
    }

    // MARK: Building

    private struct Row {
        var title: String
        var action: Selector?
        var key: String = ""
        var modifiers: NSEvent.ModifierFlags = .command
        /// The name of its Shortcut action, or of the item for Show Trash.
        var identifier: String?
        var target: AppMenus?
    }

    private func add(_ row: Row, to menu: NSMenu) {
        let item = menu.addItem(withTitle: row.title, action: row.action, keyEquivalent: row.key)
        if !row.key.isEmpty { item.keyEquivalentModifierMask = row.modifiers }
        item.identifier = row.identifier.map { NSUserInterfaceItemIdentifier($0) }
        item.target = row.target
        // The key equivalents are the layout-independent ones of the Shortcuts; the system must not translate them.
        item.allowsAutomaticKeyEquivalentLocalization = false
    }

    private func menu(title: String) -> NSMenu { NSMenu(title: title) }

    private func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.allowsAutomaticKeyEquivalentLocalization = false
        let sub = menu(title: title)
        item.submenu = sub
        return sub
    }

    /// Pith, Edit, Format, Note, View and Window. The system shows it while Pith is active; it holds the keys of the Panel.
    func makeMainMenu() -> NSMenu {
        let main = menu(title: "Main")

        let appMenu = submenu(in: main, title: "Pith")
        add(Row(title: "About Pith", action: #selector(showAbout(_:)), target: self), to: appMenu)
        appMenu.addItem(.separator())
        add(Row(title: "Settings…", action: #selector(showSettings(_:)), key: ",", target: self), to: appMenu)
        appMenu.addItem(.separator())
        add(Row(title: "Quit Pith", action: #selector(NSApplication.terminate(_:)), key: "q"), to: appMenu)

        let edit = submenu(in: main, title: "Edit")
        add(Row(title: "Undo", action: Selector(("undo:")), key: "z"), to: edit)
        add(Row(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]), to: edit)
        edit.addItem(.separator())
        add(Row(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"), to: edit)
        add(Row(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"), to: edit)
        add(Row(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"), to: edit)
        add(Row(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a"), to: edit)
        edit.addItem(.separator())
        add(Row(title: "Find Next", action: #selector(findNext(_:)), key: "g", target: self), to: edit)
        add(Row(title: "Find Previous", action: #selector(findPrevious(_:)), key: "g", modifiers: [.command, .shift], target: self), to: edit)

        let format = submenu(in: main, title: "Format")
        let inline: [Row] = [
            Row(title: "Bold", action: #selector(EditorTextView.toggleBold(_:)), key: "b"),
            Row(title: "Italic", action: #selector(EditorTextView.toggleItalic(_:)), key: "i"),
            Row(title: "Highlight", action: #selector(EditorTextView.toggleHighlight(_:)), key: "u", modifiers: [.command, .shift]),
            Row(title: "Strikethrough", action: #selector(EditorTextView.toggleStrikethrough(_:)), key: "u", modifiers: [.command, .option]),
            Row(title: "Code", action: #selector(EditorTextView.toggleCode(_:)), key: "j", modifiers: [.command, .shift]),
            Row(title: "Link", action: #selector(EditorTextView.toggleLink(_:)), key: "k", modifiers: [.command, .shift]),
        ]
        let blocks: [Row] = [
            Row(title: "Heading 1", action: #selector(EditorTextView.toggleHeading1(_:)), key: "1", modifiers: [.command, .control]),
            Row(title: "Heading 2", action: #selector(EditorTextView.toggleHeading2(_:)), key: "2", modifiers: [.command, .control]),
            Row(title: "Heading 3", action: #selector(EditorTextView.toggleHeading3(_:)), key: "3", modifiers: [.command, .control]),
            Row(title: "Bulleted List", action: #selector(EditorTextView.toggleBulletList(_:)), key: "l", modifiers: [.command, .shift]),
            Row(title: "Numbered List", action: #selector(EditorTextView.toggleOrderedList(_:)), key: "l", modifiers: [.command, .option]),
            Row(title: "Task List", action: #selector(EditorTextView.toggleTaskList(_:)), key: "l", modifiers: [.command, .control]),
            Row(title: "Quote", action: #selector(EditorTextView.toggleQuote(_:)), key: "'"),
            Row(title: "Code Block", action: #selector(EditorTextView.toggleCodeBlock(_:)), key: "j", modifiers: [.command, .option, .shift]),
        ]
        for group in [inline, blocks] {
            for row in group { add(row, to: format) }
            format.addItem(.separator())
        }
        add(Row(title: "Indent", action: #selector(NSResponder.indent(_:)), key: "]"), to: format)
        add(Row(title: "Outdent", action: #selector(EditorTextView.outdent(_:)), key: "["), to: format)
        format.addItem(.separator())
        add(Row(title: "Complete Task", action: #selector(EditorTextView.toggleTask(_:)), key: "k"), to: format)

        let noteMenu = submenu(in: main, title: "Note")
        addNoteCommands(to: noteMenu)

        // ⌘= also works, see `performKeyEquivalent(_:)`.
        let view = submenu(in: main, title: "View")
        add(Row(title: "Bigger", action: #selector(increaseTextSize(_:)), key: "+", target: self), to: view)
        add(Row(title: "Smaller", action: #selector(decreaseTextSize(_:)), key: "-", target: self), to: view)
        add(Row(title: "Actual Size", action: #selector(resetTextSize(_:)), key: "0", target: self), to: view)

        let windowMenu = submenu(in: main, title: "Window")
        add(Row(title: "Reset Panel Size", action: #selector(resetPanelSize(_:)), target: self), to: windowMenu)
        add(Row(title: "Close", action: #selector(closeWindow(_:)), key: "w", target: self), to: windowMenu)

        #if DEBUG
        let debug = submenu(in: main, title: "Debug")
        add(Row(title: "Generate 5k Lines", action: #selector(generateBigNote(_:)), target: self), to: debug)
        #endif

        register(main)
        return main
    }

    /// The identifiers are the names of the Shortcut actions, so that the keys and Settings can find these items.
    private func addNoteCommands(to menu: NSMenu) {
        let rows: [Row] = [
            Row(title: "New Note", action: #selector(newNote(_:)), identifier: "newNote", target: self),
            Row(title: "Go to Latest Note", action: #selector(goToLatest(_:)), identifier: "goToLatest", target: self),
            Row(title: "Previous Note", action: #selector(previousNote(_:)), identifier: "previousNote", target: self),
            Row(title: "Next Note", action: #selector(nextNote(_:)), identifier: "nextNote", target: self),
            Row(title: "Search Notes", action: #selector(searchNotes(_:)), identifier: "searchNotes", target: self),
        ]
        for row in rows { add(row, to: menu) }
        menu.addItem(.separator())
        // ⌘⌫ is the Panel's own key too: with the Trash on top the list takes it first, and the item is off.
        add(Row(title: "Move to Trash", action: #selector(moveToTrash(_:)), identifier: "moveToTrash", target: self), to: menu)
        add(Row(title: "Show Trash", action: #selector(showTrash(_:)), identifier: "showTrash", target: self), to: menu)
    }

    /// The menu of the icon in the menu bar. Its keys are only shown; the system does not send them to this menu.
    func makeStatusMenu() -> NSMenu {
        let menu = menu(title: "Pith")
        menu.delegate = self
        let top: [Row] = [
            Row(title: "Open Pith", action: #selector(openPith(_:)), identifier: "hotkey", target: self),
            Row(title: "New Note", action: #selector(menuBarNewNote(_:)), identifier: "newNote", target: self),
            Row(title: "Go to Latest Note", action: #selector(menuBarGoToLatest(_:)), identifier: "goToLatest", target: self),
        ]
        for row in top { add(row, to: menu) }
        menu.addItem(.separator())
        add(Row(title: "Trash", action: #selector(menuBarShowTrash(_:)), identifier: "showTrash", target: self), to: menu)
        add(Row(title: "Settings…", action: #selector(showSettings(_:)), key: ",", target: self), to: menu)
        add(Row(title: "Reset Panel Size", action: #selector(resetPanelSize(_:)), target: self), to: menu)
        menu.addItem(.separator())
        add(Row(title: "Quit Pith", action: #selector(NSApplication.terminate(_:)), key: "q"), to: menu)
        register(menu)
        return menu
    }

    /// The context menu of the editor, built anew for each click so that it shows the Shortcuts as they are.
    func makeContextMenu() -> NSMenu {
        let menu = menu(title: "Note")
        add(Row(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"), to: menu)
        add(Row(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"), to: menu)
        add(Row(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"), to: menu)
        menu.addItem(.separator())
        let rows: [Row] = [
            Row(title: "New Note", action: #selector(newNote(_:)), identifier: "newNote", target: self),
            Row(title: "Go to Latest Note", action: #selector(goToLatest(_:)), identifier: "goToLatest", target: self),
            Row(title: "Search Notes", action: #selector(searchNotes(_:)), identifier: "searchNotes", target: self),
        ]
        for row in rows { add(row, to: menu) }
        menu.addItem(.separator())
        add(Row(title: "Move to Trash", action: #selector(moveToTrash(_:)), identifier: "moveToTrash", target: self), to: menu)
        add(Row(title: "Show Trash", action: #selector(showTrash(_:)), identifier: "showTrash", target: self), to: menu)
        applyShortcuts(to: menu)
        return menu
    }

    /// The icon in the menu bar with the status menu on it, so that a left and a right click both open it.
    func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.image
        item.button?.setAccessibilityLabel("Pith")
        item.menu = makeStatusMenu()
        return item
    }

    // MARK: Shortcuts

    private func register(_ menu: NSMenu) {
        live.add(menu)
        applyShortcuts(to: menu)
    }

    /// The key equivalent of each item with the name of a Shortcut action is the Shortcut's, as the layout types it.
    private func applyShortcuts(to menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu { applyShortcuts(to: submenu) }
            guard let name = item.identifier?.rawValue, let action = ShortcutAction(rawValue: name) else { continue }
            if let key = shortcuts.menuKey(for: action) {
                item.keyEquivalent = key.key
                item.keyEquivalentModifierMask = key.modifiers
            } else {
                item.keyEquivalent = ""
            }
        }
    }

    @objc private func shortcutsDidChange(_ notification: Notification) {
        for menu in live.allObjects { applyShortcuts(to: menu) }
    }

    // MARK: Keys of the Panel

    /// ⇧⌘[ and ⇧⌘] (or whatever Previous and Next Note are now) by the key's place on the keyboard, whatever the layout.
    /// The menu would give the default ones to Outdent and Indent, which have ⌘[ and ⌘] and match with ⇧ held too.
    func pagingAction(for event: NSEvent) -> Selector? {
        let pressed = Shortcut(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
        if pressed == shortcuts.shortcut(for: .previousNote) { return #selector(previousNote(_:)) }
        if pressed == shortcuts.shortcut(for: .nextNote) { return #selector(nextNote(_:)) }
        return nil
    }

    /// A key the Panel handles before the main menu does; `true` when it did. ⌘= is ⌘+ without ⇧, and the menu item has
    /// the shifted one only.
    func performKeyEquivalent(_ event: NSEvent) -> Bool {
        if performSearchKey(event) { return true }
        if let action = pagingAction(for: event) {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            if validateMenuItem(item) { perform(action, with: self) }
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "=" {
            let item = NSMenuItem(title: "", action: #selector(increaseTextSize(_:)), keyEquivalent: "")
            if validateMenuItem(item) { increaseTextSize(self) }
            return true
        }
        return false
    }

    /// ⌘A and ⌘⌫ with Search on top belong to its list, ahead of the field, which would select its text and erase the query.
    /// ⌘⌫ is the menu's Move to Trash, and nothing at all with no row selected.
    private func performSearchKey(_ event: NSEvent) -> Bool {
        guard let screen = panel.screens.top as? SearchScreen,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        // By the key's place on the keyboard, as the paging keys are.
        let aKey: UInt16 = 0
        let deleteKey: UInt16 = 51
        switch event.keyCode {
        case aKey:
            screen.selectAllRows()
        case deleteKey:
            if screen.canMoveToTrash { trash.moveToTrash(nil) }
        default:
            return false
        }
        return true
    }

    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return true }
        switch action {
        case #selector(newNote(_:)), #selector(goToLatest(_:)), #selector(previousNote(_:)), #selector(nextNote(_:)):
            return panel.isKey && panel.screens.top === note && note.isAvailable
        case #selector(searchNotes(_:)):
            return panel.isKey && search.validateMenuItem(probe(#selector(SearchController.find(_:))))
        case #selector(findNext(_:)):
            return panel.isKey && search.validateMenuItem(probe(#selector(SearchController.findNext(_:))))
        case #selector(findPrevious(_:)):
            return panel.isKey && search.validateMenuItem(probe(#selector(SearchController.findPrevious(_:))))
        case #selector(moveToTrash(_:)):
            return panel.isKey && trash.validateMenuItem(probe(#selector(TrashController.moveToTrash(_:))))
        case #selector(showTrash(_:)):
            return panel.isKey && trash.validateMenuItem(probe(#selector(TrashController.showTrash(_:))))
        case #selector(increaseTextSize(_:)), #selector(decreaseTextSize(_:)), #selector(resetTextSize(_:)), #selector(generateBigNote(_:)):
            return panel.isKey
        case #selector(closeWindow(_:)):
            if panel.isKey { return true }
            guard let key = NSApp.keyWindow else { return false }
            return key.sheetParent == nil
        case #selector(showSettings(_:)):
            return openSettings != nil
        case #selector(menuBarNewNote(_:)), #selector(menuBarGoToLatest(_:)), #selector(menuBarShowTrash(_:)):
            return note.isAvailable
        default:
            return true
        }
    }

    /// An item of the other controller's own action, to ask that controller whether it is on.
    private func probe(_ action: Selector) -> NSMenuItem {
        NSMenuItem(title: "", action: action, keyEquivalent: "")
    }

    // MARK: Actions of the main menu and the context menu

    @objc func newNote(_ sender: Any?) { note.newNote() }
    @objc func goToLatest(_ sender: Any?) { note.goToLatest() }
    @objc func previousNote(_ sender: Any?) { note.previousNote() }
    @objc func nextNote(_ sender: Any?) { note.nextNote() }
    @objc func searchNotes(_ sender: Any?) { search.find(sender) }
    @objc func findNext(_ sender: Any?) { search.findNext(sender) }
    @objc func findPrevious(_ sender: Any?) { search.findPrevious(sender) }
    @objc func moveToTrash(_ sender: Any?) { trash.moveToTrash(sender) }
    @objc func showTrash(_ sender: Any?) { trash.showTrash(sender) }

    @objc func increaseTextSize(_ sender: Any?) { changeTextSize { $0.bigger() } }
    @objc func decreaseTextSize(_ sender: Any?) { changeTextSize { $0.smaller() } }
    @objc func resetTextSize(_ sender: Any?) { changeTextSize { $0.reset() } }

    /// Changes the size and shows the pill, also at the ends of the range where the size stays.
    private func changeTextSize(_ change: (TextSizeModel) -> Void) {
        change(textSize)
        note.showSizeHUD(size: textSize.size)
    }

    @objc func resetPanelSize(_ sender: Any?) { panel.resetPanelFrame(sender) }

    /// ⌘W: the Panel hides; any other window of Pith closes.
    @objc func closeWindow(_ sender: Any?) {
        if panel.isKey {
            panel.hide()
        } else {
            NSApp.keyWindow?.performClose(sender)
        }
    }

    @objc func showSettings(_ sender: Any?) { openSettings?() }

    /// The standard About window, with a link to the repository in its credits.
    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString(
            string: Self.repositoryURL.absoluteString,
            attributes: [.link: Self.repositoryURL, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// Replaces the Note with a generated one of 5000 lines, the same as the bench's, and forgets the undo history.
    @objc func generateBigNote(_ sender: Any?) {
        note.replaceText(NoteGenerator.note(lines: 5000, seed: 1))
    }

    // MARK: Actions of the menu in the menu bar

    /// Open Pith shows the Panel, even if it is already shown; it never hides it.
    @objc func openPith(_ sender: Any?) { panel.reveal() }

    @objc func menuBarNewNote(_ sender: Any?) { fromMenuBar { note.newNote() } }
    @objc func menuBarGoToLatest(_ sender: Any?) { fromMenuBar { note.goToLatest() } }

    /// Opens the Trash, unless it is on top already.
    @objc func menuBarShowTrash(_ sender: Any?) {
        panel.reveal()
        guard !panel.hasAlert, !(panel.screens.top is TrashScreen) else { return }
        trash.showTrash(sender)
    }

    /// Shows the Panel and, if no alert waits there to be answered first, closes Search and the Trash and runs `command` on the Note.
    private func fromMenuBar(_ command: () -> Void) {
        panel.reveal()
        guard !panel.hasAlert else { return }
        closeScreensAboveNote()
        command()
    }

    private func closeScreensAboveNote() {
        var remaining = panel.screens.screens.count
        while panel.screens.top !== note, remaining > 0 {
            remaining -= 1
            if !panel.screens.top.handleCancel() { break }
        }
    }

    // MARK: Number in the Trash

    /// The number of Notes in the Trash is counted again each time the menu opens; none, or a failed count, shows no number.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.identifier?.rawValue == "showTrash" }) else { return }
        let count = (try? note.store?.trashCount()) ?? 0
        item.badge = count > 0 ? NSMenuItemBadge(count: count) : nil
    }
}
