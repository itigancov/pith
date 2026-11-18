import Foundation
import Testing
@testable import PithEditor

/// Text with its selection marked inline: `|` is the caret, `«…»` a selection (`[` is taken by task checkboxes).
private struct Marked: Equatable, CustomStringConvertible {
    let text: String
    let selection: NSRange

    init(_ marked: String) {
        var text = ""
        var start: Int?
        var end: Int?
        for character in marked {
            let here = text.utf16.count
            switch character {
            case "|": start = here; end = here
            case "«": start = here
            case "»": end = here
            default: text.append(character)
            }
        }
        self.text = text
        let location = start ?? text.utf16.count
        self.selection = NSRange(location: location, length: (end ?? location) - location)
    }

    init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }

    var description: String {
        let ns = text as NSString
        let before = ns.substring(to: selection.location)
        let inside = ns.substring(with: selection)
        let after = ns.substring(from: selection.upperBound)
        let shown = selection.length == 0 ? "\(before)|\(after)" : "\(before)«\(inside)»\(after)"
        return shown.debugDescription
    }
}

private typealias Command = (String, NSRange) -> TextEdit?

/// Runs `command` on `before` and returns the marked result, or `nil` when the Command declines.
private func run(_ command: Command, _ before: String) -> Marked? {
    let input = Marked(before)
    guard let edit = command(input.text, input.selection) else { return nil }
    return Marked(text: apply(edit, to: input.text), selection: edit.selection)
}

/// Applies the replacements from the last, so earlier ranges stay valid.
private func apply(_ edit: TextEdit, to text: String) -> String {
    let result = NSMutableString(string: text)
    for replacement in edit.replacements.reversed() {
        result.replaceCharacters(in: replacement.range, with: replacement.string)
    }
    return result as String
}

private func newline(_ before: String) -> Marked? { run(BlockCommands.newline, before) }
private func indent(_ before: String) -> Marked? { run(BlockCommands.indent, before) }
private func outdent(_ before: String) -> Marked? { run(BlockCommands.outdent, before) }

struct BlockCommandsTests {
    // MARK: Newline continues the prefix

    @Test func newlineContinuesABullet() {
        #expect(newline("- a|") == Marked("- a\n- |"))
    }

    @Test func newlineKeepsTheBulletCharacter() {
        #expect(newline("* a|") == Marked("* a\n* |"))
        #expect(newline("+ a|") == Marked("+ a\n+ |"))
    }

    @Test func newlineIncrementsTheNumber() {
        #expect(newline("3. a|") == Marked("3. a\n4. |"))
        #expect(newline("9. a|") == Marked("9. a\n10. |"))
    }

    @Test func newlineStartsAnOpenTask() {
        #expect(newline("- [ ] a|") == Marked("- [ ] a\n- [ ] |"))
        #expect(newline("* [x] a|") == Marked("* [x] a\n* [ ] |"))
        #expect(newline("- [X] a|") == Marked("- [X] a\n- [ ] |"))
    }

    @Test func newlineContinuesANumberedTask() {
        #expect(newline("1. [x] a|") == Marked("1. [x] a\n2. [ ] |"))
    }

    @Test func newlineContinuesAQuote() {
        #expect(newline("> a|") == Marked("> a\n> |"))
        #expect(newline("> - a|") == Marked("> - a\n> |"))
    }

    @Test func newlineKeepsTheIndent() {
        #expect(newline("- a\n  - b|") == Marked("- a\n  - b\n  - |"))
        #expect(newline("- a\n\t- [ ] b|") == Marked("- a\n\t- [ ] b\n\t- [ ] |"))
    }

    @Test func newlineInTheMiddleMovesTheTailIntoTheNewItem() {
        #expect(newline("- ab|cd") == Marked("- ab\n- |cd"))
        #expect(newline("2. ab|cd\n3. e") == Marked("2. ab\n3. |cd\n4. e"))
    }

    @Test func newlineInsideTheMarkerActsAtTheStartOfTheContent() {
        #expect(newline("-| a") == Marked("- \n- |a"))
        #expect(newline("  |- [ ] a") == Marked("  - [ ] \n  - [ ] |a"))
        #expect(newline("1|0. a") == Marked("10. \n11. |a"))
    }

    @Test func newlineReplacesTheSelectionFirst() {
        #expect(newline("- a«bc»d") == Marked("- a\n- |d"))
        #expect(newline("- a«b\n- c»d") == Marked("- a\n- |d"))
        #expect(newline("- a\n- «b»") == Marked("- a\n|"))
        #expect(newline("1. a\n  1. «b»\n2. c") == Marked("1. a\n2. |\n3. c"))
        #expect(newline("«text\n»- a") == Marked("- \n- |a"))
        #expect(newline("«- a»") == nil)
    }

    @Test func newlineUsesTheLineBreakOfTheLine() {
        #expect(newline("- a|\r\n- b") == Marked("- a\r\n- |\r\n- b"))
        #expect(newline("- a\r\n- b|") == Marked("- a\r\n- b\r\n- |"))
    }

    @Test func newlineCountsUTF16() {
        #expect(newline("- мир 🌍|") == Marked("- мир 🌍\n- |"))
        #expect(newline("- 🌍|мир") == Marked("- 🌍\n- |мир"))
    }

    // MARK: Newline on an empty item

    @Test func newlineOnAnEmptyTopLevelItemRemovesThePrefix() {
        #expect(newline("- a\n- |") == Marked("- a\n|"))
        #expect(newline("- a\n- [ ] |") == Marked("- a\n|"))
        #expect(newline("- a\n- [x]|") == Marked("- a\n|"))
        #expect(newline("1. a\n2. |\nb") == Marked("1. a\n|\nb"))
    }

    @Test func itemOfOnlySpacesIsEmpty() {
        #expect(newline("1.  |") == Marked("|"))
        #expect(newline("- [ ]   |") == Marked("|"))
        #expect(newline("|-   ") == Marked("|"))
    }

    @Test func newlineOnAnEmptyQuoteRemovesTheMarker() {
        #expect(newline("> a\n> |") == Marked("> a\n|"))
        #expect(newline("> a\n>  |") == Marked("> a\n|"))
    }

    @Test func newlineOnAnEmptyNestedItemOutdentsIt() {
        #expect(newline("- a\n  - |") == Marked("- a\n- |"))
        #expect(newline("- a\n  - b\n    - |") == Marked("- a\n  - b\n  - |"))
    }

    @Test func outdentedEmptyItemTakesTheMarkerOfThePreviousItemOnItsLevel() {
        #expect(newline("* a\n  1. b\n  2. |") == Marked("* a\n  1. b\n* |"))
        #expect(newline("3. a\n  - [ ] b\n  - [ ] |") == Marked("3. a\n  - [ ] b\n4. [ ] |"))
        #expect(newline("- [x] a\n  - |") == Marked("- [x] a\n- |"))
        #expect(newline("1. a\n  - b\n  - |\n2. c") == Marked("1. a\n  - b\n2. |\n3. c"))
    }

    @Test func emptyItemNestedManyLevelsDeepMovesToItsParentsLevel() {
        #expect(newline("- a\n        - |") == Marked("- a\n- |"))
        #expect(newline("- a\n  1. b\n          - |") == Marked("- a\n  1. b\n  2. |"))
        #expect(newline("      - |") == Marked("    - |"))
    }

    @Test func outdentedEmptyItemKeepsItsChildren() {
        #expect(newline("- a\n  - |\n    - b") == Marked("- a\n- |\n  - b"))
    }

    @Test func newlineOnAnEmptyItemLeavingTheListKeepsTheOtherNumbers() {
        #expect(newline("1. a\n2. |\n3. b") == Marked("1. a\n|\n3. b"))
    }

    // MARK: Newline elsewhere

    @Test func newlineOutsideListsAndQuotesDeclines() {
        #expect(newline("text|") == nil)
        #expect(newline("# head|ing") == nil)
        #expect(newline("|") == nil)
        #expect(newline("a\n  |") == nil)
        #expect(newline("```\n- a|\n```") == nil)
        #expect(newline("-|") == nil)
    }

    // MARK: Indent and outdent

    @Test func indentNestsTheItemWhereverTheCaretIs() {
        #expect(indent("- a\n- b|") == Marked("- a\n  - b|"))
        #expect(indent("- a\n|- b") == Marked("- a\n  |- b"))
        #expect(indent("- a\n- [ ] |b") == Marked("- a\n  - [ ] |b"))
    }

    @Test func outdentUnnestsTheItem() {
        #expect(outdent("- a\n  - b|") == Marked("- a\n- b|"))
        #expect(outdent("- a\n  |- b") == Marked("- a\n|- b"))
    }

    @Test func childrenMoveWithTheirParent() {
        #expect(indent("- a\n- b|\n  - c\n    - d\n- e") == Marked("- a\n  - b|\n    - c\n      - d\n- e"))
        #expect(outdent("- a\n  - b|\n    - c\n  - d") == Marked("- a\n- b|\n  - c\n  - d"))
    }

    @Test func indentHasNoLimitBelowThePreviousItem() {
        #expect(indent("- a\n  - b|") == Marked("- a\n    - b|"))
        #expect(indent("- a\n  - b\n            - c|") == Marked("- a\n  - b\n              - c|"))
    }

    @Test func firstItemIndentsToo() {
        #expect(indent("- a|\n- b") == Marked("  - a|\n- b"))
        #expect(indent("text\n- a|") == Marked("text\n  - a|"))
    }

    @Test func itemsDeeperThanTheirParentByManyLevelsMoveWithIt() {
        #expect(outdent("  - a|\n          - b\n- c") == Marked("- a|\n        - b\n- c"))
    }

    @Test func outdentAtLevelZeroDoesNothing() {
        #expect(outdent("- a|") == Marked("- a|"))
        #expect(outdent("1. [ ] a|") == Marked("1. [ ] a|"))
    }

    @Test func shiftedIndentIsTwoSpacesPerLevel() {
        #expect(indent("- a\n    - b\n    - c|") == Marked("- a\n    - b\n      - c|"))
        #expect(outdent("- a\n\t- b\n\t\t- c|") == Marked("- a\n\t- b\n      - c|"))
        #expect(indent("1. a\n   - b|") == Marked("1. a\n    - b|"))
    }

    @Test func markerStaysWhenShifted() {
        #expect(indent("- a\n* b|") == Marked("- a\n  * b|"))
        #expect(outdent("- a\n  + [x] b|") == Marked("- a\n+ [x] b|"))
    }

    @Test func selectionShiftsEveryItemItTouchesAndNothingElse() {
        #expect(indent("- a\n«- b\ntext\n# h\n> q\n- c\n- d»") == Marked("- a\n«  - b\ntext\n# h\n> q\n  - c\n  - d»"))
        #expect(outdent("- a\n  - «b\n  - c»\n  - d") == Marked("- a\n- «b\n- c»\n  - d"))
    }

    @Test func selectionEndingAtTheStartOfALineLeavesThatLine() {
        #expect(indent("- a\n«- b\n»- c") == Marked("- a\n«  - b\n»- c"))
    }

    @Test func selectedParentAndChildMoveOneLevel() {
        #expect(indent("- a\n- «b\n  - c»") == Marked("- a\n  - «b\n    - c»"))
    }

    @Test func shiftOutsideListItemsDeclines() {
        #expect(indent("text|") == nil)
        #expect(outdent("# h|") == nil)
        #expect(indent("> q|") == nil)
        #expect(indent("```\n- a|\n```") == nil)
        #expect(indent("«text\n# h»") == nil)
    }

    @Test func shiftCountsUTF16() {
        #expect(indent("- мир\n- 🌍|мир") == Marked("- мир\n  - 🌍|мир"))
    }

    // MARK: Renumbering

    @Test func newlineInTheMiddleRenumbersTheRest() {
        #expect(newline("1. a|\n2. b\n3. c") == Marked("1. a\n2. |\n3. b\n4. c"))
    }

    @Test func renumberingKeepsTheFirstNumber() {
        #expect(newline("3. a|\n4. b") == Marked("3. a\n4. |\n5. b"))
        #expect(newline("|7. a") == Marked("7. \n8. |a"))
    }

    @Test func renumberingGrowsTheNumberWidth() {
        #expect(newline("8. a\n9. b|\n10. c") == Marked("8. a\n9. b\n10. |\n11. c"))
    }

    @Test func indentStartsANewSublistAtOne() {
        #expect(indent("1. a\n2. b|\n3. c") == Marked("1. a\n  1. b|\n2. c"))
        #expect(indent("- a\n5. b|") == Marked("- a\n  1. b|"))
    }

    @Test func indentJoinsAnExistingSublist() {
        #expect(indent("1. a\n  1. x\n  2. y\n2. b|\n3. c") == Marked("1. a\n  1. x\n  2. y\n  3. b|\n2. c"))
    }

    @Test func listLeftByItsFirstItemKeepsItsFirstNumber() {
        #expect(outdent("- a\n  5. b|\n  6. c") == Marked("- a\n1. b|\n  5. c"))
    }

    @Test func outdentRenumbersBothLists() {
        #expect(outdent("1. a\n  1. x\n  2. y|\n  3. z\n2. b") == Marked("1. a\n  1. x\n2. y|\n  1. z\n3. b"))
    }

    @Test func bulletOnTheSameLevelBreaksTheNumbering() {
        #expect(newline("1. a|\n2. b\n- c\n4. d") == Marked("1. a\n2. |\n3. b\n- c\n4. d"))
    }

    @Test func deeperItemsDoNotBreakTheNumbering() {
        #expect(newline("1. a|\n  - x\n2. b") == Marked("1. a\n2. |\n  - x\n3. b"))
    }

    @Test func untouchedListsKeepTheirNumbers() {
        #expect(indent("1. a\n1. b\n- c\n- d|\n  1. x\n  1. y") == Marked("1. a\n1. b\n- c\n  - d|\n    1. x\n    1. y"))
    }

    @Test func shiftKeepsCRLF() {
        #expect(indent("- a\r\n- b|\r\n- c") == Marked("- a\r\n  - b|\r\n- c"))
    }
}
