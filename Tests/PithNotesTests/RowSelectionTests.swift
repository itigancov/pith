import Foundation
import Testing
@testable import PithNotes

struct RowSelectionTests {
    private func rows(_ selection: RowSelection) -> [Int] { Array(selection.selected) }

    // MARK: Start

    @Test func startsOnTheFirstRow() {
        let selection = RowSelection(count: 5)
        #expect(rows(selection) == [0])
        #expect(selection.active == 0)
        #expect(!selection.isMultiple)
    }

    @Test func isEmptyWithNoRows() {
        let selection = RowSelection(count: 0)
        #expect(selection.selected.isEmpty)
        #expect(selection.active == nil)
    }

    @Test func resetGoesBackToTheFirstRowOrNothing() {
        var selection = RowSelection(count: 5)
        selection.selectAll()
        selection.reset(count: 3)
        #expect(rows(selection) == [0])
        selection.reset(count: 0)
        #expect(selection.selected.isEmpty)
        #expect(selection.active == nil)
    }

    // MARK: Shift and arrows

    @Test func extendGrowsFromTheAnchorAndTheActiveRowMoves() {
        var selection = RowSelection(count: 6)
        selection.click(1)
        selection.extend(by: 1)
        selection.extend(by: 1)
        #expect(rows(selection) == [1, 2, 3])
        #expect(selection.active == 3)
        #expect(selection.isMultiple)
    }

    @Test func extendUpGrowsUpward() {
        var selection = RowSelection(count: 6)
        selection.click(3)
        selection.extend(by: -1)
        selection.extend(by: -1)
        #expect(rows(selection) == [1, 2, 3])
        #expect(selection.active == 1)
    }

    @Test func extendTheOtherWayFirstShrinksToTheAnchorThenGrowsTheOtherWay() {
        var selection = RowSelection(count: 8)
        selection.click(3)
        selection.extend(by: -1)
        selection.extend(by: -1)
        #expect(rows(selection) == [1, 2, 3])
        selection.extend(by: 1)
        #expect(rows(selection) == [2, 3])
        selection.extend(by: 1)
        #expect(rows(selection) == [3])
        #expect(!selection.isMultiple)
        selection.extend(by: 1)
        #expect(rows(selection) == [3, 4])
        #expect(selection.active == 4)
    }

    @Test func extendStopsAtTheEnds() {
        var selection = RowSelection(count: 3)
        selection.click(1)
        selection.extend(by: 1)
        selection.extend(by: 1)
        selection.extend(by: 1)
        #expect(rows(selection) == [1, 2])
        selection.click(1)
        selection.extend(by: -1)
        selection.extend(by: -1)
        #expect(rows(selection) == [0, 1])
    }

    @Test func extendWithNoRowsDoesNothing() {
        var selection = RowSelection(count: 0)
        selection.extend(by: 1)
        #expect(selection.selected.isEmpty)
    }

    // MARK: Arrows

    @Test func moveGoesOneRowFromTheActiveOne() {
        var selection = RowSelection(count: 6)
        selection.click(1)
        selection.extend(by: 1)
        selection.extend(by: 1)
        selection.move(by: 1)
        #expect(rows(selection) == [4])
        #expect(selection.active == 4)
    }

    @Test func moveUpFromAMultipleSelectionStepsFromTheActiveRow() {
        var selection = RowSelection(count: 6)
        selection.click(4)
        selection.extend(by: -1)
        selection.extend(by: -1)
        selection.move(by: -1)
        #expect(rows(selection) == [1])
    }

    @Test func moveStopsAtTheEnds() {
        var selection = RowSelection(count: 3)
        selection.move(by: -1)
        #expect(rows(selection) == [0])
        selection.click(2)
        selection.move(by: 1)
        #expect(rows(selection) == [2])
    }

    @Test func moveAfterMovingStartsANewAnchor() {
        var selection = RowSelection(count: 6)
        selection.move(by: 1)
        selection.extend(by: 1)
        #expect(rows(selection) == [1, 2])
    }

    // MARK: Clicks

    @Test func aClickSelectsOnlyThatRow() {
        var selection = RowSelection(count: 5)
        selection.selectAll()
        selection.click(2)
        #expect(rows(selection) == [2])
        #expect(selection.active == 2)
    }

    @Test func shiftClickSelectsFromTheAnchorToTheRow() {
        var selection = RowSelection(count: 8)
        selection.click(2)
        selection.shiftClick(5)
        #expect(rows(selection) == [2, 3, 4, 5])
        #expect(selection.active == 5)
        selection.shiftClick(0)
        #expect(rows(selection) == [0, 1, 2])
        #expect(selection.active == 0)
    }

    @Test func shiftClickDropsWhatCommandClickAddedOutsideTheRange() {
        var selection = RowSelection(count: 10)
        selection.click(1)
        selection.commandClick(7)
        selection.shiftClick(9)
        #expect(rows(selection) == [7, 8, 9])
        selection.commandClick(2)
        selection.shiftClick(4)
        #expect(rows(selection) == [2, 3, 4])
    }

    @Test func commandClickAddsARowAndMovesTheAnchorThere() {
        var selection = RowSelection(count: 10)
        selection.click(1)
        selection.commandClick(5)
        #expect(rows(selection) == [1, 5])
        #expect(selection.active == 5)
        selection.extend(by: 1)
        #expect(rows(selection) == [5, 6])
    }

    @Test func commandClickOnASelectedRowTakesItOut() {
        var selection = RowSelection(count: 10)
        selection.click(1)
        selection.commandClick(4)
        selection.commandClick(7)
        selection.commandClick(4)
        #expect(rows(selection) == [1, 7])
        // The row clicked is still where Shift and the arrows start from.
        selection.shiftClick(2)
        #expect(rows(selection) == [2, 3, 4])
    }

    @Test func theActiveRowStaysInTheSelectionAfterATakeOut() {
        var selection = RowSelection(count: 10)
        selection.click(1)
        selection.commandClick(4)
        selection.commandClick(4)
        #expect(rows(selection) == [1])
        #expect(selection.active == 1)
    }

    @Test func commandClickOnTheLastSelectedRowLeavesNothing() {
        var selection = RowSelection(count: 5)
        selection.click(2)
        selection.commandClick(2)
        #expect(selection.selected.isEmpty)
        #expect(selection.active == nil)
        // Shift from there starts at the row clicked.
        selection.extend(by: 1)
        #expect(rows(selection) == [2, 3])
    }

    @Test func shiftClickWithNothingSelectedIsAClick() {
        var selection = RowSelection(count: 5)
        selection.click(2)
        selection.commandClick(2)
        selection.shiftClick(4)
        #expect(rows(selection) == [2, 3, 4])
    }

    // MARK: All, collapse

    @Test func selectAllTakesEveryRowWithTheActiveOneLast() {
        var selection = RowSelection(count: 4)
        selection.selectAll()
        #expect(rows(selection) == [0, 1, 2, 3])
        #expect(selection.active == 3)
        selection.extend(by: -1)
        #expect(rows(selection) == [0, 1, 2])
    }

    @Test func selectAllWithNoRowsDoesNothing() {
        var selection = RowSelection(count: 0)
        selection.selectAll()
        #expect(selection.selected.isEmpty)
    }

    @Test func collapseKeepsTheActiveRow() {
        var selection = RowSelection(count: 6)
        selection.click(1)
        selection.extend(by: 1)
        selection.extend(by: 1)
        selection.collapse()
        #expect(rows(selection) == [3])
        #expect(selection.active == 3)
        #expect(!selection.isMultiple)
    }

    // MARK: Removing

    @Test func removingABlockSelectsTheRowThatTookItsPlace() {
        var selection = RowSelection(count: 8)
        selection.click(2)
        selection.extend(by: 1)
        selection.extend(by: 1)
        let after = selection.removing(selection.selected, newCount: 5)
        #expect(rows(after) == [2])
        #expect(after.active == 2)
    }

    @Test func removingScatteredRowsSelectsTheRowThatTookTheLowestOnesPlace() {
        var selection = RowSelection(count: 8)
        selection.click(1)
        selection.commandClick(4)
        selection.commandClick(6)
        // 0 2 3 5 7 stay: the row after 6 is 7, now at index 4
        let after = selection.removing(selection.selected, newCount: 5)
        #expect(rows(after) == [4])
    }

    @Test func removingTheLastRowsSelectsTheOneAbove() {
        var selection = RowSelection(count: 6)
        selection.click(4)
        selection.extend(by: 1)
        let after = selection.removing(selection.selected, newCount: 4)
        #expect(rows(after) == [3])
    }

    @Test func removingEverythingLeavesNothing() {
        var selection = RowSelection(count: 3)
        selection.selectAll()
        let after = selection.removing(selection.selected, newCount: 0)
        #expect(after.selected.isEmpty)
        #expect(after.active == nil)
    }

    @Test func theAnchorAfterRemovingIsTheRowSelected() {
        var selection = RowSelection(count: 8)
        selection.click(2)
        selection.extend(by: 1)
        var after = selection.removing(selection.selected, newCount: 6)
        after.extend(by: 1)
        #expect(rows(after) == [2, 3])
    }

    // MARK: Selecting given rows

    @Test func selectingRowsMakesTheLowestTheAnchorAndTheHighestActive() {
        let selection = RowSelection(selecting: IndexSet([1, 2, 5]), count: 8)
        #expect(rows(selection) == [1, 2, 5])
        #expect(selection.active == 5)
    }

    @Test func selectingNoRowsIsAReset() {
        let selection = RowSelection(selecting: IndexSet(), count: 4)
        #expect(rows(selection) == [0])
    }

    @Test func selectingRowsOutsideTheListIgnoresThem() {
        let selection = RowSelection(selecting: IndexSet([1, 9]), count: 4)
        #expect(rows(selection) == [1])
    }
}
