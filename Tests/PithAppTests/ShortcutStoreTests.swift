import AppKit
import Carbon.HIToolbox
import Testing
@testable import PithApp

/// A QWERTY stand-in for the live layout.
struct StubLayout: KeyLayout {
    var characters: [UInt32: String] = [
        0: "a", 11: "b", 6: "z", 45: "n", 18: "1", 3: "f", 33: "[", 30: "]", 40: "k", 41: ";",
    ]
    func character(forKeyCode keyCode: UInt32) -> String? { characters[keyCode] }
}

/// Records what the store asks of the system; `refused` shortcuts fail to register.
final class FakeRegistrar: HotkeyRegistering {
    enum Call: Equatable { case register(Shortcut), unregister }
    var calls: [Call] = []
    var refused: Set<Shortcut> = []
    var registered: Shortcut?

    func register(_ shortcut: Shortcut) -> Bool {
        calls.append(.register(shortcut))
        registered = nil
        guard !refused.contains(shortcut) else { return false }
        registered = shortcut
        return true
    }

    func unregister() {
        calls.append(.unregister)
        registered = nil
    }
}

private func key(_ code: Int, _ modifiers: NSEvent.ModifierFlags) -> Shortcut {
    Shortcut(keyCode: UInt32(code), modifiers: modifiers)
}

private final class Fixture {
    let suite = "PithShortcutTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let registrar = FakeRegistrar()
    let store: ShortcutStore

    init(menu: [MenuKey] = [], system: [Shortcut] = [], layout: KeyLayout = StubLayout()) {
        defaults = UserDefaults(suiteName: suite)!
        store = ShortcutStore(defaults: defaults, menuKeys: { menu }, systemShortcuts: { system }, layout: layout, registrar: registrar)
    }

    isolated deinit { defaults.removePersistentDomain(forName: suite) }

    /// A new store on the same defaults, as after a relaunch.
    func relaunched() -> ShortcutStore {
        ShortcutStore(defaults: defaults, menuKeys: { [] }, systemShortcuts: { [] }, layout: StubLayout(), registrar: FakeRegistrar())
    }
}

struct ShortcutStoreValueTests {
    @Test func theSevenDefaultsAreTheDocumentedOnesAndDoNotClash() {
        let fixture = Fixture()
        let expected: [ShortcutAction: Shortcut] = [
            .hotkey: key(kVK_Space, .option),
            .newNote: key(kVK_ANSI_N, .command),
            .goToLatest: key(kVK_ANSI_1, .command),
            .searchNotes: key(kVK_ANSI_F, .command),
            .previousNote: key(kVK_ANSI_LeftBracket, [.command, .shift]),
            .nextNote: key(kVK_ANSI_RightBracket, [.command, .shift]),
            .moveToTrash: key(kVK_Delete, .command),
        ]
        for action in ShortcutAction.allCases {
            #expect(fixture.store.shortcut(for: action) == expected[action])
            #expect(fixture.store.rejection(of: action.defaultShortcut, for: action) == nil)
        }
        #expect(Set(expected.values).count == 7)
    }

    @Test func anAssignedValueSurvivesARelaunch() {
        let fixture = Fixture()
        #expect(fixture.store.assign(key(kVK_ANSI_K, [.command, .control]), to: .newNote) == nil)
        #expect(fixture.relaunched().shortcut(for: .newNote) == key(kVK_ANSI_K, [.command, .control]))
        #expect(fixture.relaunched().shortcut(for: .searchNotes) == ShortcutAction.searchNotes.defaultShortcut)
    }

    @Test func damagedJSONGivesEveryRowItsDefault() {
        let fixture = Fixture()
        fixture.defaults.set(Data("not json".utf8), forKey: ShortcutStore.defaultsKey)
        for action in ShortcutAction.allCases {
            #expect(fixture.relaunched().shortcut(for: action) == action.defaultShortcut)
        }
    }

    @Test func aStoredValueThatBreaksTheRulesGivesThatRowItsDefault() {
        let fixture = Fixture()
        // A plain "A" for the Hotkey, ⌥A for a Panel row; a valid ⌃⌘K for another row stays.
        let json = """
        {"hotkey": {"keyCode": 0, "modifiers": 0},
         "newNote": {"keyCode": 0, "modifiers": \(NSEvent.ModifierFlags.option.rawValue)},
         "searchNotes": {"keyCode": 40, "modifiers": \(NSEvent.ModifierFlags([.command, .control]).rawValue)},
         "unknownRow": {"keyCode": 1, "modifiers": 0},
         "nextNote": {"keyCode": "bad"}}
        """
        fixture.defaults.set(Data(json.utf8), forKey: ShortcutStore.defaultsKey)
        let store = fixture.relaunched()
        #expect(store.shortcut(for: .hotkey) == ShortcutAction.hotkey.defaultShortcut)
        #expect(store.shortcut(for: .newNote) == ShortcutAction.newNote.defaultShortcut)
        #expect(store.shortcut(for: .nextNote) == ShortcutAction.nextNote.defaultShortcut)
        #expect(store.shortcut(for: .searchNotes) == key(kVK_ANSI_K, [.command, .control]))
    }

    @Test func restoreDefaultsErasesTheOverridesAndReregistersTheDefaultHotkey() {
        let fixture = Fixture()
        _ = fixture.store.assign(key(kVK_Space, [.control, .option]), to: .hotkey)
        _ = fixture.store.assign(key(kVK_ANSI_K, [.command, .control]), to: .newNote)
        fixture.store.restoreDefaults()
        for action in ShortcutAction.allCases {
            #expect(fixture.store.shortcut(for: action) == action.defaultShortcut)
        }
        #expect(fixture.defaults.data(forKey: ShortcutStore.defaultsKey) == nil)
        #expect(fixture.registrar.registered == key(kVK_Space, .option))
    }

    @Test func assigningTheDefaultStoresNothing() {
        let fixture = Fixture()
        _ = fixture.store.assign(key(kVK_ANSI_K, [.command, .control]), to: .newNote)
        _ = fixture.store.assign(ShortcutAction.newNote.defaultShortcut, to: .newNote)
        #expect(fixture.defaults.data(forKey: ShortcutStore.defaultsKey) == nil)
    }

    @Test func aChangeIsAnnouncedOnce() {
        let fixture = Fixture()
        var count = 0
        let observer = NotificationCenter.default.addObserver(forName: .shortcutsDidChange, object: fixture.store, queue: nil) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        _ = fixture.store.assign(key(kVK_ANSI_K, [.command, .control]), to: .newNote)
        _ = fixture.store.assign(key(kVK_ANSI_K, [.command, .control]), to: .newNote)
        #expect(count == 1)
    }
}

struct ShortcutStoreRuleTests {
    @Test func hotkeyNeedsOneOfCommandOptionControl() {
        let fixture = Fixture()
        #expect(fixture.store.assign(key(kVK_ANSI_A, .shift), to: .hotkey) == .needsModifier)
        #expect(fixture.store.assign(key(kVK_ANSI_A, []), to: .hotkey) == .needsModifier)
        #expect(fixture.store.assign(key(kVK_ANSI_A, .option), to: .hotkey) == nil)
        #expect(fixture.store.assign(key(kVK_Space, [.option, .shift]), to: .hotkey) == nil)
    }

    @Test func panelRowsNeedCommandOrControl() {
        let fixture = Fixture()
        #expect(fixture.store.assign(key(kVK_ANSI_A, .option), to: .newNote) == .needsCommandOrControl)
        #expect(fixture.store.assign(key(kVK_ANSI_A, [.option, .shift]), to: .newNote) == .needsCommandOrControl)
        #expect(fixture.store.assign(key(kVK_ANSI_A, .shift), to: .newNote) == .needsModifier)
        #expect(fixture.store.assign(key(kVK_ANSI_A, .control), to: .newNote) == nil)
    }

    @Test func aRowCannotTakeAnotherRowsShortcutIncludingTheHotkey() {
        let fixture = Fixture()
        #expect(fixture.store.assign(ShortcutAction.searchNotes.defaultShortcut, to: .newNote) == .usedBy("Search notes"))
        // ⌥Space alone fails the Panel rule first, so the Hotkey takes a ⌃ shortcut for this.
        #expect(fixture.store.assign(key(kVK_Space, .control), to: .hotkey) == nil)
        #expect(fixture.store.assign(key(kVK_Space, .control), to: .newNote) == .usedBy("Open and hide Pith"))
        #expect(fixture.store.assign(ShortcutAction.newNote.defaultShortcut, to: .hotkey) == .usedBy("New note"))
        #expect(fixture.store.shortcut(for: .newNote) == ShortcutAction.newNote.defaultShortcut)
    }

    @Test func assigningTheSameValueToTheSameRowIsNotAnErrorAndChangesNothing() {
        let fixture = Fixture()
        #expect(fixture.store.assign(ShortcutAction.newNote.defaultShortcut, to: .newNote) == nil)
        #expect(fixture.store.assign(ShortcutAction.hotkey.defaultShortcut, to: .hotkey) == nil)
        #expect(fixture.registrar.calls.isEmpty)
    }

    @Test func aMenuItemsKeyIsUsedByItsTitle() {
        let fixture = Fixture(menu: [MenuKey(title: "Bold", key: "b", modifiers: .command)])
        #expect(fixture.store.assign(key(kVK_ANSI_B, .command), to: .newNote) == .usedBy("Bold"))
        #expect(fixture.store.assign(key(kVK_ANSI_B, [.command, .control]), to: .newNote) == nil)
    }

    @Test func aCapitalLetterInTheMenuMeansShift() {
        let item = NSMenuItem(title: "Redo", action: nil, keyEquivalent: "Z")
        item.keyEquivalentModifierMask = .command
        let menu = NSMenu()
        menu.addItem(item)
        let keys = MenuKey.items(in: menu)
        #expect(keys == [MenuKey(title: "Redo", key: "z", modifiers: [.command, .shift])])
        let fixture = Fixture(menu: keys)
        #expect(fixture.store.assign(key(kVK_ANSI_Z, [.command, .shift]), to: .newNote) == .usedBy("Redo"))
    }

    @Test func menuItemsOfTheRowsAreLeftOutOfTheCheck() {
        let menu = NSMenu()
        let sub = NSMenu(title: "File")
        let new = sub.addItem(withTitle: "New Note", action: nil, keyEquivalent: "n")
        new.identifier = NSUserInterfaceItemIdentifier(ShortcutAction.newNote.rawValue)
        sub.addItem(withTitle: "Quit Pith", action: nil, keyEquivalent: "q")
        menu.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = sub
        #expect(MenuKey.items(in: menu).map(\.title) == ["Quit Pith"])
    }

    @Test func theMenuIsCheckedThroughTheLayout() {
        // On this layout the physical key 11 types "q": the menu's ⌘Q sits on it.
        var layout = StubLayout()
        layout.characters[11] = "q"
        let fixture = Fixture(menu: [MenuKey(title: "Quit Pith", key: "q", modifiers: .command)], layout: layout)
        #expect(fixture.store.assign(key(11, .command), to: .newNote) == .usedBy("Quit Pith"))
        let qwerty = Fixture(menu: [MenuKey(title: "Quit Pith", key: "q", modifiers: .command)])
        #expect(qwerty.store.assign(key(11, .command), to: .newNote) == nil)
    }

    @Test func textEditingKeysAreRefusedButCommandDeleteIsNot() {
        let fixture = Fixture()
        #expect(fixture.store.assign(key(kVK_LeftArrow, .option), to: .hotkey) == .textEditing)
        #expect(fixture.store.assign(key(kVK_RightArrow, .command), to: .hotkey) == .textEditing)
        #expect(fixture.store.assign(key(kVK_Delete, .option), to: .hotkey) == .textEditing)
        #expect(fixture.store.assign(key(kVK_ForwardDelete, .option), to: .hotkey) == .textEditing)
        // ⌘⌫ is the default of Move to Trash and free for other rows.
        #expect(fixture.store.rejection(of: key(kVK_Delete, .command), for: .moveToTrash) == nil)
        #expect(fixture.store.assign(key(kVK_Delete, .command), to: .hotkey) == .usedBy("Move to Trash"))
        #expect(fixture.store.assign(key(kVK_ANSI_A, .control), to: .newNote) == nil)
    }

    @Test func systemShortcutsAreRefused() {
        let fixture = Fixture(system: [key(kVK_LeftArrow, .control)])
        #expect(fixture.store.assign(key(kVK_LeftArrow, .control), to: .newNote) == .system)
        #expect(fixture.store.assign(key(kVK_RightArrow, .control), to: .newNote) == nil)
    }

    @Test func theFirstRuleInOrderWins() {
        // ⌥A on a Panel row is also in the menu; the missing ⌘ or ⌃ comes first.
        let fixture = Fixture(menu: [MenuKey(title: "Strike", key: "a", modifiers: .option)], system: [key(kVK_ANSI_A, .option)])
        #expect(fixture.store.assign(key(kVK_ANSI_A, .option), to: .newNote) == .needsCommandOrControl)
        // The Hotkey has no such rule: the menu is next, before the system.
        #expect(fixture.store.assign(key(kVK_ANSI_A, .option), to: .hotkey) == .usedBy("Strike"))
        // Another row beats the menu.
        let both = Fixture(menu: [MenuKey(title: "New", key: "n", modifiers: .command)])
        #expect(both.store.assign(key(kVK_ANSI_N, .command), to: .searchNotes) == .usedBy("New note"))
    }

    @Test func rejectionsCarryTheTextsOfTheSpec() {
        #expect(Rejection.needsModifier.message == "Use ⌘, ⌥ or ⌃ in the shortcut")
        #expect(Rejection.needsCommandOrControl.message == "Add ⌘ or ⌃: ⌥ alone types characters")
        #expect(Rejection.usedBy("Bold").message == "Used by Bold")
        #expect(Rejection.textEditing.message == "Used by text editing")
        #expect(Rejection.system.message == "Used by macOS")
        #expect(Rejection.carbon.message == "Can't use this shortcut, another app may own it")
    }

    @Test func symbolicHotKeysAreReadAsShortcuts() {
        let entries: [[String: Any]] = [
            [kHISymbolicHotKeyEnabled as String: true, kHISymbolicHotKeyCode as String: 123, kHISymbolicHotKeyModifiers as String: controlKey],
            [kHISymbolicHotKeyEnabled as String: false, kHISymbolicHotKeyCode as String: 124, kHISymbolicHotKeyModifiers as String: controlKey],
            [kHISymbolicHotKeyEnabled as String: true, kHISymbolicHotKeyCode as String: 0xFFFF, kHISymbolicHotKeyModifiers as String: 0],
        ]
        #expect(SystemShortcuts.shortcuts(in: entries) == [key(kVK_LeftArrow, .control)])
    }
}

struct ShortcutStoreHotkeyTests {
    @Test func aNewHotkeyReplacesTheOldOneAndIsSaved() {
        let fixture = Fixture()
        let new = key(kVK_Space, [.control, .option])
        #expect(fixture.store.assign(new, to: .hotkey) == nil)
        #expect(fixture.registrar.registered == new)
        #expect(fixture.store.shortcut(for: .hotkey) == new)
        #expect(fixture.relaunched().shortcut(for: .hotkey) == new)
    }

    @Test func aRefusedHotkeyKeepsTheOldOneRegisteredAndSaved() {
        let fixture = Fixture()
        let taken = key(kVK_Space, [.command, .option])
        fixture.registrar.refused = [taken]
        #expect(fixture.store.assign(taken, to: .hotkey) == .carbon)
        #expect(fixture.registrar.calls == [.register(taken), .register(ShortcutAction.hotkey.defaultShortcut)])
        #expect(fixture.registrar.registered == ShortcutAction.hotkey.defaultShortcut)
        #expect(fixture.store.shortcut(for: .hotkey) == ShortcutAction.hotkey.defaultShortcut)
        #expect(fixture.defaults.data(forKey: ShortcutStore.defaultsKey) == nil)
    }

    @Test func recordingPausesTheHotkeyAndTheEndResumesTheCurrentOne() {
        let fixture = Fixture()
        fixture.store.setRecording(true)
        #expect(fixture.registrar.calls == [.unregister])
        fixture.store.setRecording(false)
        #expect(fixture.registrar.registered == ShortcutAction.hotkey.defaultShortcut)
    }

    @Test func assigningWhilePausedWorksAndAFailureStaysPaused() {
        let fixture = Fixture()
        fixture.store.setRecording(true)
        let taken = key(kVK_Space, [.command, .option])
        fixture.registrar.refused = [taken]
        #expect(fixture.store.assign(taken, to: .hotkey) == .carbon)
        #expect(fixture.registrar.registered == nil)
        let new = key(kVK_Space, [.control, .option])
        #expect(fixture.store.assign(new, to: .hotkey) == nil)
        fixture.store.setRecording(false)
        #expect(fixture.registrar.registered == new)
    }

    @Test func startupRegistersTheStoredHotkeyAndReportsARefusal() {
        let fixture = Fixture()
        #expect(fixture.store.registerHotkey())
        #expect(fixture.registrar.registered == ShortcutAction.hotkey.defaultShortcut)
        fixture.registrar.refused = [ShortcutAction.hotkey.defaultShortcut]
        #expect(!fixture.store.registerHotkey())
    }
}

struct ShortcutLabelTests {
    @Test func chipsPutModifiersInTheStandardOrderBeforeTheKey() {
        let layout = StubLayout()
        #expect(ShortcutAction.previousNote.defaultShortcut.chips(layout: layout) == ["⇧", "⌘", "["])
        #expect(ShortcutAction.hotkey.defaultShortcut.chips(layout: layout) == ["⌥", "Space"])
        #expect(key(kVK_ANSI_N, [.command, .shift, .option, .control]).chips(layout: layout) == ["⌃", "⌥", "⇧", "⌘", "N"])
        #expect(ShortcutAction.moveToTrash.defaultShortcut.chips(layout: layout) == ["⌘", "⌫"])
    }

    @Test func functionAndNavigationKeysHaveGlyphs() {
        let layout = StubLayout()
        #expect(key(kVK_F20, .command).chips(layout: layout) == ["⌘", "F20"])
        #expect(key(kVK_PageUp, .command).chips(layout: layout) == ["⌘", "⇞"])
        #expect(key(kVK_LeftArrow, .control).chips(layout: layout) == ["⌃", "←"])
    }

    @Test func voiceOverNamesSpellOutKeys() {
        let layout = StubLayout()
        #expect(ShortcutAction.previousNote.defaultShortcut.spokenName(layout: layout) == "Shift Command left bracket")
        #expect(ShortcutAction.hotkey.defaultShortcut.spokenName(layout: layout) == "Option Space")
        #expect(ShortcutAction.moveToTrash.defaultShortcut.spokenName(layout: layout) == "Command Delete")
        #expect(key(kVK_ANSI_N, [.control, .command]).spokenName(layout: layout) == "Control Command N")
    }

    @Test func theLiveLayoutNamesKeysAsAnASCIILayoutDoes() {
        #expect(ShortcutAction.newNote.defaultShortcut.chips(layout: LiveKeyLayout()) == ["⌘", "N"])
    }

    @Test func aShortcutRoundTripsThroughJSON() throws {
        let original = key(kVK_ANSI_K, [.command, .shift])
        let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func modifiersOtherThanTheFourAreDropped() {
        #expect(Shortcut(keyCode: 0, modifiers: [.option, .capsLock, .function, .numericPad]).modifiers == .option)
    }
}
