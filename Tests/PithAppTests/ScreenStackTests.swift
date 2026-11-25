import AppKit
import Testing
@testable import PithApp

@MainActor
struct ScreenStackTests {
    final class FakeScreen: PanelScreen {
        let name: String
        let view = NSView()
        var preferredFirstResponder: NSResponder? { nil }
        /// What Esc does on this screen: handle it (and maybe remove the screen) or leave it to the Panel.
        var cancelHandled = false
        var log: [String] = []
        weak var stack: ScreenStack?

        init(_ name: String) { self.name = name }

        func handleCancel() -> Bool {
            log.append("cancel")
            if cancelHandled { stack?.pop(self) }
            return cancelHandled
        }

        func willHide() { log.append("willHide") }
        func willCover() { log.append("willCover") }
    }

    let note = FakeScreen("note")
    let search = FakeScreen("search")
    let trash = FakeScreen("trash")
    let stack: ScreenStack

    init() {
        stack = ScreenStack(root: note)
        search.stack = stack
        trash.stack = stack
    }

    static func name(_ screen: PanelScreen) -> String { (screen as? FakeScreen)?.name ?? "?" }

    @Test func startsOnTheRoot() {
        #expect(stack.top === note)
        #expect(stack.screens.count == 1)
    }

    @Test func escGoesToTheTopScreenOnly() {
        stack.push(search)
        search.cancelHandled = true
        #expect(stack.cancel())
        #expect(search.log == ["cancel"])
        #expect(note.log == ["willCover"])
    }

    @Test func aScreenThatHandlesEscRemovesItselfAndTheNoteIsOnTop() {
        stack.push(search)
        search.cancelHandled = true
        _ = stack.cancel()
        #expect(stack.top === note)
    }

    @Test func escOnTheNoteIsNotHandledSoThePanelHides() {
        #expect(!stack.cancel())
        #expect(note.log == ["cancel"])
    }

    @Test func escOnAScreenThatDeclinesIsNotHandledAndTheScreenStays() {
        stack.push(search)
        #expect(!stack.cancel())
        #expect(stack.top === search)
    }

    @Test func hidingRemovesEverythingAboveTheNoteAndTellsTheTopScreen() {
        stack.push(search)
        stack.push(trash)
        stack.hide()
        #expect(trash.log == ["willHide"])
        #expect(search.log == ["willCover"])
        #expect(stack.top === note)
        #expect(stack.screens.count == 1)
    }

    @Test func hidingOnTheNoteTellsTheNote() {
        stack.hide()
        #expect(note.log == ["willHide"])
    }

    @Test func pushingCoversThePreviousTopScreen() {
        stack.push(search)
        stack.push(trash)
        #expect(note.log == ["willCover"])
        #expect(search.log == ["willCover"])
        #expect(stack.top === trash)
    }

    @Test func changeIsReportedWithTheOldAndTheNewTopScreen() {
        var changes: [String] = []
        stack.onChange = { old, new in changes.append("\(Self.name(old))>\(Self.name(new))") }
        stack.push(search)
        stack.pop(search)
        stack.push(search)
        stack.push(trash)
        stack.hide()
        #expect(changes == ["note>search", "search>note", "note>search", "search>trash", "trash>note"])
    }

    @Test func noChangeIsReportedWhenTheTopStaysTheSame() {
        var changes = 0
        stack.onChange = { _, _ in changes += 1 }
        stack.hide()
        stack.pop(search)
        stack.pop(note)
        #expect(changes == 0)
    }

    @Test func theNoteCannotBePopped() {
        stack.pop(note)
        #expect(stack.top === note)
    }

    @Test func poppingAScreenBelowTheTopKeepsTheTop() {
        stack.push(search)
        stack.push(trash)
        stack.pop(search)
        #expect(stack.screens.map(Self.name) == ["note", "trash"])
        #expect(stack.top === trash)
    }

    @Test func theNextShowOpensOnTheNote() {
        stack.push(search)
        stack.hide()
        #expect(stack.top === note)
    }
}
