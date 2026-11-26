import Foundation
import Testing
@testable import PithNotes

struct StackTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    private func stack(_ ids: [UUID], at position: Stack.Position? = nil) -> Stack {
        Stack(ids: ids, position: position)
    }

    @Test func startsOnTheLastNoteOrABlank() {
        #expect(stack([a, b, c]).position == .note(c))
        #expect(stack([]).position == .blank)
    }

    @Test func nextGoesToTheFollowingNote() {
        var s = stack([a, b, c], at: .note(a))
        #expect(s.next() == .moved(from: .note(a), to: .note(b)))
        #expect(s.position == .note(b))
    }

    @Test func nextFromTheLastNoteGoesToTheBlank() {
        var s = stack([a, b])
        #expect(s.next() == .moved(from: .note(b), to: .blank))
        #expect(s.position == .blank)
    }

    @Test func nextOnTheBlankIsAnEdge() {
        var s = stack([a], at: .blank)
        #expect(s.next() == .edge)
        #expect(s.position == .blank)
    }

    @Test func previousGoesToThePrecedingNote() {
        var s = stack([a, b, c])
        #expect(s.previous() == .moved(from: .note(c), to: .note(b)))
        #expect(s.position == .note(b))
    }

    @Test func previousOnTheFirstNoteIsAnEdge() {
        var s = stack([a, b], at: .note(a))
        #expect(s.previous() == .edge)
        #expect(s.position == .note(a))
    }

    @Test func previousFromTheBlankGoesToTheLastNote() {
        var s = stack([a, b], at: .blank)
        #expect(s.previous() == .moved(from: .blank, to: .note(b)))
        #expect(s.next() == .moved(from: .note(b), to: .blank))
    }

    @Test func previousOnALoneBlankIsAnEdge() {
        var s = stack([])
        #expect(s.previous() == .edge)
        #expect(s.position == .blank)
    }

    @Test func newNoteGoesToTheBlank() {
        var s = stack([a, b], at: .note(a))
        #expect(s.newNote() == .moved(from: .note(a), to: .blank))
        #expect(s.position == .blank)
    }

    @Test func newNoteOnTheBlankDoesNothing() {
        var s = stack([a], at: .blank)
        #expect(s.newNote() == .none)
        #expect(s.position == .blank)
    }

    @Test func latestJumpsToTheGivenNote() {
        var s = stack([a, b, c], at: .note(a))
        #expect(s.latest(c) == .moved(from: .note(a), to: .note(c)))
        #expect(s.position == .note(c))
    }

    @Test func latestJumpsFromTheBlank() {
        var s = stack([a, b], at: .blank)
        #expect(s.latest(b) == .moved(from: .blank, to: .note(b)))
    }

    @Test func latestOnItselfIsAnEdge() {
        var s = stack([a, b])
        #expect(s.latest(b) == .edge)
        #expect(s.position == .note(b))
    }

    @Test func latestWithOnlyABlankDoesNothing() {
        var s = stack([])
        #expect(s.latest(nil) == .none)
        #expect(s.position == .blank)
    }

    @Test func latestIgnoresANoteNotInTheStack() {
        var s = stack([a])
        #expect(s.latest(UUID()) == .none)
    }

    @Test func showMovesToAnyNote() {
        var s = stack([a, b, c], at: .note(c))
        #expect(s.show(a) == .moved(from: .note(c), to: .note(a)))
        #expect(s.show(a) == .edge)
        #expect(s.show(UUID()) == .none)
        #expect(s.position == .note(a))
    }

    @Test func aBlankThatGotTextBecomesTheLastNote() {
        var s = stack([a], at: .blank)
        s.noteCreated(b)
        #expect(s.ids == [a, b])
        #expect(s.position == .note(b))
    }

    @Test func removingAnotherNoteKeepsThePosition() {
        var s = stack([a, b, c], at: .note(b))
        s.remove(a)
        #expect(s.ids == [b, c])
        #expect(s.position == .note(b))
        s.remove(UUID())
        #expect(s.ids == [b, c])
    }

    @Test func removingTheCurrentNoteMovesToItsNeighbour() {
        var s = stack([a, b, c], at: .note(b))
        s.remove(b)
        #expect(s.position == .note(c))
        s.remove(c)
        #expect(s.position == .note(a))
        s.remove(a)
        #expect(s.position == .blank)
    }

    @Test func removingANoteKeepsTheBlank() {
        var s = stack([a, b], at: .blank)
        s.remove(a)
        #expect(s.position == .blank)
        #expect(s.ids == [b])
    }

    // MARK: Trash

    @Test func removingSeveralNotesMovesTheOpenOneToTheNextThatStays() {
        var s = stack([a, b, c, d], at: .note(b))
        s.remove([b, c])
        #expect(s.ids == [a, d])
        #expect(s.position == .note(d))
    }

    @Test func removingSeveralIncludingTheLastOpensThePreviousThatStays() {
        var s = stack([a, b, c], at: .note(c))
        s.remove([b, c])
        #expect(s.ids == [a])
        #expect(s.position == .note(a))
    }

    @Test func removingEverythingOpensTheBlank() {
        var s = stack([a, b], at: .note(a))
        s.remove([a, b])
        #expect(s.ids.isEmpty)
        #expect(s.position == .blank)
    }

    @Test func removingOtherNotesKeepsTheOpenOne() {
        var s = stack([a, b, c], at: .note(c))
        s.remove([a])
        #expect(s.ids == [b, c])
        #expect(s.position == .note(c))
    }

    @Test func removingTheLastOpenNoteOfSeveralGivesWayToTheNext() {
        var s = stack([a, b, c], at: .note(a))
        s.remove(b)
        #expect(s.position == .note(a))
        s.remove(a)
        #expect(s.position == .note(c))
    }

    @Test func reloadingPutsARestoredNoteInItsPlaceAndKeepsThePosition() {
        var s = stack([a, c], at: .note(c))
        s.reload(ids: [a, b, c])
        #expect(s.ids == [a, b, c])
        #expect(s.position == .note(c))
        var blank = stack([a, c], at: .blank)
        blank.reload(ids: [a, b, c])
        #expect(blank.position == .blank)
        var first = stack([b, c], at: .note(b))
        first.reload(ids: [a, b, c])
        #expect(first.ids == [a, b, c])
        #expect(first.position == .note(b))
    }

    // MARK: Latest

    private func summary(_ id: UUID, created: Double, updated: Double) -> NoteSummary {
        NoteSummary(
            id: id, createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: updated), deletedAt: nil
        )
    }

    @Test func theNewestLatestIsTheLastNote() {
        let notes = [summary(a, created: 1, updated: 9), summary(b, created: 2, updated: 3)]
        #expect(Latest.newest.id(in: notes) == b)
    }

    @Test func theLastEditedLatestIsTheMostRecentlyUpdated() {
        let notes = [summary(a, created: 1, updated: 9), summary(b, created: 2, updated: 3)]
        #expect(Latest.lastEdited.id(in: notes) == a)
    }

    @Test func aTieOnUpdatedAtGoesToTheLaterCreated() {
        let notes = [summary(a, created: 1, updated: 5), summary(b, created: 2, updated: 5), summary(c, created: 0, updated: 5)]
        #expect(Latest.lastEdited.id(in: notes) == b)
    }

    @Test func noNotesNoLatest() {
        #expect(Latest.newest.id(in: []) == nil)
        #expect(Latest.lastEdited.id(in: []) == nil)
    }
}
