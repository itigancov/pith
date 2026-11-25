import AppKit
import PithEditor
import PithNotes

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var noteScreen: NoteScreen?
    private let textSize = TextSizeModel(initial: AppDelegate.textSizeArgument())
    private let hotkeys = HotkeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearanceArgument()

        let screen = NoteScreen(openStore: makeStoreOpener(), scheduler: TaskScheduler(), textSize: textSize)
        self.noteScreen = screen

        let panel = PanelController(note: screen, fixedSize: windowSizeArgument())
        self.panelController = panel
        screen.alerts = panel
        panel.onWillHide = { [weak screen] in screen?.flush() }
        NSApp.mainMenu = makeMainMenu()

        // The alerts of the load wait in the Panel until it shows.
        screen.load()

        hotkeys.onPress = { [weak panel] in panel?.toggle() }
        hotkeys.register(.default)

        // Every launch shows the Panel, as the Hotkey does.
        panel.show()

        // `-PithBigNote YES` starts on the generated Note, as Debug → Generate 5k Lines does.
        if UserDefaults.standard.bool(forKey: "PithBigNote") { generateBigNote(nil) }

        // `-PithSelection "<location> <length>"` starts with that selection in view, for screenshots of it.
        if UserDefaults.standard.string(forKey: "PithSelection") != nil { screen.scrollSelectionToVisible() }

        presentAlertArguments()

        showSurface(in: panel.panel, screen: screen)
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteScreen?.flush()
    }

    /// `-PithTextSize <n>` starts at that size instead of the stored one, and stores nothing.
    private static func textSizeArgument() -> Int? {
        let value = UserDefaults.standard.integer(forKey: "PithTextSize")
        return value == 0 ? nil : value
    }

    /// Where the notes are. With `-PithFixture <path>` it is an in-memory database holding one Note, that UTF-8 file's text
    /// with the selection of `-PithSelection "<location> <length>"`; nothing goes to disk. If the file cannot be read, the
    /// database is empty. Without the flag it is the real database in Application Support.
    private func makeStoreOpener() -> () throws -> (store: NoteStore, recovery: CorruptionRecovery?) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "PithFixture") else {
            return { try NoteStore.open(at: .file(NoteStore.defaultFileURL)) }
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
        return {
            let opened = try NoteStore.open(at: .memory)
            if let text { _ = try opened.store.insert(text: text, selection: selection, scrollOffset: 0) }
            return opened
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

        var opensPopup: Bool { self == .contextMenu }
        /// A sheet slides in; the window is captured only after it has.
        var opensSheet: Bool { self == .saveFailure }
    }

    /// `-PithShow window|context-menu|text-size|save-failure` opens that surface for `make shots`; `window` (the default)
    /// opens nothing. `-PithShots YES` reports the IDs of the app's visible windows on stdout once the surface is up.
    private func showSurface(in window: NSWindow, screen: NoteScreen) {
        let defaults = UserDefaults.standard
        let surface = defaults.string(forKey: "PithShow").flatMap(Surface.init(rawValue:)) ?? .window
        let editor = screen.editor
        window.display()
        if defaults.bool(forKey: "PithShots") {
            // `popUp` blocks in its tracking loop, so the report is a timer that also fires there.
            let attempts = Counter()
            let panelNumber = window.windowNumber
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
            case .window: break
            }
        }
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

    private func makeMainMenu() -> NSMenu {
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

        let debug = submenu(in: main, title: "Debug")
        debug.addItem(withTitle: "Generate 5k Lines", action: #selector(generateBigNote(_:)), keyEquivalent: "")

        let windowMenu = submenu(in: main, title: "Window")
        // The Panel has no Minimize or Close; ticket 10 builds the full menu.
        let reset = windowMenu.addItem(withTitle: "Reset Panel Size", action: #selector(PanelController.resetPanelFrame(_:)), keyEquivalent: "")
        reset.target = panelController

        return main
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
