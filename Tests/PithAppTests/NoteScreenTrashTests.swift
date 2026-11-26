import AppKit
import Foundation
import Testing
@testable import PithApp
@testable import PithNotes

/// ⌘⌫, the toast and Undo: the screen, its store and its footer together, on a `.memory` database and a scheduler moved by hand.
@MainActor
struct NoteScreenTrashTests {
    let clock: TestClock
    let scheduler = ManualScheduler()
    let alerts = AlertSpy()
    let store: NoteStore
    let defaults = UserDefaults(suiteName: "pith-tests-" + UUID().uuidString)!
    let textSize = TextSizeModel(defaults: UserDefaults(suiteName: "pith-tests-" + UUID().uuidString)!)

    init() throws {
        let clock = TestClock()
        self.clock = clock
        store = try NoteStore.open(at: .memory, now: { clock.date }).store
    }

    private func makeScreen(start: Stack.Position? = nil) -> (NoteScreen, NSWindow) {
        let store = store
        let screen = NoteScreen(openStore: { (store, nil) }, scheduler: scheduler, alerts: alerts, textSize: textSize, defaults: defaults)
        let clock = clock
        screen.now = { clock.date }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = screen.view
        screen.load(start: start)
        return (screen, window)
    }

    @discardableResult
    private func insert(_ text: String) throws -> Note {
        clock.advance(1)
        return try store.insert(text: text, selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)
    }

    private func type(_ text: String, in screen: NoteScreen) {
        screen.editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: ⌘⌫

    @Test func aNoteInTheMiddleGoesToTheTrashAndTheNextTakesItsPlace() throws {
        let a = try insert("one")
        let b = try insert("two")
        let c = try insert("three")
        let (screen, window) = makeScreen(start: .note(b.id))
        screen.moveToTrash()
        #expect(screen.editor.string == "three")
        #expect(screen.stack.ids == [a.id, c.id])
        #expect(screen.stack.position == .note(c.id))
        #expect(try store.note(id: b.id)?.deletedAt != nil)
        #expect(try store.trash().map(\.id) == [b.id])
        _ = window
    }

    @Test func theLastNoteGivesWayToThePrevious() throws {
        try insert("one")
        let b = try insert("two")
        let c = try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        #expect(screen.editor.string == "two")
        #expect(screen.stack.position == .note(b.id))
        #expect(try store.note(id: c.id)?.deletedAt != nil)
        _ = window
    }

    @Test func theOnlyNoteGivesWayToABlank() throws {
        let a = try insert("one")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        #expect(screen.editor.string == "")
        #expect(screen.editor.isShowingPlaceholder)
        #expect(screen.stack.position == .blank)
        #expect(try store.note(id: a.id)?.deletedAt != nil)
        _ = window
    }

    @Test func theFooterDoesNotLightAndTheToastTakesItsPlace() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        #expect(!screen.isToastShowing)
        screen.moveToTrash()
        #expect(!screen.footer.isActive)
        #expect(screen.footer.isHidden)
        #expect(screen.isToastShowing)
        #expect(screen.toastText == "Note moved to Trash")
        #expect(screen.footer.dots.count == 1)
        _ = window
    }

    @Test func theTextTypedJustBeforeIsSavedBeforeTheNoteGoes() throws {
        try insert("one")
        let b = try insert("two")
        let (screen, window) = makeScreen()
        type("X", in: screen)
        screen.moveToTrash()
        let trashed = try #require(try store.note(id: b.id))
        #expect(trashed.deletedAt != nil)
        #expect(trashed.text == "Xtwo")
        _ = window
    }

    @Test func aBlankWithNotesGoesBackToThePreviousNoteWithoutAToast() throws {
        let a = try insert("one")
        let (screen, window) = makeScreen()
        screen.newNote()
        screen.moveToTrash()
        #expect(screen.stack.position == .note(a.id))
        #expect(screen.editor.string == "one")
        #expect(!screen.isToastShowing)
        #expect(try store.trashCount() == 0)
        _ = window
    }

    @Test func aBlankWithoutNotesDoesNothing() throws {
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        #expect(screen.stack.position == .blank)
        #expect(!screen.isToastShowing)
        _ = window
    }

    @Test func aNoteWhoseTextWasErasedIsDeletedForGoodWithoutAToast() throws {
        let a = try insert("one")
        let b = try insert("two")
        let (screen, window) = makeScreen()
        screen.editor.setSelectedRange(NSRange(location: 0, length: 3))
        type("", in: screen)
        screen.moveToTrash()
        #expect(try store.note(id: b.id) == nil)
        #expect(try store.trashCount() == 0)
        #expect(screen.stack.ids == [a.id])
        #expect(screen.stack.position == .note(a.id))
        #expect(!screen.isToastShowing)
        _ = window
    }

    // MARK: Undo

    @Test func undoBringsTheNoteBackToItsPlaceAndOpensIt() throws {
        let a = try insert("one")
        let b = try insert("two")
        let c = try insert("three")
        let (screen, window) = makeScreen(start: .note(b.id))
        screen.moveToTrash()
        #expect(screen.undoMoveToTrash())
        #expect(screen.stack.ids == [a.id, b.id, c.id])
        #expect(screen.stack.position == .note(b.id))
        #expect(screen.editor.string == "two")
        #expect(try store.note(id: b.id)?.deletedAt == nil)
        #expect(!screen.isToastShowing)
        #expect(!screen.footer.isHidden)
        #expect(screen.footer.isActive)
        #expect(screen.footer.counterText == "2 / 3")
        _ = window
    }

    @Test func undoOfTheOnlyNoteLeavesTheBlank() throws {
        let a = try insert("one")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        #expect(screen.undoMoveToTrash())
        #expect(screen.stack.position == .note(a.id))
        #expect(screen.editor.string == "one")
        _ = window
    }

    @Test func commandZWhileTheToastIsUpUndoesTheDeletionNotTheText() throws {
        try insert("one")
        let b = try insert("two")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        let manager = try #require(screen.undoManager(for: screen.editor))
        #expect(manager.canUndo)
        manager.undo()
        #expect(screen.stack.position == .note(b.id))
        #expect(screen.editor.string == "two")
        _ = window
    }

    @Test func commandZAfterTypingIsTheTextsUndo() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        #expect(screen.editor.string == "one")
        type("X", in: screen)
        #expect(!screen.isToastShowing)
        screen.undoManager(for: screen.editor)?.undo()
        #expect(screen.editor.string == "one")
        #expect(screen.stack.ids.count == 1)
        #expect(try store.trashCount() == 1)
        _ = window
    }

    @Test func undoWithoutAToastDoesNothing() throws {
        try insert("one")
        let (screen, window) = makeScreen()
        #expect(!screen.undoMoveToTrash())
        #expect(screen.undoManager(for: screen.editor)?.canUndo == false)
        _ = window
    }

    @Test func undoAfterPagingDoesNotRestore() throws {
        try insert("one")
        try insert("two")
        try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        screen.previousNote()
        #expect(!screen.isToastShowing)
        #expect(!screen.undoMoveToTrash())
        #expect(try store.trashCount() == 1)
        _ = window
    }

    // MARK: The toast's life

    @Test func theToastGoesOutAfterFiveSeconds() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        scheduler.advance(by: 4.9)
        #expect(screen.isToastShowing)
        scheduler.advance(by: 0.2)
        #expect(!screen.isToastShowing)
        #expect(!screen.footer.isHidden)
        _ = window
    }

    @Test func theMouseOnTheToastHoldsItAndAFullTermStartsWhenItLeaves() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        scheduler.advance(by: 3)
        screen.toastHoverChanged(true)
        scheduler.advance(by: 60)
        #expect(screen.isToastShowing)
        screen.toastHoverChanged(false)
        scheduler.advance(by: 4.9)
        #expect(screen.isToastShowing)
        scheduler.advance(by: 0.2)
        #expect(!screen.isToastShowing)
        _ = window
    }

    @Test func aSecondDeletionReplacesTheToastAndUndoBringsBackOnlyThatNote() throws {
        let a = try insert("one")
        let b = try insert("two")
        let c = try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        scheduler.advance(by: 3)
        screen.moveToTrash()
        scheduler.advance(by: 3)
        #expect(screen.isToastShowing)
        #expect(screen.undoMoveToTrash())
        #expect(screen.stack.ids == [a.id, b.id])
        #expect(try store.trash().map(\.id) == [c.id])
        #expect(screen.stack.position == .note(b.id))
        _ = window
    }

    @Test func aToastThatReplacesOneUnderTheMouseIsHeldToo() throws {
        try insert("one")
        try insert("two")
        try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        screen.toastHoverChanged(true)
        screen.moveToTrash()
        scheduler.advance(by: 60)
        #expect(screen.isToastShowing)
        screen.toastHoverChanged(false)
        scheduler.advance(by: 5.1)
        #expect(!screen.isToastShowing)
        _ = window
    }

    @Test func aToastAfterOneThatEndedUnderTheMouseIsNotHeld() throws {
        try insert("one")
        try insert("two")
        try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        screen.toastHoverChanged(true)
        screen.moveToTrash()
        screen.toastHoverChanged(false)
        scheduler.advance(by: 6)
        #expect(!screen.isToastShowing)
        screen.moveToTrash()
        scheduler.advance(by: 6)
        #expect(!screen.isToastShowing)
        _ = window
    }

    @Test func hidingThePanelOrCoveringTheNoteEndsTheToast() throws {
        try insert("one")
        try insert("two")
        try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash()
        screen.willCover()
        #expect(!screen.isToastShowing)
        screen.moveToTrash()
        screen.willHide()
        #expect(!screen.isToastShowing)
        _ = window
    }

    @Test func aFailedWriteLeavesTheNoteAndShowsTheAlert() throws {
        let a = try insert("one")
        let (screen, window) = makeScreen()
        try store.execute("DROP TRIGGER IF EXISTS fail; CREATE TRIGGER fail BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT, 'disk full'); END")
        screen.moveToTrash()
        #expect(screen.stack.position == .note(a.id))
        #expect(screen.editor.string == "one")
        #expect(!screen.isToastShowing)
        #expect(!alerts.saveFailures.isEmpty)
        #expect(try store.trashCount() == 0)
        _ = window
    }

    // MARK: Several Notes

    @Test func severalNotesGoTogetherWithOneToastAndOneUndo() throws {
        let a = try insert("one")
        let b = try insert("two")
        let c = try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash(ids: [b.id, c.id])
        #expect(screen.toastText == "2 notes moved to Trash")
        #expect(screen.stack.ids == [a.id])
        #expect(screen.stack.position == .note(a.id))
        #expect(screen.editor.string == "one")
        #expect(screen.undoMoveToTrash())
        #expect(screen.stack.ids == [a.id, b.id, c.id])
        #expect(screen.stack.position == .note(b.id))
        #expect(try store.trashCount() == 0)
        _ = window
    }

    @Test func severalNotesThatDoNotIncludeTheOpenOneLeaveItOpen() throws {
        let a = try insert("one")
        let b = try insert("two")
        let c = try insert("three")
        let (screen, window) = makeScreen()
        screen.moveToTrash(ids: [a.id, b.id])
        #expect(screen.stack.position == .note(c.id))
        #expect(screen.editor.string == "three")
        #expect(screen.toastText == "2 notes moved to Trash")
        _ = window
    }
}
