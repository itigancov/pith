import AppKit
import Testing
@testable import PithApp

@MainActor
struct StackMenuTests {
    private final class Recorder: NSObject {
        var hits = 0
        @objc func hit(_ sender: Any?) { hits += 1 }
    }

    private func noteMenu() throws -> NSMenu {
        let main = AppDelegate().makeMainMenu()
        return try #require(main.items.first { $0.title == "Note" }?.submenu)
    }

    private func key(_ characters: String, ignoring: String, code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: code
        ))
    }

    /// The four paging items, which the next tests look at.
    private func pagingItems() throws -> [NSMenuItem] {
        Array(try noteMenu().items.prefix(4))
    }

    @Test func theNoteMenuHasTheFourPagingItemsAndTheTrashOnesWithTheNamesOfTheShortcutActions() throws {
        let menu = try noteMenu()
        #expect(menu.items.map(\.title) == ["New Note", "Go to Latest Note", "Previous Note", "Next Note", "", "Move to Trash", "Show Trash"])
        #expect(menu.items.map { $0.identifier?.rawValue } == ["newNote", "goToLatest", "previousNote", "nextNote", nil, "moveToTrash", "showTrash"])
        let trash = menu.items[5]
        #expect(trash.keyEquivalent == "\u{8}")
        #expect(trash.keyEquivalentModifierMask == [.command])
        #expect(menu.items[6].keyEquivalent == "")
        let titles = AppDelegate().makeMainMenu().items.map(\.title)
        #expect(titles.firstIndex(of: "Note") == titles.firstIndex(of: "View").map { $0 + 1 })
    }

    @Test func newNoteAndLatestAreOnTheirKeysInTheMenu() throws {
        let main = AppDelegate().makeMainMenu()
        NSApplication.shared.mainMenu = main
        let menu = try #require(main.items.first { $0.title == "Note" }?.submenu)
        menu.autoenablesItems = false
        let paging = Array(menu.items.prefix(4))
        let recorders = paging.map { _ in Recorder() }
        for (item, recorder) in zip(paging, recorders) {
            item.target = recorder
            item.action = #selector(Recorder.hit(_:))
            item.isEnabled = true
        }
        let events = [try key("n", ignoring: "n", code: 45, .command), try key("1", ignoring: "1", code: 18, .command)]
        for (index, event) in events.enumerated() {
            _ = main.performKeyEquivalent(with: event)
            // The menu flashes the item before it sends the action.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
            #expect(recorders.map(\.hits) == (0..<4).map { $0 <= index ? 1 : 0 }, "after key \(index)")
        }
    }

    @Test func theItemsShowTheShortcutsOfThePagingKeys() throws {
        let items = try pagingItems()
        #expect(items.map(\.keyEquivalent) == ["n", "1", "[", "]"])
        #expect(items[2].keyEquivalentModifierMask == [.command, .shift])
        #expect(items[3].keyEquivalentModifierMask == [.command, .shift])
    }

    @Test func shiftCommandBracketsPageByTheKeyWhateverTheLayout() throws {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        // The Russian layout: the keys of [ and ] give х and ъ.
        #expect(AppDelegate.pagingAction(for: try key("Х", ignoring: "х", code: 33, flags)) == #selector(AppDelegate.previousNote(_:)))
        #expect(AppDelegate.pagingAction(for: try key("}", ignoring: "]", code: 30, flags)) == #selector(AppDelegate.nextNote(_:)))
        // ⌘[ and ⌘] alone are Outdent and Indent.
        #expect(AppDelegate.pagingAction(for: try key("[", ignoring: "[", code: 33, .command)) == nil)
        #expect(AppDelegate.pagingAction(for: try key("]", ignoring: "]", code: 30, [.command, .shift, .option])) == nil)
    }

    @Test func theItemsAreOffWithoutANoteScreen() throws {
        let delegate = AppDelegate()
        let menu = delegate.makeMainMenu()
        let item = try #require(menu.items.first { $0.title == "Note" }?.submenu?.items.first)
        #expect(!delegate.validateMenuItem(item))
    }
}
