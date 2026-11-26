import AppKit
import Foundation
import PithEditor
import Testing
@testable import PithApp
@testable import PithNotes

@MainActor
final class AlertSpy: StorageAlerts {
    var corruption: [URL] = []
    var openFailures: [(reason: String, canRetry: Bool, onRetry: () -> Void)] = []
    var saveFailures: [String] = []

    func presentCorruptionRecoveryAlert(movedFile: URL) { corruption.append(movedFile) }
    func presentOpenFailureAlert(reason: String, canRetry: Bool, onRetry: @escaping () -> Void) {
        openFailures.append((reason, canRetry, onRetry))
    }
    func presentSaveFailureAlert(reason: String) { saveFailures.append(reason) }
}

/// The editor, the store and the autosaver together, on a `.memory` database and a scheduler moved by hand.
@MainActor
struct NoteScreenTests {
    let clock: TestClock
    let scheduler = ManualScheduler()
    let alerts = AlertSpy()
    let store: NoteStore
    let textSize = TextSizeModel(defaults: UserDefaults(suiteName: "pith-tests-" + UUID().uuidString)!)

    init() throws {
        let clock = TestClock()
        self.clock = clock
        store = try NoteStore.open(at: .memory, now: { clock.date }).store
    }

    /// A screen in a Panel-sized window, loaded.
    private func makeScreen(
        recovery: CorruptionRecovery? = nil, open: (() throws -> (store: NoteStore, recovery: CorruptionRecovery?))? = nil
    ) -> (NoteScreen, NSWindow) {
        let store = store
        let screen = NoteScreen(
            openStore: open ?? { (store, recovery) }, scheduler: scheduler, alerts: alerts, textSize: textSize
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = screen.view
        screen.load()
        return (screen, window)
    }

    @discardableResult
    private func insert(_ text: String, selection: NoteSelection = NoteSelection(location: 0, length: 0), scroll: Double = 0) throws -> Note {
        clock.advance(1)
        return try store.insert(text: text, selection: selection, scrollOffset: scroll)
    }

    private func type(_ text: String, in screen: NoteScreen) {
        screen.editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: Opening

    @Test func opensTheLatestNoteOfTheStack() throws {
        try insert("old")
        try insert("newest")
        let (screen, window) = makeScreen()
        #expect(screen.editor.string == "newest")
        _ = window
    }

    @Test func opensABlankWhenTheStackIsEmpty() {
        let (screen, window) = makeScreen()
        #expect(screen.editor.string == "")
        #expect(screen.editor.isEditable)
        _ = window
    }

    @Test func aNoteLeftEmptyIsGoneAtLaunchAndTheBlankShowsThePlaceholder() throws {
        let empty = try insert("")
        let (screen, window) = makeScreen()
        #expect(try store.note(id: empty.id) == nil)
        #expect(screen.editor.string == "")
        #expect(screen.editor.isShowingPlaceholder)
        #expect(screen.editor.placeholder == "Start typing, or paste with ⌘V")
        _ = window
    }

    @Test func placeholderIsGoneOnceThereIsText() throws {
        try insert("text")
        let (screen, window) = makeScreen()
        #expect(!screen.editor.isShowingPlaceholder)
        _ = window
    }

    @Test func restoresTheSelection() throws {
        try insert("Hello world", selection: NoteSelection(location: 6, length: 5))
        let (screen, window) = makeScreen()
        #expect(screen.editor.selectedRange() == NSRange(location: 6, length: 5))
        _ = window
    }

    @Test func clampsAStoredSelectionToTheLengthOfTheText() throws {
        try insert("Hello", selection: NoteSelection(location: 40, length: 10))
        let (screen, window) = makeScreen()
        #expect(screen.editor.selectedRange() == NSRange(location: 5, length: 0))
        try insert("Hello world", selection: NoteSelection(location: 6, length: 50))
        let (second, secondWindow) = makeScreen()
        #expect(second.editor.selectedRange() == NSRange(location: 6, length: 5))
        _ = (window, secondWindow)
    }

    @Test func restoresTheScrollPosition() throws {
        let text = (1...200).map { "Line number \($0)" }.joined(separator: "\n")
        try insert(text, selection: NoteSelection(location: 0, length: 0), scroll: 600)
        let (screen, window) = makeScreen()
        window.layoutIfNeeded()
        #expect(abs(screen.scrollView.contentView.bounds.origin.y - 600) < 1)
    }

    @Test func aScrollPastTheEndIsClamped() throws {
        let text = (1...200).map { "Line number \($0)" }.joined(separator: "\n")
        try insert(text, scroll: 1_000_000)
        let (screen, window) = makeScreen()
        window.layoutIfNeeded()
        let documentHeight = screen.editor.frame.height
        let visibleHeight = screen.scrollView.contentView.bounds.height
        #expect(screen.scrollView.contentView.bounds.origin.y <= documentHeight + screen.scrollView.contentInsets.bottom - visibleHeight + 1)
        #expect(screen.scrollView.contentView.bounds.origin.y > 0)
    }

    // MARK: Saving

    @Test func theDebounceWritesTheTextButNotTheViewState() throws {
        let note = try insert("abc")
        let (screen, window) = makeScreen()
        screen.editor.setSelectedRange(NSRange(location: 3, length: 0))
        type("d", in: screen)
        scheduler.advance(by: 0.5)
        let saved = try #require(try store.note(id: note.id))
        #expect(saved.text == "abcd")
        #expect(saved.selection == NoteSelection(location: 0, length: 0))
        _ = window
    }

    @Test func nothingIsWrittenBeforeThePause() throws {
        let note = try insert("abc")
        let (screen, window) = makeScreen()
        screen.editor.setSelectedRange(NSRange(location: 3, length: 0))
        type("d", in: screen)
        scheduler.advance(by: 0.4)
        #expect(try store.note(id: note.id)?.text == "abc")
        _ = window
    }

    @Test func flushWritesTheTextAndTheViewStateAtOnce() throws {
        let note = try insert("abc")
        let (screen, window) = makeScreen()
        screen.editor.setSelectedRange(NSRange(location: 3, length: 0))
        type("d", in: screen)
        screen.editor.setSelectedRange(NSRange(location: 1, length: 2))
        screen.flush()
        let saved = try #require(try store.note(id: note.id))
        #expect(saved.text == "abcd")
        #expect(saved.selection == NoteSelection(location: 1, length: 2))
        _ = window
    }

    @Test func aMovedCursorAloneIsWrittenByFlush() throws {
        let note = try insert("abcdef")
        let (screen, window) = makeScreen()
        screen.editor.setSelectedRange(NSRange(location: 4, length: 1))
        screen.flush()
        #expect(try store.note(id: note.id)?.selection == NoteSelection(location: 4, length: 1))
        _ = window
    }

    @Test func theScrollPositionIsWrittenByFlush() throws {
        let text = (1...200).map { "Line number \($0)" }.joined(separator: "\n")
        let note = try insert(text)
        let (screen, window) = makeScreen()
        window.layoutIfNeeded()
        screen.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 420))
        screen.scrollView.reflectScrolledClipView(screen.scrollView.contentView)
        screen.flush()
        #expect(abs((try store.note(id: note.id)?.scrollOffset ?? 0) - 420) < 1)
    }

    @Test func aRestartShowsTheSameNote() throws {
        let (first, firstWindow) = makeScreen()
        type("Hello", in: first)
        first.editor.setSelectedRange(NSRange(location: 2, length: 1))
        first.flush()
        let (second, secondWindow) = makeScreen()
        #expect(second.editor.string == "Hello")
        #expect(second.editor.selectedRange() == NSRange(location: 2, length: 1))
        _ = (firstWindow, secondWindow)
    }

    @Test func aBlankBecomesOneNoteOnTheFirstText() throws {
        let (screen, window) = makeScreen()
        type("a", in: screen)
        type("b", in: screen)
        scheduler.advance(by: 0.5)
        type("c", in: screen)
        screen.flush()
        let stack = try store.stack()
        #expect(stack.count == 1)
        #expect(try store.note(id: stack[0].id)?.text == "abc")
        _ = window
    }

    @Test func aBlankWithNoTextStaysOutOfTheStore() throws {
        let (screen, window) = makeScreen()
        screen.flush()
        #expect(try store.stack().isEmpty)
        _ = window
    }

    @Test func emptyingANoteKeepsItUntilTheNextLaunch() throws {
        let note = try insert("x")
        let (screen, window) = makeScreen()
        screen.editor.setSelectedRange(NSRange(location: 0, length: 1))
        screen.editor.insertText("", replacementRange: NSRange(location: 0, length: 1))
        screen.flush()
        #expect(try store.note(id: note.id)?.text == "")
        let (second, secondWindow) = makeScreen()
        #expect(try store.note(id: note.id) == nil)
        #expect(second.editor.string == "")
        #expect(second.editor.isShowingPlaceholder)
        _ = (window, secondWindow)
    }

    @Test func replacingTheTextIsSavedLikeTyping() throws {
        let note = try insert("old")
        let (screen, window) = makeScreen()
        screen.replaceText("generated")
        scheduler.advance(by: 0.5)
        #expect(try store.note(id: note.id)?.text == "generated")
        _ = window
    }

    // MARK: Undo

    @Test func undoRevertsTheEditsOfThisNote() throws {
        try insert("abc")
        let (screen, window) = makeScreen()
        screen.editor.setSelectedRange(NSRange(location: 3, length: 0))
        type("d", in: screen)
        let undo = try #require(screen.editor.undoManager)
        undo.undo()
        #expect(screen.editor.string == "abc")
        undo.redo()
        #expect(screen.editor.string == "abcd")
        _ = window
    }

    @Test func openingANoteStartsWithoutHistory() throws {
        try insert("abc")
        let (screen, window) = makeScreen()
        #expect(screen.editor.undoManager?.canUndo == false)
        _ = window
    }

    @Test func aBlankKeepsItsHistoryWhenItBecomesANote() throws {
        let (screen, window) = makeScreen()
        let before = try #require(screen.editor.undoManager)
        type("a", in: screen)
        scheduler.advance(by: 0.5)
        #expect(try store.stack().count == 1)
        // The same manager, so the history of the typing before the first save is still there.
        #expect(screen.editor.undoManager === before)
        #expect(screen.editor.undoManager?.canUndo == true)
        _ = window
    }

    // MARK: Storage alerts

    @Test func aCorruptedFileShowsTheRecoveryAlert() {
        let moved = URL(fileURLWithPath: "/tmp/notes-corrupt.sqlite")
        let (_, window) = makeScreen(recovery: CorruptionRecovery(movedFile: moved))
        #expect(alerts.corruption == [moved])
        _ = window
    }

    @Test func aNoteThatDoesNotOpenShowsTheAlertAndLocksTheEditor() {
        struct Boom: LocalizedError { var errorDescription: String? { "Disk is gone." } }
        let (screen, window) = makeScreen(open: { throw Boom() })
        #expect(alerts.openFailures.count == 1)
        #expect(alerts.openFailures[0].reason == "Disk is gone.")
        #expect(alerts.openFailures[0].canRetry)
        #expect(!screen.editor.isEditable)
        _ = window
    }

    @Test func typingIsNotPossibleWhileTheOpenFailureAlertIsUp() {
        let (screen, window) = makeScreen(open: { throw NoteStoreError.sqlite(code: 5, message: "database is locked") })
        type("lost", in: screen)
        #expect(screen.editor.string == "")
        _ = window
    }

    @Test func notesFromANewerPithOfferNoRetry() {
        let (screen, window) = makeScreen(open: { throw NoteStoreError.newerSchema(found: 9, supported: 1) })
        #expect(alerts.openFailures.count == 1)
        #expect(!alerts.openFailures[0].canRetry)
        #expect(!screen.editor.isEditable)
        _ = window
    }

    @Test func tryAgainOpensTheNoteAndUnlocksTheEditor() throws {
        try insert("my note")
        let store = store
        var attempts = 0
        let (screen, window) = makeScreen(open: {
            attempts += 1
            if attempts == 1 { throw NoteStoreError.sqlite(code: 5, message: "database is locked") }
            return (store, nil)
        })
        #expect(!screen.editor.isEditable)
        alerts.openFailures[0].onRetry()
        #expect(attempts == 2)
        #expect(screen.editor.isEditable)
        #expect(screen.editor.string == "my note")
        screen.editor.setSelectedRange(NSRange(location: 7, length: 0))
        type("!", in: screen)
        scheduler.advance(by: 0.5)
        #expect(try store.note(id: store.stack()[0].id)?.text == "my note!")
        _ = window
    }

    @Test func aFailingRetryShowsTheAlertAgain() {
        let (screen, window) = makeScreen(open: { throw NoteStoreError.sqlite(code: 5, message: "database is locked") })
        alerts.openFailures[0].onRetry()
        #expect(alerts.openFailures.count == 2)
        #expect(!screen.editor.isEditable)
        _ = window
    }

    @Test func aFailedSaveShowsTheAlertOnceAndKeepsTheEditorOpen() throws {
        try insert("abc")
        let (screen, window) = makeScreen()
        try store.execute("DROP TABLE notes")
        screen.editor.setSelectedRange(NSRange(location: 3, length: 0))
        type("d", in: screen)
        scheduler.advance(by: 0.5)
        #expect(alerts.saveFailures.count == 1)
        #expect(alerts.saveFailures[0].hasSuffix("."))
        type("e", in: screen)
        scheduler.advance(by: 0.5)
        screen.flush()
        #expect(alerts.saveFailures.count == 1)
        #expect(screen.editor.isEditable)
        #expect(screen.editor.string == "abcde")
        _ = window
    }

    @Test func aFailedFlushIsReportedToTheCaller() throws {
        try insert("abc")
        let (screen, window) = makeScreen()
        try store.execute("DROP TABLE notes")
        type("d", in: screen)
        #expect(!screen.flush())
        _ = window
    }

    // MARK: Text size

    @Test func theTextSizeOfTheModelStylesTheNote() async throws {
        try insert("some text")
        let (screen, window) = makeScreen()
        #expect(screen.editor.theme.textSize == 14)
        textSize.bigger()
        for _ in 0..<50 where screen.editor.theme.textSize == 14 { await Task.yield() }
        #expect(screen.editor.theme.textSize == 15)
        #expect(screen.editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == .systemFont(ofSize: 15))
        _ = window
    }

    @Test func aStartingSizeAppliesRightAway() throws {
        textSize.reset()
        for _ in 0..<3 { textSize.bigger() }
        try insert("some text")
        let (screen, window) = makeScreen()
        #expect(screen.editor.theme.textSize == 17)
        _ = window
    }

    @Test func theSizePillShowsTheSizeAndHoldsForASecond() {
        let (screen, window) = makeScreen()
        #expect(screen.hud.isHidden)
        screen.showSizeHUD(size: 17)
        #expect(!screen.hud.isHidden)
        #expect(screen.hud.size == 17)
        scheduler.advance(by: 0.9)
        #expect(screen.hud.alphaValue == 1)
        _ = window
    }

    @Test func hidingThePanelDismissesThePill() {
        let (screen, window) = makeScreen()
        screen.showSizeHUD(size: 17)
        screen.willHide()
        #expect(screen.hud.isHidden)
        _ = window
    }

    // MARK: Screen

    @Test func escIsNotHandledSoThePanelHides() {
        let (screen, window) = makeScreen()
        #expect(!screen.handleCancel())
        _ = window
    }

    @Test func theEditorTakesTheFocus() {
        let (screen, window) = makeScreen()
        #expect(screen.preferredFirstResponder === screen.editor)
        _ = window
    }
}
