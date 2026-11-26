import AppKit
import PithEditor
import PithNotes

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var panelController: PanelController?
    private var noteScreen: NoteScreen?
    private var searchController: SearchController?
    private var trashController: TrashController?
    private let textSize = TextSizeModel(initial: AppDelegate.textSizeArgument())
    private let hotkeys = HotkeyCenter()
    private lazy var shortcuts = ShortcutStore(registrar: hotkeys)
    private var recorderWindow: RecorderTestWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearanceArgument()

        // A fixture lives in memory; the open Note of the real defaults is not its to change.
        let screen = NoteScreen(
            openStore: makeStoreOpener(), scheduler: TaskScheduler(), textSize: textSize,
            defaults: UserDefaults.standard.string(forKey: "PithFixture") == nil ? .standard : nil
        )
        self.noteScreen = screen
        // `-PithLatest newest|last-edited` sets what ⌘1 jumps to, without storing it.
        if let mode = UserDefaults.standard.string(forKey: "PithLatest").flatMap(Latest.init(rawValue:)) {
            screen.latestMeans = { mode }
        }

        let panel = PanelController(note: screen, fixedSize: windowSizeArgument())
        self.panelController = panel
        screen.alerts = panel
        let search = SearchController(stack: panel.screens, note: screen)
        search.isBlocked = { [weak panel] in panel?.panel.attachedSheet != nil }
        if let now = nowArgument() { search.now = { now } }
        self.searchController = search
        let trash = TrashController(stack: panel.screens, note: screen)
        trash.isBlocked = { [weak panel] in panel?.panel.attachedSheet != nil }
        trash.presentAlert = { [weak panel] alert, answer in panel?.enqueue(alert, handler: answer) }
        trash.presentFailure = { [weak panel] reason in panel?.presentSaveFailureAlert(reason: reason) }
        if let now = nowArgument() {
            trash.now = { now }
            screen.now = { now }
        }
        self.trashController = trash
        panel.onWillHide = { [weak screen] in screen?.flush() }
        panel.panel.onKeyEquivalent = { [weak self] event in self?.performPagingKey(event) ?? false }
        NSApp.mainMenu = makeMainMenu()

        // The alerts of the load wait in the Panel until it shows.
        screen.load()
        openStackArgument(in: screen)

        hotkeys.onPress = { [weak panel] in panel?.toggle() }
        // A Hotkey the system refuses is logged; the menu's Open Pith is the way in then.
        shortcuts.registerHotkey()

        // Every launch shows the Panel, as the Hotkey does; the recorder window takes its place for `-PithShow recorder`.
        if Surface.requested == .recorder {
            let state = UserDefaults.standard.string(forKey: "PithRecorderState").flatMap(Self.recorderState)
            recorderWindow = RecorderTestWindow(store: shortcuts, size: windowSizeArgument(), state: state)
            recorderWindow?.show()
        } else {
            panel.show()
        }

        // `-PithBigNote YES` starts on the generated Note, as Debug → Generate 5k Lines does.
        if UserDefaults.standard.bool(forKey: "PithBigNote") { generateBigNote(nil) }

        // `-PithSelection "<location> <length>"` starts with that selection in view, for screenshots of it.
        if UserDefaults.standard.string(forKey: "PithSelection") != nil { screen.scrollSelectionToVisible() }

        presentAlertArguments()

        showSurface(in: panel.panel, screen: screen)
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteScreen?.willTerminate()
    }

    /// `-PithNow <ISO 8601>` is "now" for the times of Search's rows, so that a screenshot shows "10:42" and "Yesterday".
    private func nowArgument() -> Date? {
        UserDefaults.standard.string(forKey: "PithNow").flatMap(Fixture.date(from:))
    }

    /// `-PithTextSize <n>` starts at that size instead of the stored one, and stores nothing.
    private static func textSizeArgument() -> Int? {
        let value = UserDefaults.standard.integer(forKey: "PithTextSize")
        return value == 0 ? nil : value
    }

    /// Where the notes are. With `-PithFixture <path>` it is an in-memory database holding one Note, that UTF-8 file's text
    /// with the selection of `-PithSelection "<location> <length>"`, or, for a `.json` file, the Notes in it (`Fixture`);
    /// nothing goes to disk. If the file cannot be read, the database is empty. Without the flag it is the real database in Application Support.
    private func makeStoreOpener() -> () throws -> (store: NoteStore, recovery: CorruptionRecovery?) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "PithFixture") else {
            return { try NoteStore.open(at: .file(NoteStore.defaultFileURL)) }
        }
        if path.hasSuffix(".json") {
            let entries: [Fixture.Entry]
            do {
                entries = try Fixture.parse(json: Data(contentsOf: URL(fileURLWithPath: path)))
            } catch {
                NSLog("Pith: cannot read fixture %@: %@", path, String(describing: error))
                return { try NoteStore.open(at: .memory) }
            }
            return { try Fixture.openStore(entries: entries) }
        }
        let text: String?
        do {
            text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        } catch {
            NSLog("Pith: cannot read fixture %@: %@", path, String(describing: error))
            text = nil
        }
        var selection = NoteSelection(location: 0, length: 0)
        if let numbers = defaults.string(forKey: "PithSelection")?.split(separator: " ").compactMap({ Int($0) }), numbers.count == 2 {
            selection = NoteSelection(location: numbers[0], length: numbers[1])
        }
        // `-PithStackSize N` fills the Stack with N short Notes, the fixture one of them, at the place `-PithStackIndex` says.
        let size = defaults.integer(forKey: "PithStackSize")
        let slot = Self.stackSlot(size: size)
        return {
            let opened = try NoteStore.open(at: .memory)
            guard size > 0 else {
                if let text { _ = try opened.store.insert(text: text, selection: selection, scrollOffset: 0) }
                return opened
            }
            for position in 1...size {
                if position == slot, let text {
                    _ = try opened.store.insert(text: text, selection: selection, scrollOffset: 0)
                } else {
                    _ = try opened.store.insert(text: "# Note \(position)\n\nA short Note to fill the Stack.", selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)
                }
            }
            return opened
        }
    }

    /// The place of the fixture in a Stack of `size`: `-PithStackIndex <i>` from 1, the last one for `blank` or none.
    private static func stackSlot(size: Int) -> Int {
        let index = UserDefaults.standard.string(forKey: "PithStackIndex").flatMap { Int($0) }
        return min(max(index ?? size, 1), max(size, 1))
    }

    /// `-PithStackIndex <i>` opens the i-th Note of the Stack (from 1), `blank` opens a Blank; both with the footer lit.
    private func openStackArgument(in screen: NoteScreen) {
        guard let value = UserDefaults.standard.string(forKey: "PithStackIndex") else { return }
        if value == "blank" {
            screen.newNote()
        } else if let index = Int(value), screen.stack.ids.indices.contains(index - 1) {
            screen.show(noteID: screen.stack.ids[index - 1])
        }
    }

    /// `-PithWindowSize "<width> <height>"` sizes the Panel's content instead of its stored size, without saving it:
    /// screenshots at a fixed size. The Panel has no title bar, so its content is its whole frame.
    private func windowSizeArgument() -> CGSize? {
        guard let size = UserDefaults.standard.string(forKey: "PithWindowSize")?.split(separator: " ").compactMap({ Double($0) }),
              size.count == 2 else { return nil }
        return CGSize(width: size[0], height: size[1])
    }

    /// `-PithCorruptAlert <path>` shows the alert about a damaged notes file set aside at `path`.
    /// `-PithOpenFailureAlert <reason>` shows the alert about notes that did not open, with Try Again;
    /// `-PithOpenFailureAlert newerSchema` shows its variant for notes from a newer Pith, with Quit only.
    /// `-PithSaveFailureAlert <reason>` shows the alert about notes that could not be saved.
    private func presentAlertArguments() {
        guard let panel = panelController else { return }
        if let path = UserDefaults.standard.string(forKey: "PithCorruptAlert") {
            panel.presentCorruptionRecoveryAlert(movedFile: URL(fileURLWithPath: path))
        }
        if let reason = UserDefaults.standard.string(forKey: "PithOpenFailureAlert") {
            let canRetry = reason != "newerSchema"
            panel.presentOpenFailureAlert(reason: reason, canRetry: canRetry) {
                NSLog("Pith: Try Again pressed")
            }
        }
        if let reason = UserDefaults.standard.string(forKey: "PithSaveFailureAlert") {
            panel.presentSaveFailureAlert(reason: reason)
        }
    }

    /// What `-PithShow` opens for `make shots`. `window` opens nothing; a surface that adds a popup window sets `opensPopup`.
    private enum Surface: String {
        case window
        case contextMenu = "context-menu"
        /// The size pill, held on screen.
        case textSize = "text-size"
        /// The sheet of the alert about notes that could not be saved.
        case saveFailure = "save-failure"
        /// The test window of the Shortcut recorder instead of the Panel.
        case recorder
        /// Search with an empty query, with the query "region" (two Notes), with the query "invoice" (none).
        case searchAll = "search-all"
        case searchResults = "search-results"
        case searchEmpty = "search-empty"
        /// The footer of the Stack lit, on a Note in the middle of the Stack, on a Blank, and on the Latest Note.
        case stack
        case stackNew = "stack-new"
        case jumpLatest = "jump-latest"
        /// The toast after ⌘⌫ on the open Note, held on screen.
        case deleteUndo = "delete-undo"
        /// The Trash, and over it the alert of Empty Trash and the alert of Delete permanently.
        case trash
        case trashConfirm = "trash-confirm"
        case trashDelete = "trash-delete"

        var opensPopup: Bool { self == .contextMenu }
        /// A sheet slides in, and Search or the Trash comes up after the window does; the window is captured only after they have.
        var opensSheet: Bool {
            switch self {
            case .saveFailure, .searchAll, .searchResults, .searchEmpty, .deleteUndo, .trash, .trashConfirm, .trashDelete: true
            default: false
            }
        }

        static var requested: Surface {
            UserDefaults.standard.string(forKey: "PithShow").flatMap(Surface.init(rawValue:)) ?? .window
        }
    }

    /// `-PithRecorderState idle|recording|error` for the recorder window; `error` shows "Used by Bold".
    private static func recorderState(_ name: String) -> ShortcutRecorderModel.State? {
        switch name {
        case "idle": .idle
        case "recording": .recording(error: nil)
        case "error": .recording(error: Rejection.usedBy("Bold").message)
        default: nil
        }
    }

    /// `-PithShow window|context-menu|text-size|save-failure|recorder|stack|stack-new|jump-latest|search-all|search-results|
    /// search-empty|delete-undo|trash|trash-confirm|trash-delete` opens that surface for `make shots`; `window` (the default) opens nothing. `-PithShots YES` reports the
    /// IDs of the app's visible windows on stdout once the surface is up.
    private func showSurface(in window: NSWindow, screen: NoteScreen) {
        let defaults = UserDefaults.standard
        let surface = Surface.requested
        let editor = screen.editor
        // The recorder window is the window to photograph there; the Panel stays hidden.
        let shotWindow = recorderWindow?.window ?? window
        shotWindow.display()
        if defaults.bool(forKey: "PithShots") {
            // `popUp` blocks in its tracking loop, so the report is a timer that also fires there.
            let attempts = Counter()
            let panelNumber = shotWindow.windowNumber
            let opensPopup = surface.opensPopup
            let opensSheet = surface.opensSheet
            let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
                attempts.value += 1
                let shots = Self.visibleShots(panel: panelNumber)
                // Wait until the surface is on screen; give up after 8 s and report what there is.
                let settled = !opensSheet || attempts.value >= 6
                guard attempts.value >= 32 || (settled && shots.contains { $0.role == "window" } && (!opensPopup || shots.contains { $0.role == "menu" })) else { return }
                timer.invalidate()
                for shot in shots { print("PithShot \(shot.role) \(shot.id)") }
                print("PithShot done")
                fflush(stdout)
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        // After the window is on screen: `popUp` started during launch can come up without anything on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            switch surface {
            case .contextMenu:
                // On the selection if there is one: a right click elsewhere moves it. Otherwise the middle of the visible text.
                var point = NSPoint(x: editor.visibleRect.midX, y: editor.visibleRect.midY)
                if editor.selectedRange().length > 0 {
                    let onScreen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
                    let inWindow = window.convertFromScreen(NSRect(x: onScreen.midX, y: onScreen.midY, width: 0, height: 0)).origin
                    point = editor.convert(inWindow, from: nil)
                }
                let event = NSEvent.mouseEvent(
                    with: .rightMouseDown, location: editor.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                )
                if let event, let menu = editor.menu(for: event) {
                    menu.popUp(positioning: nil, at: point, in: editor)
                }
            case .textSize:
                screen.showSizeHUD(size: self?.textSize.size ?? TextSizeModel.defaultSize, autoHide: false)
            case .saveFailure:
                self?.panelController?.presentSaveFailureAlert(reason: "SQLite error 13: database or disk is full.")
            case .searchAll: self?.showSearch(query: "")
            case .searchResults: self?.showSearch(query: "region")
            case .searchEmpty: self?.showSearch(query: "invoice")
            case .window, .recorder: break
            case .deleteUndo:
                screen.moveToTrash()
                // The mouse on the toast holds it, so the shot finds it there.
                screen.toastHoverChanged(true)
            case .trash: self?.showTrash()
            case .trashConfirm: self?.showTrash()?.emptyTrash()
            case .trashDelete: self?.showTrash()?.deleteSelectedPermanently()
            case .stack, .stackNew, .jumpLatest:
                screen.activateFooter(pinned: true)
            }
        }
    }

    @discardableResult
    private func showTrash() -> TrashScreen? {
        trashController?.showTrash(nil)
        return panelController?.topScreen as? TrashScreen
    }

    private func showSearch(query: String) {
        searchController?.find(nil)
        guard let search = panelController?.topScreen as? SearchScreen else { return }
        search.setQuery(query)
        // The caret after the text, as on the artboards, not the whole text selected.
        if let editor = search.field.currentEditor() { editor.selectedRange = NSRange(location: (query as NSString).length, length: 0) }
    }

    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    /// The visible windows of this process: the Panel is the window (its sheet shows in its capture), anything at the
    /// popup menu level or above is a menu (a menu sits on layer 101).
    private nonisolated static func visibleShots(panel: Int) -> [(role: String, id: Int)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? Int == pid,
                  let id = info[kCGWindowNumber as String] as? Int, let layer = info[kCGWindowLayer as String] as? Int else { return nil }
            if id == panel { return ("window", id) }
            return layer >= menuLayer ? ("menu", id) : nil
        }
    }

    /// `-PithAppearance light|dark` forces an appearance; without it the app follows the system.
    private func applyAppearanceArgument() {
        switch UserDefaults.standard.string(forKey: "PithAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = submenu(in: main, title: "Pith")
        appMenu.addItem(withTitle: "About Pith", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Pith", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = submenu(in: main, title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        // Ticket 10 may rearrange these.
        let findItem = edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findItem.submenu = findMenu
        let finds: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Find…", #selector(SearchController.find(_:)), "f", [.command]),
            ("Find Next", #selector(SearchController.findNext(_:)), "g", [.command]),
            ("Find Previous", #selector(SearchController.findPrevious(_:)), "g", [.command, .shift]),
        ]
        for (title, action, key, modifiers) in finds {
            let item = findMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = searchController
        }

        let format = submenu(in: main, title: "Format")
        let inline: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Bold", #selector(EditorTextView.toggleBold(_:)), "b", []),
            ("Italic", #selector(EditorTextView.toggleItalic(_:)), "i", []),
            ("Highlight", #selector(EditorTextView.toggleHighlight(_:)), "u", [.shift]),
            ("Strikethrough", #selector(EditorTextView.toggleStrikethrough(_:)), "u", [.option]),
            ("Code", #selector(EditorTextView.toggleCode(_:)), "j", [.shift]),
            ("Link", #selector(EditorTextView.toggleLink(_:)), "k", [.shift]),
        ]
        let blocks: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Heading 1", #selector(EditorTextView.toggleHeading1(_:)), "1", [.control]),
            ("Heading 2", #selector(EditorTextView.toggleHeading2(_:)), "2", [.control]),
            ("Heading 3", #selector(EditorTextView.toggleHeading3(_:)), "3", [.control]),
            ("Bulleted List", #selector(EditorTextView.toggleBulletList(_:)), "l", [.shift]),
            ("Numbered List", #selector(EditorTextView.toggleOrderedList(_:)), "l", [.option]),
            ("Task List", #selector(EditorTextView.toggleTaskList(_:)), "l", [.control]),
            ("Quote", #selector(EditorTextView.toggleQuote(_:)), "'", []),
            ("Code Block", #selector(EditorTextView.toggleCodeBlock(_:)), "j", [.option, .shift]),
        ]
        for group in [inline, blocks] {
            for (title, action, key, modifiers) in group {
                let item = format.addItem(withTitle: title, action: action, keyEquivalent: key)
                item.keyEquivalentModifierMask = modifiers.union(.command)
            }
            format.addItem(.separator())
        }
        format.addItem(withTitle: "Indent", action: #selector(NSResponder.indent(_:)), keyEquivalent: "]")
        format.addItem(withTitle: "Outdent", action: #selector(EditorTextView.outdent(_:)), keyEquivalent: "[")
        format.addItem(.separator())
        format.addItem(withTitle: "Complete Task", action: #selector(EditorTextView.toggleTask(_:)), keyEquivalent: "k")

        // ⌘= also works, see `PithPanel`.
        let view = submenu(in: main, title: "View")
        view.addItem(withTitle: "Bigger", action: #selector(increaseTextSize(_:)), keyEquivalent: "+").target = self
        view.addItem(withTitle: "Smaller", action: #selector(decreaseTextSize(_:)), keyEquivalent: "-").target = self
        view.addItem(withTitle: "Actual Size", action: #selector(resetTextSize(_:)), keyEquivalent: "0").target = self

        // The identifiers are the names of the shortcut actions, so that the settings can find these items.
        let note = submenu(in: main, title: "Note")
        let paging: [(String, Selector, String, NSEvent.ModifierFlags, String)] = [
            ("New Note", #selector(newNote(_:)), "n", [.command], "newNote"),
            ("Go to Latest Note", #selector(goToLatest(_:)), "1", [.command], "goToLatest"),
            ("Previous Note", #selector(previousNote(_:)), "[", [.command, .shift], "previousNote"),
            ("Next Note", #selector(nextNote(_:)), "]", [.command, .shift], "nextNote"),
        ]
        for (title, action, key, modifiers, identifier) in paging {
            let item = note.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
            item.target = self
        }
        note.addItem(.separator())
        // ⌘⌫ is the Panel's own key too: with the Trash on top the list takes it first, and the item is off.
        let trashItems: [(String, Selector, String, String)] = [
            ("Move to Trash", #selector(TrashController.moveToTrash(_:)), "\u{8}", "moveToTrash"),
            ("Show Trash", #selector(TrashController.showTrash(_:)), "", "showTrash"),
        ]
        for (title, action, key, identifier) in trashItems {
            let item = note.addItem(withTitle: title, action: action, keyEquivalent: key)
            if !key.isEmpty { item.keyEquivalentModifierMask = [.command] }
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
            item.target = trashController
        }

        let debug = submenu(in: main, title: "Debug")
        debug.addItem(withTitle: "Generate 5k Lines", action: #selector(generateBigNote(_:)), keyEquivalent: "")

        let windowMenu = submenu(in: main, title: "Window")
        // The Panel has no Minimize or Close; ticket 10 builds the full menu.
        let reset = windowMenu.addItem(withTitle: "Reset Panel Size", action: #selector(PanelController.resetPanelFrame(_:)), keyEquivalent: "")
        reset.target = panelController

        return main
    }

    // MARK: Stack

    @objc func newNote(_ sender: Any?) { noteScreen?.newNote() }
    @objc func goToLatest(_ sender: Any?) { noteScreen?.goToLatest() }
    @objc func previousNote(_ sender: Any?) { noteScreen?.previousNote() }
    @objc func nextNote(_ sender: Any?) { noteScreen?.nextNote() }

    /// ⇧⌘[ and ⇧⌘] by the key's place on the keyboard, whatever the layout. The menu would give them to Outdent and Indent,
    /// which have ⌘[ and ⌘] and match with ⇧ held too.
    static func pagingAction(for event: NSEvent) -> Selector? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] else { return nil }
        switch event.keyCode {
        case 33: return #selector(previousNote(_:))
        case 30: return #selector(nextNote(_:))
        default: return nil
        }
    }

    private func performPagingKey(_ event: NSEvent) -> Bool {
        guard let action = Self.pagingAction(for: event) else { return false }
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        guard validateMenuItem(item) else { return true }
        NSApp.sendAction(action, to: self, from: self)
        return true
    }

    /// The paging items work with the Note screen on top and its notes open.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let paging: Set<Selector> = [#selector(newNote(_:)), #selector(goToLatest(_:)), #selector(previousNote(_:)), #selector(nextNote(_:))]
        guard let action = menuItem.action, paging.contains(action) else { return true }
        guard let noteScreen else { return false }
        return panelController?.topScreen === noteScreen && noteScreen.isAvailable
    }

    // MARK: Text size

    @objc func increaseTextSize(_ sender: Any?) { changeTextSize { $0.bigger() } }
    @objc func decreaseTextSize(_ sender: Any?) { changeTextSize { $0.smaller() } }
    @objc func resetTextSize(_ sender: Any?) { changeTextSize { $0.reset() } }

    /// Changes the size and shows the pill, also at the ends of the range where the size stays.
    private func changeTextSize(_ change: (TextSizeModel) -> Void) {
        change(textSize)
        noteScreen?.showSizeHUD(size: textSize.size)
    }

    /// Replaces the Note with a generated one of 5000 lines, the same as the bench's, and forgets the undo history.
    @objc private func generateBigNote(_ sender: Any?) {
        noteScreen?.replaceText(NoteGenerator.note(lines: 5000, seed: 1))
    }

    private func submenu(in menu: NSMenu, title: String) -> NSMenu {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        item.submenu = sub
        return sub
    }
}
