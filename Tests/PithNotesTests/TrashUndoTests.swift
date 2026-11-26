import Foundation
import Testing
@testable import PithNotes

struct TrashUndoTests {
    let a = UUID(), b = UUID(), c = UUID()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func later(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func thereIsNoToastUntilANoteIsDeleted() {
        var undo = TrashUndo()
        #expect(!undo.isShowing)
        #expect(undo.text == nil)
        #expect(undo.undo(now: start) == nil)
    }

    @Test func aDeletionShowsAToastForFiveSeconds() {
        var undo = TrashUndo()
        undo.deleted(ids: [a], now: start)
        #expect(undo.isShowing)
        #expect(undo.text == "Note moved to Trash")
        undo.tick(now: later(4.9))
        #expect(undo.isShowing)
        undo.tick(now: later(5))
        #expect(!undo.isShowing)
        #expect(undo.text == nil)
    }

    @Test func severalNotesGiveTheCountInTheText() {
        var undo = TrashUndo()
        undo.deleted(ids: [a, b, c], now: start)
        #expect(undo.text == "3 notes moved to Trash")
    }

    @Test func undoGivesTheIdsAndClosesTheToast() {
        var undo = TrashUndo()
        undo.deleted(ids: [a, b], now: start)
        #expect(undo.undo(now: later(2)) == [a, b])
        #expect(!undo.isShowing)
        #expect(undo.undo(now: later(2)) == nil)
    }

    @Test func undoAfterTheTermIsNothing() {
        var undo = TrashUndo()
        undo.deleted(ids: [a], now: start)
        #expect(undo.undo(now: later(5.1)) == nil)
    }

    @Test func aNewDeletionReplacesTheToastAndRestartsTheTerm() {
        var undo = TrashUndo()
        undo.deleted(ids: [a], now: start)
        undo.deleted(ids: [b], now: later(3))
        undo.tick(now: later(6))
        #expect(undo.isShowing)
        #expect(undo.undo(now: later(7)) == [b])
    }

    @Test func underTheMouseTheToastStaysAndAFullTermStartsWhenItLeaves() {
        var undo = TrashUndo()
        undo.deleted(ids: [a], now: start)
        undo.pause()
        undo.tick(now: later(60))
        #expect(undo.isShowing)
        undo.resume(now: later(60))
        undo.tick(now: later(64))
        #expect(undo.isShowing)
        undo.tick(now: later(65))
        #expect(!undo.isShowing)
    }

    @Test func pausingAnExpiredToastDoesNotRevive() {
        var undo = TrashUndo()
        undo.deleted(ids: [a], now: start)
        undo.tick(now: later(6))
        undo.pause()
        undo.resume(now: later(7))
        #expect(!undo.isShowing)
    }

    @Test func dismissClosesTheToast() {
        var undo = TrashUndo()
        undo.deleted(ids: [a], now: start)
        undo.dismiss()
        #expect(!undo.isShowing)
        #expect(undo.undo(now: start) == nil)
    }

    @Test func aDeletionOfNoNotesShowsNothing() {
        var undo = TrashUndo()
        undo.deleted(ids: [], now: start)
        #expect(!undo.isShowing)
    }
}
