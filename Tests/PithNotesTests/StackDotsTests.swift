import Foundation
import Testing
@testable import PithNotes

struct StackDotsTests {
    private func ids(_ count: Int) -> [UUID] { (0..<count).map { _ in UUID() } }

    private func kinds(_ dots: [StackDots.Dot]) -> [StackDots.Kind] { dots.map(\.kind) }

    @Test func fewPositionsAreAllRegularAroundTheCurrent() {
        let notes = ids(4)
        let dots = StackDots.layout(ids: notes, position: .note(notes[1]))
        #expect(kinds(dots) == [.regular, .current, .regular, .regular])
        #expect(dots.map(\.key) == notes.map(\.uuidString))
    }

    @Test func sevenPositionsFitWithoutEdges() {
        let notes = ids(7)
        let dots = StackDots.layout(ids: notes, position: .note(notes[3]))
        #expect(kinds(dots) == [.regular, .regular, .regular, .current, .regular, .regular, .regular])
    }

    @Test func eightPositionsInTheMiddleShowASevenWindowWithEdgesOnBothSides() {
        let notes = ids(40)
        let dots = StackDots.layout(ids: notes, position: .note(notes[11]))
        #expect(dots.count == 7)
        #expect(kinds(dots) == [.edge, .regular, .regular, .current, .regular, .regular, .edge])
        // The current Note is in the middle: window 8...14.
        #expect(dots.map(\.key) == notes[8...14].map(\.uuidString))
    }

    @Test func atTheStartOnlyTheFarSideIsAnEdge() {
        let notes = ids(40)
        let dots = StackDots.layout(ids: notes, position: .note(notes[0]))
        #expect(kinds(dots) == [.current, .regular, .regular, .regular, .regular, .regular, .edge])
        let second = StackDots.layout(ids: notes, position: .note(notes[1]))
        #expect(kinds(second) == [.regular, .current, .regular, .regular, .regular, .regular, .edge])
    }

    @Test func atTheEndOnlyTheNearSideIsAnEdge() {
        let notes = ids(40)
        let dots = StackDots.layout(ids: notes, position: .note(notes[39]))
        #expect(kinds(dots) == [.edge, .regular, .regular, .regular, .regular, .regular, .current])
    }

    @Test func eightPositionsHaveOneEdge() {
        let notes = ids(8)
        let dots = StackDots.layout(ids: notes, position: .note(notes[0]))
        #expect(kinds(dots) == [.current, .regular, .regular, .regular, .regular, .regular, .edge])
        let last = StackDots.layout(ids: notes, position: .note(notes[7]))
        #expect(kinds(last) == [.edge, .regular, .regular, .regular, .regular, .regular, .current])
    }

    @Test func theBlankIsTheLastPosition() {
        let notes = ids(3)
        let dots = StackDots.layout(ids: notes, position: .blank)
        #expect(kinds(dots) == [.regular, .regular, .regular, .blank])
        #expect(dots.last?.key == "blank")
    }

    @Test func theBlankAfterManyNotesIsLastInTheWindow() {
        let notes = ids(40)
        let dots = StackDots.layout(ids: notes, position: .blank)
        #expect(kinds(dots) == [.edge, .regular, .regular, .regular, .regular, .regular, .blank])
        #expect(dots.dropLast().map(\.key) == notes[34...].map(\.uuidString))
    }

    @Test func aLoneNoteIsOneCurrentDot() {
        let notes = ids(1)
        #expect(kinds(StackDots.layout(ids: notes, position: .note(notes[0]))) == [.current])
    }

    @Test func anEmptyStackIsOneBlankDot() {
        #expect(kinds(StackDots.layout(ids: [], position: .blank)) == [.blank])
    }

    // MARK: Counter

    @Test func theCounterShowsThePositionAndTheTotal() {
        let notes = ids(40)
        #expect(StackDots.counter(ids: notes, position: .note(notes[11]), latest: nil) == "12 / 40")
    }

    @Test func theCounterOfABlankIsNew() {
        #expect(StackDots.counter(ids: ids(5), position: .blank, latest: nil) == "New")
        #expect(StackDots.counter(ids: [], position: .blank, latest: nil) == "New")
    }

    @Test func theCounterOfTheLatestNoteHasThePrefix() {
        let notes = ids(10)
        #expect(StackDots.counter(ids: notes, position: .note(notes[9]), latest: notes[9]) == "Latest · 10 / 10")
        #expect(StackDots.counter(ids: notes, position: .note(notes[8]), latest: notes[9]) == "9 / 10")
    }

    @Test func theLatestOfALoneNote() {
        let notes = ids(1)
        #expect(StackDots.counter(ids: notes, position: .note(notes[0]), latest: notes[0]) == "Latest · 1 / 1")
    }

    @Test func theVoiceOverStrings() {
        let notes = ids(40)
        #expect(StackDots.spoken(ids: notes, position: .note(notes[11]), latest: nil) == "Note 12 of 40")
        #expect(StackDots.spoken(ids: notes, position: .note(notes[9]), latest: notes[9]) == "Latest, note 10 of 40")
        #expect(StackDots.spoken(ids: notes, position: .blank, latest: notes[9]) == "New note")
    }
}
