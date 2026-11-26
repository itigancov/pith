import AppKit
import Testing
@testable import PithApp

@MainActor
struct MainMenuTests {
    @Test func theMainMenuHasPithEditFormatNoteViewAndWindowInThatOrder() throws {
        let harness = try MenuHarness()
        let titles = harness.menus.makeMainMenu().items.map(\.title)
        #expect(titles.filter { $0 != "Debug" } == ["Pith", "Edit", "Format", "Note", "View", "Window"])
    }

    @Test func eachMenuHasTheItemsOfTheSpecInOrder() throws {
        let harness = try MenuHarness()
        let main = harness.menus.makeMainMenu()
        #expect(harness.layout(of: harness.submenu(main, "Pith")) == ["About Pith", "|", "Settings…", "|", "Quit Pith"])
        #expect(harness.layout(of: harness.submenu(main, "Edit")) ==
            ["Undo", "Redo", "|", "Cut", "Copy", "Paste", "Select All", "|", "Find Next", "Find Previous"])
        #expect(harness.layout(of: harness.submenu(main, "Note")) ==
            ["New Note", "Go to Latest Note", "Previous Note", "Next Note", "Search Notes", "|", "Move to Trash", "Show Trash"])
        #expect(harness.layout(of: harness.submenu(main, "View")) == ["Bigger", "Smaller", "Actual Size"])
        #expect(harness.layout(of: harness.submenu(main, "Window")) == ["Reset Panel Size", "Close"])
        #expect(harness.layout(of: harness.submenu(main, "Format")) == [
            "Bold", "Italic", "Highlight", "Strikethrough", "Code", "Link", "|",
            "Heading 1", "Heading 2", "Heading 3", "Bulleted List", "Numbered List", "Task List", "Quote", "Code Block", "|",
            "Indent", "Outdent", "|", "Complete Task",
        ])
    }

    @Test func thereIsNoFindSubmenuAndNoItemHasASubmenuBesidesTheTopOnes() throws {
        let harness = try MenuHarness()
        let main = harness.menus.makeMainMenu()
        for menu in main.items.compactMap(\.submenu) {
            #expect(menu.items.allSatisfy { $0.submenu == nil })
        }
    }

    @Test func theKeysAreTheOnesOfTheSpec() throws {
        let harness = try MenuHarness()
        let main = harness.menus.makeMainMenu()
        func key(_ title: String, _ menu: String) -> String {
            guard let item = harness.item(title, in: harness.submenu(main, menu)) else { return "missing" }
            var modifiers = ""
            for (flag, glyph) in [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            where item.keyEquivalentModifierMask.contains(flag) { modifiers += glyph }
            return item.keyEquivalent.isEmpty ? "" : modifiers + item.keyEquivalent
        }
        #expect(key("Settings…", "Pith") == "⌘,")
        #expect(key("Quit Pith", "Pith") == "⌘q")
        #expect(key("Find Next", "Edit") == "⌘g")
        #expect(key("Find Previous", "Edit") == "⇧⌘g")
        #expect(key("New Note", "Note") == "⌘n")
        #expect(key("Go to Latest Note", "Note") == "⌘1")
        #expect(key("Previous Note", "Note") == "⇧⌘[")
        #expect(key("Next Note", "Note") == "⇧⌘]")
        #expect(key("Search Notes", "Note") == "⌘f")
        #expect(key("Move to Trash", "Note") == "⌘\u{8}")
        #expect(key("Show Trash", "Note") == "")
        #expect(key("Smaller", "View") == "⌘-")
        #expect(key("Actual Size", "View") == "⌘0")
        #expect(key("Close", "Window") == "⌘w")
        #expect(key("Reset Panel Size", "Window") == "")
        #expect(key("Indent", "Format") == "⌘]")
        #expect(key("Outdent", "Format") == "⌘[")
    }

    @Test func theSevenShortcutItemsCarryTheNamesOfTheirActionsAndShowTrashHasItsOwn() throws {
        let harness = try MenuHarness()
        let main = harness.menus.makeMainMenu()
        let note = harness.submenu(main, "Note")
        #expect(note?.items.map { $0.identifier?.rawValue } ==
            ["newNote", "goToLatest", "previousNote", "nextNote", "searchNotes", nil, "moveToTrash", "showTrash"])
    }

    @Test func noItemTranslatesItsKeyEquivalentToTheLayout() throws {
        let harness = try MenuHarness()
        func allItems(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) } }
        let menus = [harness.menus.makeMainMenu(), harness.menus.makeStatusMenu(), harness.menus.makeContextMenu()]
        for menu in menus {
            for item in allItems(menu) where !item.isSeparatorItem {
                #expect(!item.allowsAutomaticKeyEquivalentLocalization, "\(item.title)")
            }
        }
    }

    @Test func theShortcutsMenuKeysAreOutOfTheKeyListForTheRecorder() throws {
        let harness = try MenuHarness()
        let keys = MenuKey.items(in: harness.menus.makeMainMenu())
        let titles = keys.map(\.title)
        #expect(!titles.contains("New Note"))
        #expect(!titles.contains("Previous Note"))
        #expect(!titles.contains("Move to Trash"))
        #expect(!titles.contains("Search Notes"))
        #expect(keys.contains { $0.title == "Settings…" && $0.key == "," && $0.modifiers == .command })
        #expect(keys.contains { $0.title == "Close" && $0.key == "w" && $0.modifiers == .command })
    }

    // MARK: Validation

    @Test func theNoteItemsAreOnWithTheNoteOnTopAndOffWithNotesUnavailable() throws {
        let on = try MenuHarness()
        let note = on.submenu(on.menus.makeMainMenu(), "Note")
        for title in ["New Note", "Go to Latest Note", "Previous Note", "Next Note", "Search Notes", "Move to Trash", "Show Trash"] {
            #expect(on.isEnabled(on.item(title, in: note)), "\(title)")
        }
        let off = try MenuHarness(load: false)
        let offNote = off.submenu(off.menus.makeMainMenu(), "Note")
        for title in ["New Note", "Go to Latest Note", "Previous Note", "Next Note", "Search Notes", "Move to Trash", "Show Trash"] {
            #expect(!off.isEnabled(off.item(title, in: offNote)), "\(title)")
        }
    }

    @Test func thePanelItemsAreOffWhenThePanelIsNotKey() throws {
        let harness = try MenuHarness()
        harness.panel.isKey = false
        let main = harness.menus.makeMainMenu()
        let panelItems: [(String, String)] = [
            ("New Note", "Note"), ("Move to Trash", "Note"), ("Show Trash", "Note"), ("Search Notes", "Note"),
            ("Bigger", "View"), ("Smaller", "View"), ("Actual Size", "View"), ("Find Next", "Edit"), ("Find Previous", "Edit"),
        ]
        for (title, menu) in panelItems {
            #expect(!harness.isEnabled(harness.item(title, in: harness.submenu(main, menu))), "\(title)")
        }
        // Reset Panel Size and Quit work from anywhere.
        #expect(harness.isEnabled(harness.item("Reset Panel Size", in: harness.submenu(main, "Window"))))
    }

    @Test func theNoteItemsFollowTheScreenOnTop() throws {
        let harness = try MenuHarness(notes: ["one"])
        let note = harness.submenu(harness.menus.makeMainMenu(), "Note")
        harness.choose(harness.item("Search Notes", in: note))
        #expect(harness.panel.screens.top is SearchScreen)
        #expect(!harness.isEnabled(harness.item("Move to Trash", in: note)))
        #expect(!harness.isEnabled(harness.item("New Note", in: note)))
        #expect(harness.isEnabled(harness.item("Show Trash", in: note)))
        #expect(harness.isEnabled(harness.item("Search Notes", in: note)))
    }

    @Test func settingsIsOffUntilSomethingOpensIt() throws {
        let without = try MenuHarness()
        #expect(!without.isEnabled(without.item("Settings…", in: without.submenu(without.menus.makeMainMenu(), "Pith"))))
        let with = try MenuHarness(openSettings: true)
        let item = with.item("Settings…", in: with.submenu(with.menus.makeMainMenu(), "Pith"))
        #expect(with.isEnabled(item))
        with.choose(item)
        #expect(with.settingsOpened == 1)
    }

    // MARK: Choosing

    @Test func closeHidesThePanelWhenItIsKey() throws {
        let harness = try MenuHarness()
        let close = harness.item("Close", in: harness.submenu(harness.menus.makeMainMenu(), "Window"))
        #expect(harness.isEnabled(close))
        harness.choose(close)
        #expect(harness.panel.hides == 1)
    }

    @Test func resetPanelSizeResetsThePanel() throws {
        let harness = try MenuHarness()
        harness.choose(harness.item("Reset Panel Size", in: harness.submenu(harness.menus.makeMainMenu(), "Window")))
        #expect(harness.panel.resets == 1)
    }

    @Test func commandNAndCommand1RunThroughTheMainMenu() throws {
        let harness = try MenuHarness(notes: ["one", "two"])
        let main = harness.menus.makeMainMenu()
        NSApplication.shared.mainMenu = main
        #expect(harness.note.editor.string == "two")
        _ = main.performKeyEquivalent(with: try harness.keyEvent("n", code: 45, .command))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(harness.note.editor.string == "")
        _ = main.performKeyEquivalent(with: try harness.keyEvent("1", code: 18, .command))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        #expect(harness.note.editor.string == "two")
    }

    @Test func shiftCommandBracketsPageAndLeaveIndentAndOutdentAlone() throws {
        let harness = try MenuHarness(notes: ["one", "two", "three"])
        #expect(harness.note.editor.string == "three")
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        // The Russian layout gives х and ъ on these keys; the key code decides.
        #expect(harness.menus.performKeyEquivalent(try harness.keyEvent("х", code: 33, flags)))
        #expect(harness.note.editor.string == "two")
        #expect(harness.menus.performKeyEquivalent(try harness.keyEvent("ъ", code: 30, flags)))
        #expect(harness.note.editor.string == "three")
        // ⌘[ and ⌘] alone are Outdent and Indent: the menu's.
        #expect(!harness.menus.performKeyEquivalent(try harness.keyEvent("[", code: 33, .command)))
        #expect(!harness.menus.performKeyEquivalent(try harness.keyEvent("]", code: 30, [.command, .shift, .option])))
        #expect(harness.note.editor.string == "three")
    }

    @Test func thePagingKeysFollowTheReassignedShortcuts() throws {
        let harness = try MenuHarness(notes: ["one", "two", "three"])
        // ⌘P for Previous Note (key code 35), so ⇧⌘[ no longer pages.
        harness.shortcuts.assign(Shortcut(keyCode: 35, modifiers: .command), to: .previousNote)
        #expect(!harness.menus.performKeyEquivalent(try harness.keyEvent("[", code: 33, [.command, .shift])))
        #expect(harness.menus.performKeyEquivalent(try harness.keyEvent("p", code: 35, .command)))
        #expect(harness.note.editor.string == "two")
    }

    @Test func thePagingKeysDoNothingWhenTheItemIsOff() throws {
        let harness = try MenuHarness(notes: ["one", "two"])
        harness.panel.isKey = false
        #expect(harness.menus.performKeyEquivalent(try harness.keyEvent("[", code: 33, [.command, .shift])))
        #expect(harness.note.editor.string == "two")
    }

    // MARK: Reassigning

    @Test func aReassignedShortcutShowsInTheMainMenuAtOnce() throws {
        let harness = try MenuHarness()
        let main = harness.menus.makeMainMenu()
        let note = harness.submenu(main, "Note")
        // ⌘B (key code 11) for New Note.
        #expect(harness.shortcuts.assign(Shortcut(keyCode: 11, modifiers: [.command, .shift]), to: .newNote) == nil)
        let item = harness.item("New Note", in: note)
        #expect(item?.keyEquivalent == "b")
        #expect(item?.keyEquivalentModifierMask == [.command, .shift])
        harness.shortcuts.restoreDefaults()
        #expect(item?.keyEquivalent == "n")
        #expect(item?.keyEquivalentModifierMask == .command)
    }

    @Test func aShortcutWithoutACharacterLeavesTheKeyEquivalentEmpty() throws {
        var layout = StubLayout()
        layout.characters[45] = nil
        let harness = try MenuHarness(layout: layout)
        let item = harness.item("New Note", in: harness.submenu(harness.menus.makeMainMenu(), "Note"))
        #expect(item?.keyEquivalent == "")
    }
}
