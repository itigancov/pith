import AppKit
import Testing
@testable import PithApp

/// A spell checker with a fixed answer for one word.
final class FakeSpellChecker: SpellChecking {
    var misspelled: NSRange?
    var suggestions: [String] = []
    var ignored: [String] = []

    func misspelledRange(at index: Int, in text: String) -> NSRange? {
        guard let misspelled, NSLocationInRange(index, misspelled) else { return nil }
        return misspelled
    }

    func guesses(for range: NSRange, in text: String) -> [String] { suggestions }
    func ignore(word: String) { ignored.append(word) }
}

@MainActor
struct ContextMenuTests {
    private let text = "Credit the beta tetsers today"
    private var word: NSRange { (text as NSString).range(of: "tetsers") }

    private func harness(spelling: FakeSpellChecker? = nil) throws -> (MenuHarness, FakeSpellChecker) {
        let harness = try MenuHarness(notes: [text])
        let checker = spelling ?? FakeSpellChecker()
        harness.note.spellChecker = checker
        return (harness, checker)
    }

    private func rightClick(_ harness: MenuHarness, at index: Int) throws -> NSMenu {
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        return try #require(harness.note.textView(harness.note.editor, menu: NSMenu(), for: event, at: index))
    }

    @Test func withoutAMistakeTheMenuHasTheEightNoteCommandsOnly() throws {
        let (harness, _) = try harness()
        let menu = try rightClick(harness, at: 3)
        #expect(harness.layout(of: menu) ==
            ["Cut", "Copy", "Paste", "|", "New Note", "Go to Latest Note", "Search Notes", "|", "Move to Trash", "Show Trash"])
        for system in ["Look Up", "Translate", "Services", "Font", "Spelling and Grammar", "Substitutions", "Speech", "Share", "AutoFill"] {
            #expect(!menu.items.contains { $0.title.hasPrefix(system) }, "\(system)")
        }
    }

    @Test func theMenuShowsTheCurrentShortcuts() throws {
        let (harness, _) = try harness()
        #expect(harness.shortcuts.assign(Shortcut(keyCode: 11, modifiers: [.command, .shift]), to: .newNote) == nil)
        let menu = try rightClick(harness, at: 3)
        let item = harness.item("New Note", in: menu)
        #expect(item?.keyEquivalent == "b")
        #expect(item?.keyEquivalentModifierMask == [.command, .shift])
        #expect(harness.item("Move to Trash", in: menu)?.keyEquivalent == "\u{8}")
        #expect(harness.item("Search Notes", in: menu)?.identifier?.rawValue == "searchNotes")
    }

    @Test func theCommandsRunLikeTheMainMenusOnes() throws {
        let (harness, _) = try harness()
        let menu = try rightClick(harness, at: 3)
        harness.choose(harness.item("New Note", in: menu))
        #expect(harness.note.editor.string == "")
        harness.choose(harness.item("Show Trash", in: menu))
        #expect(harness.panel.screens.top is TrashScreen)
    }

    // MARK: The caret

    @Test func aRightClickOutsideTheSelectionPutsTheCaretThere() throws {
        let (harness, _) = try harness()
        harness.note.editor.setSelectedRange(NSRange(location: 0, length: 6))
        _ = try rightClick(harness, at: 12)
        #expect(harness.note.editor.selectedRange() == NSRange(location: 12, length: 0))
    }

    @Test func aRightClickInsideTheSelectionKeepsIt() throws {
        let (harness, _) = try harness()
        harness.note.editor.setSelectedRange(NSRange(location: 0, length: 6))
        _ = try rightClick(harness, at: 3)
        #expect(harness.note.editor.selectedRange() == NSRange(location: 0, length: 6))
    }

    // MARK: Spelling

    @Test func aMisspelledWordGetsItsCorrectionsAndIgnoreSpellingOnTop() throws {
        let checker = FakeSpellChecker()
        checker.misspelled = word
        checker.suggestions = ["testers", "teasers"]
        let (harness, _) = try harness(spelling: checker)
        let menu = try rightClick(harness, at: word.location + 2)
        #expect(harness.layout(of: menu).prefix(5) == ["testers", "teasers", "Ignore Spelling", "|", "Cut"])
        #expect(harness.layout(of: menu).count == 14)
    }

    @Test func withoutGuessesTheMenuSaysSoInADisabledItem() throws {
        let checker = FakeSpellChecker()
        checker.misspelled = word
        let (harness, _) = try harness(spelling: checker)
        let menu = try rightClick(harness, at: word.location)
        #expect(harness.layout(of: menu).prefix(4) == ["No Guesses Found", "Ignore Spelling", "|", "Cut"])
        let none = harness.item("No Guesses Found", in: menu)
        #expect(none?.action == nil)
        #expect(harness.item("Ignore Spelling", in: menu)?.action != nil)
    }

    @Test func aWordSpelledRightOrAClickElsewhereHasNoSpellingItems() throws {
        let checker = FakeSpellChecker()
        checker.misspelled = word
        checker.suggestions = ["testers"]
        let (harness, _) = try harness(spelling: checker)
        let menu = try rightClick(harness, at: 2)
        #expect(harness.layout(of: menu).first == "Cut")
    }

    @Test func aChosenCorrectionReplacesTheWordAndOneUndoBringsItBack() throws {
        let checker = FakeSpellChecker()
        checker.misspelled = word
        checker.suggestions = ["testers"]
        let (harness, _) = try harness(spelling: checker)
        let menu = try rightClick(harness, at: word.location + 1)
        harness.choose(harness.item("testers", in: menu))
        #expect(harness.note.editor.string == "Credit the beta testers today")
        harness.note.editor.undoManager?.undo()
        #expect(harness.note.editor.string == text)
    }

    @Test func ignoreSpellingTellsTheCheckerTheWord() throws {
        let checker = FakeSpellChecker()
        checker.misspelled = word
        let (harness, _) = try harness(spelling: checker)
        let menu = try rightClick(harness, at: word.location + 1)
        harness.choose(harness.item("Ignore Spelling", in: menu))
        #expect(checker.ignored == ["tetsers"])
        #expect(harness.note.editor.string == text)
    }
}
