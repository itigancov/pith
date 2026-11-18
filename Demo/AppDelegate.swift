import AppKit
import PithEditor

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        applyAppearanceArgument()

        let editor = EditorTextView()
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.allowsUndo = true
        if let url = Bundle.main.url(forResource: "Fixture", withExtension: "md"),
           let fixture = try? String(contentsOf: url, encoding: .utf8) {
            editor.string = fixture
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = editor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pith"
        window.contentView = scrollView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        if let path = UserDefaults.standard.string(forKey: "PithSnapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.snapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    /// `-PithSnapshot <path>` writes a PNG of the window's content and quits: screenshots without screen recording rights.
    private func snapshot(to url: URL) {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// `-PithAppearance light|dark` forces an appearance; without it the app follows the system.
    private func applyAppearanceArgument() {
        switch UserDefaults.standard.string(forKey: "PithAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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

        let windowMenu = submenu(in: main, title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        return main
    }

    private func submenu(in menu: NSMenu, title: String) -> NSMenu {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        item.submenu = sub
        return sub
    }
}
