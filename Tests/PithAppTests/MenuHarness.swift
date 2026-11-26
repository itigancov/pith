import AppKit
import Foundation
import PithNotes
import Testing
@testable import PithApp

/// A Panel that is only flags and counters, for the menus to talk to.
final class FakePanel: PanelHosting {
    let screens: ScreenStack
    var isShown = false
    var isKey = true
    var hasAlert = false
    var reveals = 0
    var hides = 0
    var resets = 0

    init(root: PanelScreen) { screens = ScreenStack(root: root) }

    func reveal() {
        reveals += 1
        isShown = true
    }

    func hide() {
        hides += 1
        isShown = false
        screens.hide()
    }

    func resetPanelFrame(_ sender: Any?) { resets += 1 }
}

/// The menus of the app on real screens, a `.memory` store, a fake Panel and a fake registrar.
@MainActor
final class MenuHarness {
    let suite = "PithMenuTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let store: NoteStore
    let note: NoteScreen
    let panel: FakePanel
    let search: SearchController
    let trash: TrashController
    let registrar = FakeRegistrar()
    let shortcuts: ShortcutStore
    let menus: AppMenus
    let window: NSWindow
    var settingsOpened = 0

    init(layout: KeyLayout = StubLayout(), notes: [String] = [], openSettings: Bool = false, load: Bool = true) throws {
        defaults = UserDefaults(suiteName: suite)!
        store = try NoteStore.open(at: .memory).store
        for text in notes { _ = try store.insert(text: text, selection: NoteSelection(location: 0, length: 0), scrollOffset: 0) }
        let store = store
        note = NoteScreen(
            openStore: { (store, nil) }, scheduler: ManualScheduler(),
            textSize: TextSizeModel(defaults: UserDefaults(suiteName: suite)!), defaults: nil
        )
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = note.view
        if load { note.load() }
        panel = FakePanel(root: note)
        search = SearchController(stack: panel.screens, note: note)
        trash = TrashController(stack: panel.screens, note: note)
        shortcuts = ShortcutStore(defaults: defaults, menuKeys: { [] }, systemShortcuts: { [] }, layout: layout, registrar: registrar)
        menus = AppMenus(
            shortcuts: shortcuts, panel: panel, note: note, search: search, trash: trash,
            textSize: TextSizeModel(defaults: UserDefaults(suiteName: suite)!)
        )
        if openSettings { menus.openSettings = { [unowned self] in settingsOpened += 1 } }
    }

    isolated deinit { defaults.removePersistentDomain(forName: suite) }

    // MARK: Looking

    func submenu(_ main: NSMenu, _ title: String) -> NSMenu? { main.items.first { $0.title == title }?.submenu }

    func item(_ title: String, in menu: NSMenu?) -> NSMenuItem? {
        menu?.items.first { $0.title == title }
    }

    /// What the menu shows: titles, with "|" for a separator.
    func layout(of menu: NSMenu?) -> [String] {
        (menu?.items ?? []).map { $0.isSeparatorItem ? "|" : $0.title }
    }

    /// Whether the menu would enable `item`: its target's validation, or its own flag without a validating target.
    func isEnabled(_ item: NSMenuItem?) -> Bool {
        guard let item else { return false }
        guard let target = item.target as? NSMenuItemValidation else { return item.isEnabled }
        return target.validateMenuItem(item)
    }

    /// Sends the item's action to its target.
    func choose(_ item: NSMenuItem?) {
        guard let item, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    func keyEvent(_ characters: String, code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
    }
}
