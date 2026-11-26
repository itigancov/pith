import AppKit
import Testing
@testable import PithApp

@MainActor
struct StatusMenuTests {
    private func shown(_ harness: MenuHarness) -> NSMenu {
        let menu = harness.menus.makeStatusMenu()
        menu.delegate?.menuNeedsUpdate?(menu)
        return menu
    }

    @Test func theMenuIsTheOneOfTheArtboard() throws {
        let harness = try MenuHarness()
        let menu = harness.menus.makeStatusMenu()
        #expect(harness.layout(of: menu) ==
            ["Open Pith", "New Note", "Go to Latest Note", "|", "Trash", "Settings…", "Reset Panel Size", "|", "Quit Pith"])
    }

    @Test func theItemsShowTheCurrentShortcutsAndTheHotkey() throws {
        let harness = try MenuHarness()
        let menu = harness.menus.makeStatusMenu()
        let open = harness.item("Open Pith", in: menu)
        #expect(open?.identifier?.rawValue == "hotkey")
        // Key code 49 has a name of its own: Space.
        #expect(open?.keyEquivalent == " ")
        #expect(open?.keyEquivalentModifierMask == .option)
        #expect(harness.item("New Note", in: menu)?.keyEquivalent == "n")
        #expect(harness.item("Go to Latest Note", in: menu)?.keyEquivalent == "1")
        #expect(harness.item("Settings…", in: menu)?.keyEquivalent == ",")
        #expect(harness.item("Quit Pith", in: menu)?.keyEquivalent == "q")
        #expect(harness.item("Trash", in: menu)?.identifier?.rawValue == "showTrash")
        #expect(harness.item("Trash", in: menu)?.keyEquivalent == "")
    }

    @Test func aReassignedShortcutAndHotkeyShowAtOnce() throws {
        let harness = try MenuHarness()
        let menu = harness.menus.makeStatusMenu()
        #expect(harness.shortcuts.assign(Shortcut(keyCode: 11, modifiers: [.command, .shift]), to: .newNote) == nil)
        #expect(harness.shortcuts.assign(Shortcut(keyCode: 6, modifiers: [.control, .option]), to: .hotkey) == nil)
        #expect(harness.item("New Note", in: menu)?.keyEquivalent == "b")
        #expect(harness.item("Open Pith", in: menu)?.keyEquivalent == "z")
        #expect(harness.item("Open Pith", in: menu)?.keyEquivalentModifierMask == [.control, .option])
        harness.shortcuts.restoreDefaults()
        #expect(harness.item("New Note", in: menu)?.keyEquivalent == "n")
        #expect(harness.item("Open Pith", in: menu)?.keyEquivalent == " ")
    }

    @Test func theTrashShowsTheNumberOfNotesInIt() throws {
        let harness = try MenuHarness(notes: ["one", "two", "three"])
        let ids = try harness.store.stack().map(\.id)
        #expect(harness.item("Trash", in: shown(harness))?.badge == nil)
        _ = try harness.store.moveToTrash(ids: ids)
        let badge = harness.item("Trash", in: shown(harness))?.badge
        #expect(badge?.itemCount == 3)
        #expect(badge?.stringValue == "3")
        #expect(harness.isEnabled(harness.item("Trash", in: shown(harness))))
    }

    @Test func theNumberIsGoneWhenTheTrashIsEmptiedAndItemStaysOn() throws {
        let harness = try MenuHarness(notes: ["one"])
        let menu = harness.menus.makeStatusMenu()
        _ = try harness.store.moveToTrash(ids: try harness.store.stack().map(\.id))
        menu.delegate?.menuNeedsUpdate?(menu)
        #expect(harness.item("Trash", in: menu)?.badge != nil)
        _ = try harness.store.emptyTrash()
        menu.delegate?.menuNeedsUpdate?(menu)
        #expect(harness.item("Trash", in: menu)?.badge == nil)
        #expect(harness.isEnabled(harness.item("Trash", in: menu)))
    }

    @Test func withoutNotesThereIsNoNumberAndTheNoteItemsAreOff() throws {
        let harness = try MenuHarness(load: false)
        let menu = shown(harness)
        #expect(harness.item("Trash", in: menu)?.badge == nil)
        for title in ["New Note", "Go to Latest Note", "Trash"] { #expect(!harness.isEnabled(harness.item(title, in: menu)), "\(title)") }
        for title in ["Open Pith", "Reset Panel Size", "Quit Pith"] { #expect(harness.isEnabled(harness.item(title, in: menu)), "\(title)") }
    }

    @Test func settingsIsOffUntilSomethingOpensIt() throws {
        let without = try MenuHarness()
        #expect(!without.isEnabled(without.item("Settings…", in: without.menus.makeStatusMenu())))
        let with = try MenuHarness(openSettings: true)
        let item = with.item("Settings…", in: with.menus.makeStatusMenu())
        #expect(with.isEnabled(item))
        with.choose(item)
        #expect(with.settingsOpened == 1)
    }

    // MARK: Choosing

    @Test func openPithShowsThePanelAndDoesNothingElse() throws {
        let harness = try MenuHarness(notes: ["one"])
        let menu = harness.menus.makeStatusMenu()
        harness.choose(harness.item("Open Pith", in: menu))
        harness.choose(harness.item("Open Pith", in: menu))
        #expect(harness.panel.reveals == 2)
        #expect(harness.panel.hides == 0)
        #expect(harness.panel.isShown)
    }

    @Test func openPithWorksWhenTheSystemRefusedTheHotkey() throws {
        let harness = try MenuHarness()
        harness.registrar.refused = [harness.shortcuts.shortcut(for: .hotkey)]
        #expect(!harness.shortcuts.registerHotkey())
        harness.choose(harness.item("Open Pith", in: harness.menus.makeStatusMenu()))
        #expect(harness.panel.isShown)
    }

    @Test func newNoteShowsThePanelAndOpensABlank() throws {
        let harness = try MenuHarness(notes: ["one"])
        harness.panel.isKey = false
        harness.choose(harness.item("New Note", in: harness.menus.makeStatusMenu()))
        #expect(harness.panel.reveals == 1)
        #expect(harness.note.editor.string == "")
    }

    @Test func goToLatestShowsThePanelOnTheLatestNote() throws {
        let harness = try MenuHarness(notes: ["one", "two"])
        harness.note.previousNote()
        #expect(harness.note.editor.string == "one")
        harness.choose(harness.item("Go to Latest Note", in: harness.menus.makeStatusMenu()))
        #expect(harness.panel.reveals == 1)
        #expect(harness.note.editor.string == "two")
    }

    @Test func fromSearchNewNoteAndGoToLatestComeBackToTheNote() throws {
        let harness = try MenuHarness(notes: ["one", "two"])
        let menu = harness.menus.makeStatusMenu()
        harness.search.find(nil)
        #expect(harness.panel.screens.top is SearchScreen)
        harness.choose(harness.item("New Note", in: menu))
        #expect(harness.panel.screens.top === harness.note)
        #expect(harness.note.editor.string == "")
        harness.search.find(nil)
        harness.choose(harness.item("Go to Latest Note", in: menu))
        #expect(harness.panel.screens.top === harness.note)
        #expect(harness.note.editor.string == "two")
    }

    @Test func fromTheTrashNewNoteComesBackToTheNote() throws {
        let harness = try MenuHarness(notes: ["one"])
        harness.trash.showTrash(nil)
        #expect(harness.panel.screens.top is TrashScreen)
        harness.choose(harness.item("New Note", in: harness.menus.makeStatusMenu()))
        #expect(harness.panel.screens.top === harness.note)
    }

    @Test func trashShowsThePanelWithTheTrash() throws {
        let harness = try MenuHarness(notes: ["one"])
        harness.choose(harness.item("Trash", in: harness.menus.makeStatusMenu()))
        #expect(harness.panel.reveals == 1)
        #expect(harness.panel.screens.top is TrashScreen)
    }

    @Test func trashWithTheTrashOnTopOnlyShowsThePanel() throws {
        let harness = try MenuHarness(notes: ["one"])
        let menu = harness.menus.makeStatusMenu()
        harness.choose(harness.item("Trash", in: menu))
        let top = harness.panel.screens.top
        harness.choose(harness.item("Trash", in: menu))
        #expect(harness.panel.screens.top === top)
        #expect(harness.panel.screens.screens.count == 2)
        #expect(harness.panel.reveals == 2)
    }

    @Test func trashFromSearchOpensTheTrashOverIt() throws {
        let harness = try MenuHarness(notes: ["one"])
        harness.search.find(nil)
        harness.choose(harness.item("Trash", in: harness.menus.makeStatusMenu()))
        #expect(harness.panel.screens.top is TrashScreen)
    }

    @Test func withAnAlertWaitingEveryCommandOnlyShowsThePanel() throws {
        let harness = try MenuHarness(notes: ["one", "two"])
        harness.panel.hasAlert = true
        harness.search.find(nil)
        let menu = harness.menus.makeStatusMenu()
        for title in ["New Note", "Go to Latest Note", "Trash"] { harness.choose(harness.item(title, in: menu)) }
        #expect(harness.panel.reveals == 3)
        #expect(harness.panel.screens.top is SearchScreen)
        #expect(harness.note.editor.string == "two")
        #expect(harness.panel.screens.screens.count == 2)
    }

    @Test func resetPanelSizeResetsThePanel() throws {
        let harness = try MenuHarness()
        harness.choose(harness.item("Reset Panel Size", in: harness.menus.makeStatusMenu()))
        #expect(harness.panel.resets == 1)
    }
}
