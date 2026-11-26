import AppKit
import Foundation
import Testing
@testable import PithApp
@testable import PithNotes

/// The Note screen, the Panel's stack and the Search controller together, on a `.memory` database.
@MainActor
final class SearchWorld {
    let clock = TestClock()
    let scheduler = ManualScheduler()
    let alerts = AlertSpy()
    let store: NoteStore
    let textSize = TextSizeModel(defaults: UserDefaults(suiteName: "pith-tests-" + UUID().uuidString)!)
    var beeps = 0
    var blocked = false

    private(set) var note: NoteScreen!
    private(set) var stack: ScreenStack!
    private(set) var controller: SearchController!
    private var window: NSWindow!
    private var content: PanelContentView!

    init() throws {
        let clock = clock
        store = try NoteStore.open(at: .memory, now: { clock.date }).store
    }

    @discardableResult
    func insert(_ text: String, selection: NoteSelection = NoteSelection(location: 0, length: 0), scroll: Double = 0) throws -> Note {
        clock.advance(60)
        return try store.insert(text: text, selection: selection, scrollOffset: scroll)
    }

    func edit(_ note: Note, to text: String) throws {
        clock.advance(60)
        try store.updateText(id: note.id, text: text)
    }

    /// Opens the app's screens over what the store holds now.
    func launch() {
        let store = store
        note = NoteScreen(openStore: { (store, nil) }, scheduler: scheduler, alerts: alerts, textSize: textSize)
        content = PanelContentView()
        content.show(note)
        stack = ScreenStack(root: note)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = content
        stack.onChange = { [content, window] _, new in
            content?.show(new)
            window?.makeFirstResponder(new.preferredFirstResponder)
        }
        controller = SearchController(stack: stack, note: note)
        controller.beep = { [unowned self] in beeps += 1 }
        controller.isBlocked = { [unowned self] in blocked }
        let clock = clock
        controller.now = { clock.date }
        controller.locale = Locale(identifier: "en_GB")
        note.load()
        window.makeFirstResponder(note.preferredFirstResponder)
    }

    /// Lays the window out, as the screen does once it is shown.
    func layOut() { window.layoutIfNeeded() }

    var search: SearchScreen? { stack.top as? SearchScreen }

    func openSearch() throws -> SearchScreen {
        controller.find(nil)
        return try #require(search)
    }

    /// Titles of the rows, top first.
    func titles(_ screen: SearchScreen) -> [String] {
        screen.results.indices.map { screen.display(at: $0).content.title }
    }

    func type(_ text: String) {
        note.editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

@MainActor
struct SearchScreenTests {
    let world: SearchWorld

    init() throws { world = try SearchWorld() }

    // MARK: List

    @Test func anEmptyQueryListsEveryNoteByTheLastEdit() throws {
        let first = try world.insert("First\nbody")
        try world.insert("Second")
        try world.insert("Third")
        try world.edit(first, to: "First, edited\nbody")
        world.launch()
        let screen = try world.openSearch()
        #expect(world.titles(screen) == ["First, edited", "Third", "Second"])
        #expect(screen.display(at: 0).content.detail == "body")
        #expect(screen.trailingText == "esc")
    }

    @Test func aNoteEditedJustBeforeFindIsOnTop() throws {
        let older = try world.insert("Older")
        try world.insert("Newer")
        world.launch()
        world.note.open(id: older.id)
        world.clock.advance(60)
        world.type(" and edited")
        let screen = try world.openSearch()
        #expect(world.titles(screen) == ["and editedOlder", "Newer"])
    }

    @Test func theTextJustTypedIsSearchable() throws {
        try world.insert("Note")
        world.launch()
        world.type(" zebra")
        let screen = try world.openSearch()
        screen.setQuery("zebra")
        #expect(screen.results.count == 1)
    }

    @Test func aQueryNarrowsTheListAndCountsIt() throws {
        try world.insert("Sales call notes\nthe EMEA region wants the export")
        try world.insert("SQL\ngroup by region")
        try world.insert("Groceries\nmilk")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("region")
        #expect(world.titles(screen) == ["SQL", "Sales call notes"])
        #expect(screen.trailingText == "2 notes · esc")
        screen.setQuery("milk")
        #expect(world.titles(screen) == ["Groceries"])
        #expect(screen.trailingText == "1 note · esc")
    }

    @Test func aMatchBelowTheTitleShowsAsAHighlightedSnippet() throws {
        try world.insert("SQL\norders\ngroup by region")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("region")
        let content = screen.display(at: 0).content
        #expect(content.detail == "group by region")
        #expect(content.detailHits == [9..<15])
    }

    @Test func aQueryWithNoMatchShowsTheMessageWithTheQueryAsTyped() throws {
        try world.insert("Groceries")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("Invoice")
        #expect(screen.results.isEmpty)
        #expect(screen.emptyMessage?.title == "No notes match “Invoice”")
        #expect(screen.emptyMessage?.detail == "Search looks through the text of every note")
        #expect(screen.trailingText == "esc")
    }

    @Test func anEmptyStackSaysThereAreNoNotesYet() throws {
        world.launch()
        let screen = try world.openSearch()
        #expect(screen.emptyMessage?.title == "No notes yet")
        #expect(screen.emptyMessage?.detail == "Notes you write show up here")
        screen.setQuery("x")
        #expect(screen.emptyMessage?.title == "No notes match “x”")
    }

    @Test func theTimeOfARowFollowsTheLastEdit() throws {
        try world.insert("Today")
        world.launch()
        let screen = try world.openSearch()
        #expect(!screen.display(at: 0).time.isEmpty)
        #expect(screen.display(at: 0).accessibilityLabel.hasPrefix("Today, "))
    }

    // MARK: Selection

    @Test func theFirstRowIsSelectedAndStaysSoWhenTheQueryChanges() throws {
        try world.insert("alpha one")
        try world.insert("alpha two")
        try world.insert("beta")
        world.launch()
        let screen = try world.openSearch()
        #expect(screen.selectedRow == 0)
        screen.moveSelection(by: 2)
        #expect(screen.selectedRow == 2)
        screen.setQuery("alpha")
        #expect(screen.selectedRow == 0)
    }

    @Test func theArrowsStopAtTheEnds() throws {
        try world.insert("a")
        try world.insert("b")
        world.launch()
        let screen = try world.openSearch()
        screen.moveSelection(by: -1)
        #expect(screen.selectedRow == 0)
        screen.moveSelection(by: 1)
        screen.moveSelection(by: 1)
        #expect(screen.selectedRow == 1)
    }

    @Test func theKeysOfTheFieldMoveTheSelectionAndOpen() throws {
        try world.insert("a")
        try world.insert("b")
        world.launch()
        let screen = try world.openSearch()
        let handled = screen.control(screen.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        #expect(handled)
        #expect(screen.selectedRow == 1)
        _ = screen.control(screen.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(world.stack.top === world.note)
        #expect(world.note.editor.string == "a")
    }

    // MARK: Opening a Note

    @Test func returnOpensTheNoteWithTheCursorOnTheFirstMatch() throws {
        try world.insert("Sales call\nthe EMEA region wants the export")
        try world.insert("Groceries\nmilk")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("region")
        screen.openSelected()
        #expect(world.stack.top === world.note)
        #expect(world.note.editor.string == "Sales call\nthe EMEA region wants the export")
        let selected = world.note.editor.selectedRange()
        #expect((world.note.editor.string as NSString).substring(with: selected) == "region")
    }

    @Test func returnOpensTheSelectedRowNotTheFirst() throws {
        try world.insert("one region")
        try world.insert("two region")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("region")
        screen.moveSelection(by: 1)
        screen.openSelected()
        #expect(world.note.editor.string == "one region")
    }

    @Test func returnWithAnEmptyQueryRestoresTheSavedCursor() throws {
        try world.insert("older text here", selection: NoteSelection(location: 6, length: 4))
        try world.insert("newer")
        world.launch()
        let screen = try world.openSearch()
        screen.moveSelection(by: 1)
        screen.openSelected()
        #expect(world.note.editor.string == "older text here")
        #expect(world.note.editor.selectedRange() == NSRange(location: 6, length: 4))
    }

    @Test func returnWithAnEmptyListDoesNothing() throws {
        try world.insert("Groceries")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("nothing like this")
        screen.openSelected()
        #expect(world.stack.top === screen)
    }

    @Test func aMatchFarDownIsScrolledIntoView() throws {
        let filler = (1...300).map { "Line number \($0)" }.joined(separator: "\n")
        try world.insert("Long\n" + filler + "\nthe needle is here")
        try world.insert("Short")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("needle")
        screen.openSelected()
        world.layOut()
        let editor = world.note.editor
        let layout = try #require(editor.textLayoutManager)
        let location = try #require(layout.location(layout.documentRange.location, offsetBy: editor.selectedRange().location))
        let fragment = try #require(layout.textLayoutFragment(for: location))
        let top = fragment.layoutFragmentFrame.minY + editor.textContainerOrigin.y
        let visible = world.note.scrollView.contentView.bounds
        #expect(visible.origin.y > 0)
        #expect(top >= visible.minY && top <= visible.maxY)
    }

    // MARK: Leaving

    @Test func escapeReturnsToTheNoteAsItWas() throws {
        try world.insert("Hello world", selection: NoteSelection(location: 2, length: 3))
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("hello")
        #expect(world.stack.cancel())
        #expect(world.stack.top === world.note)
        #expect(world.note.editor.string == "Hello world")
        #expect(world.note.editor.selectedRange() == NSRange(location: 2, length: 3))
    }

    @Test func hidingThePanelClosesSearch() throws {
        try world.insert("Hello")
        world.launch()
        _ = try world.openSearch()
        world.stack.hide()
        #expect(world.stack.top === world.note)
        #expect(world.stack.screens.count == 1)
    }

    @Test func everyOpeningStartsWithAnEmptyQuery() throws {
        try world.insert("Hello")
        world.launch()
        let first = try world.openSearch()
        first.setQuery("hello")
        _ = world.stack.cancel()
        let second = try world.openSearch()
        #expect(second.query == "")
    }

    @Test func findWhileOpenSelectsTheTextOfTheField() throws {
        try world.insert("Hello")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("hello")
        world.controller.find(nil)
        #expect(world.search === screen)
        let editor = try #require(screen.field.currentEditor())
        #expect(editor.selectedRange == NSRange(location: 0, length: 5))
    }

    @Test func findDoesNothingWhileAnAlertIsUp() throws {
        try world.insert("Hello")
        world.launch()
        world.blocked = true
        world.controller.find(nil)
        #expect(world.stack.top === world.note)
    }

    @Test func findWorksWithAnEmptyStack() throws {
        world.launch()
        world.controller.find(nil)
        #expect(world.search != nil)
    }

    // MARK: Find next

    private func selection(_ world: SearchWorld) -> String {
        let editor = world.note.editor
        return (editor.string as NSString).substring(with: editor.selectedRange())
    }

    private func openWithQuery(_ query: String, text: String) throws {
        try world.insert(text)
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery(query)
        _ = world.stack.cancel()
    }

    @Test func findNextWalksTheMatchesAndWrapsAround() throws {
        try openWithQuery("ab", text: "ab 1 ab 2 ab")
        world.note.editor.setSelectedRange(NSRange(location: 0, length: 0))
        world.controller.findNext(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 0, length: 2))
        world.controller.findNext(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 5, length: 2))
        world.controller.findNext(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 10, length: 2))
        world.controller.findNext(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 0, length: 2))
        #expect(world.beeps == 0)
    }

    @Test func findPreviousWalksBackAndWrapsAround() throws {
        try openWithQuery("ab", text: "ab 1 ab 2 ab")
        world.note.editor.setSelectedRange(NSRange(location: 5, length: 2))
        world.controller.findPrevious(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 0, length: 2))
        world.controller.findPrevious(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 10, length: 2))
    }

    @Test func findNextAfterOpeningFromSearchGoesToTheSecondMatch() throws {
        try world.insert("x ab y ab z")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("ab")
        screen.openSelected()
        #expect(world.note.editor.selectedRange() == NSRange(location: 2, length: 2))
        world.controller.findNext(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 7, length: 2))
    }

    @Test func findNextWorksOnTheTextAsEdited() throws {
        try openWithQuery("ab", text: "ab")
        world.note.editor.setSelectedRange(NSRange(location: 2, length: 0))
        world.type(" ab")
        world.note.editor.setSelectedRange(NSRange(location: 0, length: 0))
        world.controller.findNext(nil)
        world.controller.findNext(nil)
        #expect(world.note.editor.selectedRange() == NSRange(location: 3, length: 2))
    }

    @Test func findNextBeepsWithNoQueryYet() throws {
        try world.insert("ab")
        world.launch()
        world.controller.findNext(nil)
        #expect(world.beeps == 1)
    }

    @Test func findNextBeepsWhenTheNoteHasNoMatch() throws {
        try world.insert("other\nab")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("ab")
        _ = world.stack.cancel()
        world.note.editor.string = "nothing"
        world.controller.findNext(nil)
        #expect(world.beeps == 1)
    }

    @Test func theQueryIsRememberedWhenSearchIsLeftByEscapeOrByHiding() throws {
        try world.insert("ab")
        world.launch()
        var screen = try world.openSearch()
        screen.setQuery("ab")
        _ = world.stack.cancel()
        world.controller.findNext(nil)
        #expect(world.beeps == 0)

        screen = try world.openSearch()
        screen.setQuery("")
        screen.setQuery("b")
        world.stack.hide()
        world.note.editor.setSelectedRange(NSRange(location: 0, length: 0))
        world.controller.findNext(nil)
        #expect(selection(world) == "b")
    }

    @Test func anEmptyQueryDoesNotReplaceTheLastOne() throws {
        try world.insert("ab")
        world.launch()
        var screen = try world.openSearch()
        screen.setQuery("ab")
        _ = world.stack.cancel()
        screen = try world.openSearch()
        _ = world.stack.cancel()
        world.controller.findNext(nil)
        #expect(world.beeps == 0)
        #expect(selection(world) == "ab")
    }

    @Test func findNextDoesNothingOnTheSearchScreen() throws {
        try openWithQuery("ab", text: "ab ab")
        let screen = try world.openSearch()
        world.controller.findNext(nil)
        #expect(world.stack.top === screen)
        #expect(world.beeps == 0)
    }

    @Test func theMenuEnablesFindWhereItWorks() throws {
        try world.insert("ab")
        world.launch()
        let find = NSMenuItem(title: "Find", action: #selector(SearchController.find(_:)), keyEquivalent: "f")
        let next = NSMenuItem(title: "Next", action: #selector(SearchController.findNext(_:)), keyEquivalent: "g")
        #expect(world.controller.validateMenuItem(find))
        #expect(world.controller.validateMenuItem(next))
        _ = try world.openSearch()
        #expect(world.controller.validateMenuItem(find))
        #expect(!world.controller.validateMenuItem(next))
        _ = world.stack.cancel()
        world.blocked = true
        #expect(!world.controller.validateMenuItem(find))
        #expect(!world.controller.validateMenuItem(next))
    }
}
