import AppKit
import Foundation
import Testing
@testable import PithApp
@testable import PithNotes

/// Selecting several rows of Search, ⌘⌫ on them and Undo: the real screens over a `.memory` database and a scheduler moved by hand.
@MainActor
struct SearchSelectionTests {
    let world: SearchWorld

    init() throws { world = try SearchWorld() }

    /// Five Notes; the list shows them newest first: e, d, c, b, a.
    @discardableResult
    private func fiveNotes() throws -> [Note] {
        let notes = try ["a", "b", "c", "d", "e"].map { try world.insert("note \($0)") }
        world.launch()
        return notes
    }

    private func key(_ selector: Selector, on screen: SearchScreen) -> Bool {
        screen.control(screen.field, textView: NSTextView(), doCommandBy: selector)
    }

    private func rows(_ screen: SearchScreen) -> [Int] { Array(screen.selectedRows) }

    // MARK: Keys

    @Test func shiftDownAndUpMoveTheEndOfTheSelectionFromTheAnchor() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.moveSelection(by: 1)
        #expect(key(#selector(NSResponder.moveDownAndModifySelection(_:)), on: screen))
        _ = key(#selector(NSResponder.moveDownAndModifySelection(_:)), on: screen)
        #expect(rows(screen) == [1, 2, 3])
        #expect(screen.selectedRow == 3)
        _ = key(#selector(NSResponder.moveUpAndModifySelection(_:)), on: screen)
        #expect(rows(screen) == [1, 2])
        _ = key(#selector(NSResponder.moveUpAndModifySelection(_:)), on: screen)
        _ = key(#selector(NSResponder.moveUpAndModifySelection(_:)), on: screen)
        #expect(rows(screen) == [0, 1])
        _ = key(#selector(NSResponder.moveUpAndModifySelection(_:)), on: screen)
        #expect(rows(screen) == [0, 1])
    }

    @Test func shiftDownStopsAtTheLastRow() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        for _ in 0..<10 { _ = key(#selector(NSResponder.moveDownAndModifySelection(_:)), on: screen) }
        #expect(rows(screen) == [0, 1, 2, 3, 4])
    }

    @Test func commandASelectsEveryRow() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        #expect(key(#selector(NSResponder.selectAll(_:)), on: screen))
        #expect(rows(screen) == [0, 1, 2, 3, 4])
        #expect(screen.selectedRow == 4)
    }

    @Test func anArrowWithoutShiftLeavesOneRowAStepFromTheActiveOne() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.selectRows(from: 1, to: 3)
        _ = key(#selector(NSResponder.moveDown(_:)), on: screen)
        #expect(rows(screen) == [4])
        screen.selectRows(from: 1, to: 3)
        _ = key(#selector(NSResponder.moveUp(_:)), on: screen)
        #expect(rows(screen) == [2])
    }

    @Test func returnOpensTheActiveRow() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.selectRows(from: 1, to: 3)
        _ = key(#selector(NSResponder.insertNewline(_:)), on: screen)
        #expect(world.stack.top === world.note)
        #expect(world.note.editor.string == "note b")
    }

    @Test func theFirstEscapeLeavesTheActiveRowAndTheSecondClosesSearch() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.selectRows(from: 1, to: 3)
        #expect(world.stack.cancel())
        #expect(world.stack.top === screen)
        #expect(rows(screen) == [3])
        _ = key(#selector(NSResponder.cancelOperation(_:)), on: screen)
        #expect(world.stack.top === world.note)
    }

    @Test func aNewQuerySelectsTheFirstRowAgain() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.selectAllRows()
        screen.setQuery("note")
        #expect(rows(screen) == [0])
        #expect(!screen.isSelectionPillShown)
    }

    // MARK: Mouse

    @Test func clicksSelectExtendAndToggleRows() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 1)
        #expect(rows(screen) == [1])
        screen.click(row: 3, modifiers: .shift)
        #expect(rows(screen) == [1, 2, 3])
        screen.click(row: 0, modifiers: .command)
        #expect(rows(screen) == [0, 1, 2, 3])
        screen.click(row: 2, modifiers: .command)
        #expect(rows(screen) == [0, 1, 3])
        // Shift goes on from the row clicked with ⌘.
        screen.click(row: 4, modifiers: .shift)
        #expect(rows(screen) == [2, 3, 4])
        screen.click(row: 0)
        #expect(rows(screen) == [0])
    }

    @Test func aDoubleClickOpensTheRow() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 2, clickCount: 2)
        #expect(world.stack.top === world.note)
        #expect(world.note.editor.string == "note c")
    }

    @Test func clickingKeepsTheCursorInTheField() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        #expect(!screen.table.acceptsFirstResponder)
        screen.click(row: 2)
        #expect(screen.field.currentEditor() != nil)
    }

    // MARK: Pill

    @Test func thePillShowsFromTwoRowsOn() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        #expect(!screen.isSelectionPillShown)
        screen.selectRows(from: 0, to: 2)
        #expect(screen.isSelectionPillShown)
        #expect(screen.selectionPillText == "3 selected")
        screen.click(row: 1)
        #expect(!screen.isSelectionPillShown)
    }

    // MARK: ⌘⌫

    @Test func commandDeleteSendsTheSelectedNotesToTheTrashAndSearchStaysOpen() throws {
        let notes = try fiveNotes()
        let screen = try world.openSearch()
        screen.selectRows(from: 1, to: 2)
        screen.moveSelectionToTrash()
        #expect(world.stack.top === screen)
        #expect(world.titles(screen) == ["note e", "note b", "note a"])
        #expect(Set(try world.store.trash().map(\.id)) == [notes[3].id, notes[2].id])
        // The row that took the place of the lowest one gone.
        #expect(rows(screen) == [1])
        #expect(screen.toastText == "2 notes moved to Trash")
        #expect(!screen.isSelectionPillShown)
        #expect(world.note.stack.ids == [notes[0].id, notes[1].id, notes[4].id])
    }

    @Test func commandDeleteOnOneRowTakesThatNote() throws {
        let notes = try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 4)
        screen.moveSelectionToTrash()
        #expect(world.titles(screen) == ["note e", "note d", "note c", "note b"])
        #expect(rows(screen) == [3])
        #expect(screen.toastText == "Note moved to Trash")
        #expect(try world.store.trash().map(\.id) == [notes[0].id])
    }

    @Test func commandDeleteKeepsTheQuery() throws {
        try world.insert("alpha one")
        try world.insert("alpha two")
        try world.insert("beta")
        world.launch()
        let screen = try world.openSearch()
        screen.setQuery("alpha")
        screen.selectAllRows()
        screen.moveSelectionToTrash()
        #expect(screen.query == "alpha")
        #expect(screen.results.isEmpty)
        #expect(screen.emptyMessage?.title == "No notes match “alpha”")
    }

    @Test func deletingEveryNoteShowsTheEmptyState() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.selectAllRows()
        screen.moveSelectionToTrash()
        #expect(screen.emptyMessage?.title == "No notes yet")
        #expect(screen.selectedRows.isEmpty)
    }

    @Test func theMenuItemWorksWithARowSelectedInSearch() throws {
        try fiveNotes()
        let trash = TrashController(stack: world.stack, note: world.note)
        let item = NSMenuItem(title: "Move to Trash", action: #selector(TrashController.moveToTrash(_:)), keyEquivalent: "")
        let screen = try world.openSearch()
        #expect(trash.validateMenuItem(item))
        trash.moveToTrash(nil)
        #expect(world.stack.top === screen)
        #expect(try world.store.trashCount() == 1)
    }

    @Test func theMenuItemIsOffWithNoRowSelected() throws {
        try world.insert("only")
        world.launch()
        let trash = TrashController(stack: world.stack, note: world.note)
        let item = NSMenuItem(title: "Move to Trash", action: #selector(TrashController.moveToTrash(_:)), keyEquivalent: "")
        let screen = try world.openSearch()
        screen.click(row: 0, modifiers: .command)
        #expect(screen.selectedRows.isEmpty)
        #expect(!trash.validateMenuItem(item))
    }

    @Test func theOpenNoteThatWasDeletedGivesWayToTheNextOneWhenSearchCloses() throws {
        let notes = try fiveNotes()
        // The Note open is the last one, e; the list is e, d, c, b, a.
        let screen = try world.openSearch()
        screen.click(row: 0)
        screen.moveSelectionToTrash()
        _ = world.stack.cancel()
        #expect(world.stack.top === world.note)
        #expect(world.note.stack.position == .note(notes[3].id))
        #expect(world.note.editor.string == "note d")
    }

    // MARK: Undo

    @Test func undoBringsEveryNoteBackSelectedAndInPlace() throws {
        let notes = try fiveNotes()
        let screen = try world.openSearch()
        let before = try notes.map { try #require(try world.store.note(id: $0.id)).updatedAt }
        screen.selectRows(from: 1, to: 2)
        screen.moveSelectionToTrash()
        world.clock.advance(1)
        #expect(screen.undoMoveToTrash())
        #expect(world.titles(screen) == ["note e", "note d", "note c", "note b", "note a"])
        #expect(rows(screen) == [1, 2])
        #expect(screen.selectedRow == 2)
        #expect(world.note.stack.ids == notes.map(\.id))
        #expect(try notes.map { try #require(try world.store.note(id: $0.id)).updatedAt } == before)
        #expect(screen.toastText == nil)
        #expect(try world.store.trashCount() == 0)
    }

    @Test func commandZWhileTheToastIsUpIsTheToastsUndo() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.selectRows(from: 0, to: 1)
        screen.moveSelectionToTrash()
        let manager = try #require(screen.field.currentEditor()?.undoManager)
        #expect(manager.canUndo)
        manager.undo()
        #expect(screen.results.count == 5)
        #expect(try world.store.trashCount() == 0)
    }

    @Test func undoWithNoToastDoesNothing() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        #expect(!screen.undoMoveToTrash())
        #expect(screen.field.currentEditor()?.undoManager?.canUndo == false)
    }

    @Test func typingEndsTheToastAndCommandZIsTheFieldsAgain() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 0)
        screen.moveSelectionToTrash()
        #expect(screen.toastText != nil)
        let editor = try #require(screen.field.currentEditor() as? NSTextView)
        editor.insertText("note", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(screen.query == "note")
        #expect(screen.toastText == nil)
        #expect(!screen.undoMoveToTrash())
        #expect(try world.store.trashCount() == 1)
    }

    @Test func leavingSearchEndsTheToast() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 0)
        screen.moveSelectionToTrash()
        #expect(screen.toastText != nil)
        _ = world.stack.cancel()
        #expect(screen.toastText == nil)
        #expect(!world.note.isToastShowing)
        #expect(!screen.undoMoveToTrash())
        #expect(try world.store.trashCount() == 1)
    }

    @Test func hidingThePanelEndsTheToast() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.moveSelectionToTrash()
        world.stack.hide()
        #expect(!world.note.isToastShowing)
        #expect(screen.toastText == nil)
    }

    @Test func theToastGoesOutAfterFiveSecondsAndTheMouseHoldsIt() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 0)
        screen.moveSelectionToTrash()
        world.scheduler.advance(by: 4.9)
        #expect(screen.toastText != nil)
        world.scheduler.advance(by: 0.2)
        #expect(screen.toastText == nil)

        screen.click(row: 0)
        screen.moveSelectionToTrash()
        world.note.trashToast.hoverChanged(true)
        world.scheduler.advance(by: 60)
        #expect(screen.toastText != nil)
        world.note.trashToast.hoverChanged(false)
        world.scheduler.advance(by: 5.1)
        #expect(screen.toastText == nil)
    }

    @Test func selectingRowsDuringTheToastKeepsItAndTheToastKeepsThePillAway() throws {
        try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 0)
        screen.moveSelectionToTrash()
        screen.selectAllRows()
        #expect(screen.toastText == "Note moved to Trash")
        #expect(!screen.isSelectionPillShown)
        world.scheduler.advance(by: 6)
        #expect(screen.isSelectionPillShown)
        #expect(screen.selectionPillText == "4 selected")
    }

    @Test func aSecondDeletionReplacesTheToastAndUndoBringsBackOnlyTheLastOne() throws {
        let notes = try fiveNotes()
        let screen = try world.openSearch()
        screen.click(row: 0)
        screen.moveSelectionToTrash()
        world.scheduler.advance(by: 3)
        screen.click(row: 0)
        screen.moveSelectionToTrash()
        world.scheduler.advance(by: 3)
        #expect(screen.toastText == "Note moved to Trash")
        #expect(screen.undoMoveToTrash())
        #expect(world.titles(screen) == ["note d", "note c", "note b", "note a"])
        #expect(try world.store.trash().map(\.id) == [notes[4].id])
        #expect(rows(screen) == [0])
    }
}
