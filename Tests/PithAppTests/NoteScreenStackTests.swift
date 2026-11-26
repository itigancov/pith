import AppKit
import Foundation
import Testing
@testable import PithApp
@testable import PithNotes

/// Paging through the Stack: the screen, its store and its footer together, on a `.memory` database and a scheduler moved by hand.
@MainActor
struct NoteScreenStackTests {
    let clock: TestClock
    let scheduler = ManualScheduler()
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
        let screen = NoteScreen(openStore: { (store, nil) }, scheduler: scheduler, textSize: textSize, defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = screen.view
        screen.load(start: start)
        return (screen, window)
    }

    @discardableResult
    private func insert(_ text: String, selection: NoteSelection = NoteSelection(location: 0, length: 0)) throws -> Note {
        clock.advance(1)
        return try store.insert(text: text, selection: selection, scrollOffset: 0)
    }

    private func type(_ text: String, in screen: NoteScreen) {
        screen.editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func erase(_ screen: NoteScreen) {
        screen.editor.setSelectedRange(NSRange(location: 0, length: (screen.editor.string as NSString).length))
        screen.editor.insertText("", replacementRange: screen.editor.selectedRange())
    }

    // MARK: Paging

    @Test func previousAndNextPageThroughTheStack() throws {
        try insert("one")
        try insert("two")
        try insert("three")
        let (screen, window) = makeScreen()
        #expect(screen.editor.string == "three")
        screen.previousNote()
        #expect(screen.editor.string == "two")
        screen.previousNote()
        #expect(screen.editor.string == "one")
        screen.nextNote()
        #expect(screen.editor.string == "two")
        _ = window
    }

    @Test func leavingANoteWritesItsTextAndViewState() throws {
        let first = try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.previousNote()
        screen.editor.setSelectedRange(NSRange(location: 1, length: 2))
        type("X", in: screen)
        screen.nextNote()
        let saved = try #require(try store.note(id: first.id))
        #expect(saved.text == "oX")
        #expect(saved.selection == NoteSelection(location: 2, length: 0))
        _ = window
    }

    @Test func theFirstNoteIsAnEdgeThatLightsTheFooterAndNothingElse() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.previousNote()
        screen.footer.reset()
        screen.previousNote()
        #expect(screen.editor.string == "one")
        #expect(screen.footer.isActive)
        #expect(screen.footer.counterText == "1 / 2")
        _ = window
    }

    @Test func pagingPastTheLastNoteOpensABlankWithThePlaceholder() throws {
        try insert("one")
        let (screen, window) = makeScreen()
        screen.nextNote()
        #expect(screen.editor.string == "")
        #expect(screen.editor.isShowingPlaceholder)
        #expect(screen.stack.position == .blank)
        #expect(screen.footer.counterText == "New")
        screen.nextNote()
        #expect(screen.stack.position == .blank)
        #expect(screen.footer.isActive)
        _ = window
    }

    @Test func aBlankLeftEmptyIsGone() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.newNote()
        screen.previousNote()
        #expect(screen.editor.string == "two")
        #expect(screen.stack.ids.count == 2)
        #expect(try store.stack().count == 2)
        #expect(screen.footer.dots.count == 2)
        _ = window
    }

    @Test func typingInABlankAppendsANoteToTheStack() throws {
        let first = try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.newNote()
        type("fresh", in: screen)
        scheduler.advance(by: 0.5)
        let stack = try store.stack()
        #expect(stack.count == 3)
        #expect(screen.stack.ids == stack.map(\.id))
        #expect(screen.stack.position == .note(stack[2].id))
        #expect(screen.stack.ids.first == first.id)
        #expect(screen.footer.counterText == "Latest · 3 / 3")
        _ = window
    }

    @Test func aBlankWithPendingTextCountsAsANoteWhenYouLeave() throws {
        try insert("one")
        let (screen, window) = makeScreen()
        screen.newNote()
        type("fresh", in: screen)
        screen.previousNote()
        #expect(screen.editor.string == "one")
        #expect(try store.stack().count == 2)
        screen.nextNote()
        #expect(screen.editor.string == "fresh")
        _ = window
    }

    @Test func newNoteOnABlankDoesNothing() throws {
        let (screen, window) = makeScreen()
        screen.newNote()
        #expect(!screen.footer.isActive)
        _ = window
    }

    @Test func goToLatestJumpsToTheNewestNoteFromAnywhereIncludingTheBlank() throws {
        try insert("one")
        try insert("two")
        try insert("three")
        let (screen, window) = makeScreen()
        screen.previousNote()
        screen.previousNote()
        screen.goToLatest()
        #expect(screen.editor.string == "three")
        #expect(screen.footer.counterText == "Latest · 3 / 3")
        screen.newNote()
        screen.goToLatest()
        #expect(screen.editor.string == "three")
        _ = window
    }

    @Test func goToLatestOnLatestOnlyLightsTheFooter() throws {
        try insert("one")
        let (screen, window) = makeScreen()
        screen.goToLatest()
        #expect(screen.footer.isActive)
        #expect(screen.footer.counterText == "Latest · 1 / 1")
        _ = window
    }

    @Test func goToLatestWithOnlyABlankDoesNothing() {
        let (screen, window) = makeScreen()
        screen.goToLatest()
        #expect(!screen.footer.isActive)
        _ = window
    }

    @Test func theLastEditedLatestFollowsTheEdits() throws {
        let first = try insert("one")
        try insert("two")
        try insert("three")
        let (screen, window) = makeScreen()
        screen.latestMeans = { .lastEdited }
        screen.show(noteID: first.id)
        clock.advance(100)
        type("!", in: screen)
        screen.nextNote()
        screen.goToLatest()
        #expect(screen.editor.string == "!one")
        #expect(screen.stack.position == .note(first.id))
        #expect(screen.footer.counterText == "Latest · 1 / 3")
        _ = window
    }

    @Test func showNoteIDPagesToThatNote() throws {
        let first = try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.show(noteID: first.id)
        #expect(screen.editor.string == "one")
        screen.show(noteID: UUID())
        #expect(screen.editor.string == "one")
        _ = window
    }

    // MARK: Empty Notes

    @Test func aNoteLeftEmptyIsDeletedForGoodWhenPagingAway() throws {
        let first = try insert("one")
        let second = try insert("two")
        let (screen, window) = makeScreen()
        erase(screen)
        screen.previousNote()
        #expect(screen.editor.string == "one")
        #expect(try store.note(id: second.id) == nil)
        #expect(try store.stack().map(\.id) == [first.id])
        #expect(screen.stack.ids == [first.id])
        _ = window
    }

    @Test func aNoteOfOnlyWhitespaceCountsAsEmpty() throws {
        try insert("one")
        let second = try insert("two")
        let (screen, window) = makeScreen()
        erase(screen)
        type(" \n\t", in: screen)
        screen.previousNote()
        #expect(try store.note(id: second.id) == nil)
        _ = window
    }

    @Test func aNoteLeftEmptyIsDeletedByNewNoteAndByLatest() throws {
        let first = try insert("one")
        let second = try insert("two")
        let (screen, window) = makeScreen()
        erase(screen)
        screen.newNote()
        #expect(try store.note(id: second.id) == nil)
        #expect(screen.stack.position == .blank)
        screen.goToLatest()
        #expect(screen.editor.string == "one")
        erase(screen)
        screen.newNote()
        #expect(try store.note(id: first.id) == nil)
        #expect(try store.stack().isEmpty)
        _ = window
    }

    @Test func theEmptiedNoteIsNotWrittenBackAfterItWentAway() throws {
        try insert("one")
        let second = try insert("two")
        let (screen, window) = makeScreen()
        erase(screen)
        screen.previousNote()
        scheduler.advance(by: 1)
        #expect(try store.note(id: second.id) == nil)
        #expect(try store.stack().count == 1)
        _ = window
    }

    @Test func hidingThePanelWithAnEmptyNoteDeletesNothing() throws {
        let note = try insert("one")
        let (screen, window) = makeScreen()
        erase(screen)
        screen.flush()
        screen.willHide()
        #expect(try store.note(id: note.id) != nil)
        #expect(screen.editor.string == "")
        _ = window
    }

    @Test func launchDeletesEmptyNotesAndOpensTheLastOne() throws {
        try insert("one")
        try insert("")
        try insert("  \n")
        let (screen, window) = makeScreen()
        #expect(try store.stack().count == 1)
        #expect(screen.stack.ids.count == 1)
        #expect(screen.editor.string == "one")
        _ = window
    }

    @Test func quittingDeletesEmptyNotesAndRemembersTheLastWhenTheOpenOneWent() throws {
        let first = try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        erase(screen)
        screen.willTerminate()
        #expect(try store.stack().map(\.id) == [first.id])
        #expect(defaults.string(forKey: NoteScreen.openNoteKey) == first.id.uuidString)
        _ = window
    }

    // MARK: The open Note between launches

    @Test func theOpenNoteSurvivesARestart() throws {
        let first = try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.previousNote()
        screen.willHide()
        let (second, secondWindow) = makeScreen()
        #expect(second.stack.position == .note(first.id))
        #expect(second.editor.string == "one")
        _ = (window, secondWindow)
    }

    @Test func aMissingOrBlankOpenNoteFallsBackToTheLastNote() throws {
        try insert("one")
        let last = try insert("two")
        defaults.set(UUID().uuidString, forKey: NoteScreen.openNoteKey)
        let (screen, window) = makeScreen()
        #expect(screen.stack.position == .note(last.id))
        screen.newNote()
        screen.willHide()
        #expect(defaults.string(forKey: NoteScreen.openNoteKey) == nil)
        let (second, secondWindow) = makeScreen()
        #expect(second.stack.position == .note(last.id))
        _ = (window, secondWindow)
    }

    @Test func aGivenStartBeatsTheRememberedNote() throws {
        let first = try insert("one")
        try insert("two")
        let (screen, window) = makeScreen(start: .note(first.id))
        #expect(screen.editor.string == "one")
        let (blank, blankWindow) = makeScreen(start: .blank)
        #expect(blank.stack.position == .blank)
        #expect(blank.editor.string == "")
        _ = (window, blankWindow)
    }

    // MARK: Footer

    @Test func theFooterIsAtRestWhenTheNoteOpens() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        #expect(!screen.footer.isActive)
        #expect(screen.footer.counterText == "Latest · 2 / 2")
        _ = window
    }

    @Test func theFooterLightsOnATurnHoldsAndGoesToRest() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.previousNote()
        #expect(screen.footer.isActive)
        #expect(screen.footer.counterText == "1 / 2")
        scheduler.advance(by: 1.1)
        #expect(screen.footer.isActive)
        scheduler.advance(by: 0.1)
        #expect(!screen.footer.isActive)
        _ = window
    }

    @Test func aNewTurnRestartsTheHold() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.previousNote()
        scheduler.advance(by: 1)
        screen.nextNote()
        scheduler.advance(by: 1)
        #expect(screen.footer.isActive)
        scheduler.advance(by: 0.25)
        #expect(!screen.footer.isActive)
        _ = window
    }

    @Test func hidingThePanelPutsTheFooterAtRest() throws {
        try insert("one")
        try insert("two")
        let (screen, window) = makeScreen()
        screen.previousNote()
        screen.willHide()
        #expect(!screen.footer.isActive)
        _ = window
    }

    @Test func theFooterShowsTheWindowOfDotsOfTheCurrentNote() throws {
        for index in 1...10 { try insert("note \(index)") }
        let (screen, window) = makeScreen()
        screen.previousNote()
        #expect(screen.footer.dots.count == 7)
        #expect(screen.footer.dots.first(where: { $0.kind == .current })?.key == screen.stack.position.noteID?.uuidString)
        _ = window
    }

    @Test func theFooterTakesNoClicksButItsAreaMovesThePanel() throws {
        try insert("one")
        let (screen, window) = makeScreen()
        window.layoutIfNeeded()
        let area = screen.footer.dragArea
        let inWindow = screen.footer.convert(NSPoint(x: area.midX, y: area.midY), to: nil)
        #expect(screen.footer.hitTest(NSPoint(x: area.midX, y: area.midY)) == nil)
        #expect(screen.isDragZone(atWindowPoint: inWindow))
        _ = window
    }

    // MARK: Undo

    @Test func theUndoHistoryOfALeftBlankIsDropped() throws {
        try insert("one")
        let (screen, window) = makeScreen()
        screen.newNote()
        type("x", in: screen)
        erase(screen)
        screen.previousNote()
        screen.nextNote()
        #expect(screen.editor.undoManager?.canUndo == false)
        _ = window
    }
}
