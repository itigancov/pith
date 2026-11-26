import AppKit
import Foundation
import Testing
@testable import PithApp
@testable import PithNotes

/// The Note screen, the Panel's stack and the Trash controller together, on a `.memory` database.
@MainActor
final class TrashWorld {
    let clock = TestClock(Date(timeIntervalSince1970: 1_795_000_000))
    let scheduler = ManualScheduler()
    let store: NoteStore
    let textSize = TextSizeModel(defaults: UserDefaults(suiteName: "pith-tests-" + UUID().uuidString)!)
    /// The alerts the screen put up, with what answers them.
    var alerts: [(alert: NSAlert, answer: (NSApplication.ModalResponse) -> Void)] = []
    var saveFailures: [String] = []

    private(set) var note: NoteScreen!
    private(set) var stack: ScreenStack!
    private(set) var controller: TrashController!
    private var window: NSWindow!
    private var content: PanelContentView!

    init() throws {
        let clock = clock
        store = try NoteStore.open(at: .memory, now: { clock.date }).store
    }

    @discardableResult
    func insert(_ text: String) throws -> Note {
        clock.advance(60)
        return try store.insert(text: text, selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)
    }

    /// Puts the Notes in the Trash one by one, a minute apart.
    func trash(_ notes: Note...) throws {
        for note in notes {
            clock.advance(60)
            try store.moveToTrash(ids: [note.id])
        }
    }

    func launch() {
        let store = store
        note = NoteScreen(openStore: { (store, nil) }, scheduler: scheduler, alerts: nil, textSize: textSize)
        let clock = clock
        note.now = { clock.date }
        content = PanelContentView()
        content.show(note)
        stack = ScreenStack(root: note)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = content
        stack.onChange = { [content, window] _, new in
            content?.show(new)
            window?.makeFirstResponder(new.preferredFirstResponder)
        }
        controller = TrashController(stack: stack, note: note)
        controller.now = { clock.date }
        controller.locale = Locale(identifier: "en_GB")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        controller.calendar = calendar
        controller.presentAlert = { [unowned self] alert, answer in alerts.append((alert, answer)) }
        note.load()
        window.makeFirstResponder(note.preferredFirstResponder)
    }

    var trashScreen: TrashScreen? { stack.top as? TrashScreen }

    func openTrash() throws -> TrashScreen {
        controller.showTrash(nil)
        return try #require(trashScreen)
    }

    func titles(_ screen: TrashScreen) -> [String] {
        screen.rows.indices.map { screen.display(at: $0).title }
    }
}

@MainActor
struct TrashScreenTests {
    let world: TrashWorld

    init() throws {
        world = try TrashWorld()
    }

    @Test func rowsAreTheTrashNewestDeletionFirstWithTitleAndTime() throws {
        let a = try world.insert("Alpha note\nbody")
        let b = try world.insert("# Beta note")
        let c = try world.insert("Gamma note")
        try world.insert("Delta stays")
        try world.trash(a, b, c)
        world.launch()
        let screen = try world.openTrash()
        #expect(world.titles(screen) == ["Gamma note", "Beta note", "Alpha note"])
        #expect(screen.titleText == "Trash · 3")
        #expect(screen.selectedRow == 0)
        #expect(screen.display(at: 0).time.hasPrefix("Deleted today, "))
        #expect(screen.display(at: 0).accessibilityLabel == "Gamma note, \(screen.display(at: 0).time)")
        #expect(screen.isEmptyTrashEnabled)
        #expect(screen.emptyMessage == nil)
    }

    @Test func anEmptyTrashSaysSoAndEmptyTrashIsOff() throws {
        try world.insert("Alpha")
        world.launch()
        let screen = try world.openTrash()
        #expect(screen.rows.isEmpty)
        #expect(screen.titleText == "Trash")
        let message = try #require(screen.emptyMessage)
        #expect(message.title == "Trash is empty")
        #expect(message.detail == "Deleted notes stay here until you delete them")
        #expect(!screen.isEmptyTrashEnabled)
    }

    @Test func theTimeIsTodayYesterdayThisYearAndEarlier() throws {
        let a = try world.insert("Alpha")
        let b = try world.insert("Beta")
        let c = try world.insert("Gamma")
        let d = try world.insert("Delta")
        let now = world.clock.date
        // The calendar of the test is UTC, `en_GB` locale.
        for (note, ago) in [(a, 400 * 86_400.0), (b, 20 * 86_400.0), (c, 86_400.0 + 60), (d, 60)] {
            world.clock.date = now.addingTimeInterval(-ago)
            try world.store.moveToTrash(ids: [note.id])
        }
        world.clock.date = now
        world.launch()
        let screen = try world.openTrash()
        let times = screen.rows.indices.map { screen.display(at: $0).time }
        // Newest deletion first: the order is by `deletedAt`.
        #expect(screen.rows.map(\.id) == [d.id, c.id, b.id, a.id])
        #expect(times[0].hasPrefix("Deleted today, "))
        #expect(times[1] == "Deleted yesterday")
        #expect(times[2].hasPrefix("Deleted ") && !times[2].contains("2026") && !times[2].contains("today"))
        #expect(times[3].hasSuffix("2025") || times[3].hasSuffix("2024"))
    }

    @Test func restoreByReturnRemovesTheRowKeepsTheTrashOpenAndMovesTheSelectionOn() throws {
        let a = try world.insert("Alpha")
        let b = try world.insert("Beta")
        let c = try world.insert("Gamma")
        try world.insert("Delta stays")
        try world.trash(a, b, c)
        world.launch()
        let screen = try world.openTrash()
        // Rows: Gamma, Beta, Alpha. Select Beta, restore it.
        screen.moveSelection(by: 1)
        screen.restoreSelected()
        #expect(world.titles(screen) == ["Gamma", "Alpha"])
        #expect(screen.selectedRow == 1)
        #expect(world.stack.top === screen)
        #expect(try world.store.note(id: b.id)?.deletedAt == nil)
        // The last row: the selection goes to the previous one.
        screen.restoreSelected()
        #expect(world.titles(screen) == ["Gamma"])
        #expect(screen.selectedRow == 0)
    }

    @Test func escapeGoesBackToTheNoteItCameFromWithTheStackReloaded() throws {
        let a = try world.insert("Alpha")
        let b = try world.insert("Beta")
        let open = try world.insert("Open one")
        try world.trash(a, b)
        world.launch()
        #expect(world.note.stack.ids == [open.id])
        let screen = try world.openTrash()
        screen.moveSelection(by: 1)
        screen.restoreSelected()
        #expect(screen.handleCancel())
        #expect(world.stack.top === world.note)
        // Alpha was restored: it stands before the open Note, which stays open.
        #expect(world.note.stack.ids == [a.id, open.id])
        #expect(world.note.stack.position == .note(open.id))
        #expect(world.note.editor.string == "Open one")
        #expect(world.note.footer.isActive)
        #expect(world.note.footer.counterText.hasSuffix("2 / 2"))
    }

    @Test func escapeWithNothingRestoredDoesNotLightTheFooter() throws {
        let a = try world.insert("Alpha")
        try world.insert("Open one")
        try world.trash(a)
        world.launch()
        let screen = try world.openTrash()
        _ = screen.handleCancel()
        #expect(world.stack.top === world.note)
        #expect(!world.note.footer.isActive)
    }

    @Test func aRestoredNoteKeepsItsUpdatedAt() throws {
        let a = try world.insert("Alpha")
        try world.insert("Other")
        try world.trash(a)
        world.launch()
        let screen = try world.openTrash()
        screen.restoreSelected()
        #expect(try world.store.note(id: a.id)?.updatedAt == a.updatedAt)
    }

    @Test func deletingPermanentlyAsksFirstAndCancelKeepsTheNote() throws {
        let a = try world.insert("Alpha")
        try world.insert("Other")
        try world.trash(a)
        world.launch()
        let screen = try world.openTrash()
        screen.deleteSelectedPermanently()
        let (alert, answer) = try #require(world.alerts.first)
        #expect(alert.messageText == "Delete note permanently?")
        #expect(alert.informativeText == "You can’t undo this.")
        #expect(alert.buttons.map(\.title) == ["Cancel", "Delete"])
        #expect(alert.buttons[1].hasDestructiveAction)
        #expect(try world.store.trashCount() == 1)
        answer(.alertFirstButtonReturn)
        #expect(try world.store.trashCount() == 1)
        #expect(screen.rows.count == 1)
    }

    @Test func confirmingDeletesTheNoteForGood() throws {
        let a = try world.insert("Alpha")
        let b = try world.insert("Beta")
        try world.insert("Other")
        try world.trash(a, b)
        world.launch()
        let screen = try world.openTrash()
        screen.deleteSelectedPermanently()
        world.alerts[0].answer(.alertSecondButtonReturn)
        #expect(try world.store.note(id: b.id) == nil)
        #expect(world.titles(screen) == ["Alpha"])
        #expect(screen.selectedRow == 0)
        #expect(screen.titleText == "Trash · 1")
    }

    @Test func emptyTrashAsksWithTheCountAndThenDeletesEverything() throws {
        let a = try world.insert("Alpha")
        let b = try world.insert("Beta")
        let c = try world.insert("Gamma")
        let keep = try world.insert("Other")
        try world.trash(a, b, c)
        world.launch()
        let screen = try world.openTrash()
        screen.emptyTrash()
        let (alert, answer) = try #require(world.alerts.first)
        #expect(alert.messageText == "Empty Trash?")
        #expect(alert.informativeText == "3 notes will be deleted for good. You can’t undo this.")
        #expect(alert.buttons.map(\.title) == ["Cancel", "Empty Trash"])
        answer(.alertSecondButtonReturn)
        #expect(try world.store.trashCount() == 0)
        #expect(screen.rows.isEmpty)
        #expect(screen.emptyMessage?.title == "Trash is empty")
        #expect(!screen.isEmptyTrashEnabled)
        #expect(try world.store.stack().map(\.id) == [keep.id])
    }

    @Test func emptyTrashForOneNoteSaysNote() throws {
        let a = try world.insert("Alpha")
        try world.insert("Other")
        try world.trash(a)
        world.launch()
        let screen = try world.openTrash()
        screen.emptyTrash()
        #expect(world.alerts[0].alert.informativeText == "1 note will be deleted for good. You can’t undo this.")
    }

    @Test func emptyTrashWithNothingInItDoesNotAsk() throws {
        try world.insert("Other")
        world.launch()
        let screen = try world.openTrash()
        screen.emptyTrash()
        screen.deleteSelectedPermanently()
        screen.restoreSelected()
        #expect(world.alerts.isEmpty)
    }

    @Test func showTrashWorksFromTheNoteAndFromSearchAndOnlyOnce() throws {
        try world.insert("Other")
        world.launch()
        let first = try world.openTrash()
        world.controller.showTrash(nil)
        #expect(world.stack.screens.count == 2)
        #expect(world.stack.top === first)
        _ = first.handleCancel()
        let search = SearchController(stack: world.stack, note: world.note)
        search.find(nil)
        #expect(world.stack.top is SearchScreen)
        world.controller.showTrash(nil)
        #expect(world.stack.top is TrashScreen)
        #expect(world.stack.screens.count == 3)
    }

    @Test func hidingThePanelInTheTrashShowsTheNoteNextTime() throws {
        try world.insert("Other")
        world.launch()
        _ = try world.openTrash()
        world.stack.hide()
        #expect(world.stack.top === world.note)
        let again = try world.openTrash()
        #expect(world.stack.top === again)
    }

    @Test func openingTheTrashEndsTheToast() throws {
        let a = try world.insert("Alpha")
        try world.insert("Beta")
        world.launch()
        world.note.moveToTrash(ids: [a.id])
        #expect(world.note.isToastShowing)
        _ = try world.openTrash()
        #expect(!world.note.isToastShowing)
    }

    @Test func theMenuItemsSwapWhenTheTrashIsOnTop() throws {
        try world.insert("Other")
        world.launch()
        #expect(world.controller.validateMenuItem(menuItem(#selector(TrashController.showTrash(_:)))))
        _ = try world.openTrash()
        #expect(!world.controller.validateMenuItem(menuItem(#selector(TrashController.showTrash(_:)))))
        #expect(!world.controller.validateMenuItem(menuItem(#selector(TrashController.moveToTrash(_:)))))
    }

    private func menuItem(_ action: Selector) -> NSMenuItem {
        NSMenuItem(title: "", action: action, keyEquivalent: "")
    }

    @Test func moveToTrashFromTheMenuNeedsTheNoteOnTop() throws {
        let a = try world.insert("Alpha")
        try world.insert("Beta")
        world.launch()
        #expect(world.controller.validateMenuItem(menuItem(#selector(TrashController.moveToTrash(_:)))))
        world.controller.moveToTrash(nil)
        #expect(try world.store.trashCount() == 1)
        _ = a
    }

    @Test func aFailedRestoreAlertsAndKeepsTheRow() throws {
        let a = try world.insert("Alpha")
        try world.insert("Other")
        try world.trash(a)
        world.launch()
        let screen = try world.openTrash()
        var reasons: [String] = []
        screen.onFailure = { reasons.append($0) }
        try world.store.execute("CREATE TRIGGER fail BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT, 'disk full'); END")
        screen.restoreSelected()
        #expect(reasons.count == 1)
        #expect(screen.rows.count == 1)
    }
}
