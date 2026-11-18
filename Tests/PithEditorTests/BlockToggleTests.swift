import Foundation
import Testing
@testable import PithEditor

private func bullet(_ before: String) -> Marked? { run(BlockCommands.toggle(.bullet), before) }
private func ordered(_ before: String) -> Marked? { run(BlockCommands.toggle(.ordered), before) }
private func task(_ before: String) -> Marked? { run(BlockCommands.toggle(.task), before) }
private func quote(_ before: String) -> Marked? { run(BlockCommands.toggle(.quote), before) }
private func codeBlock(_ before: String) -> Marked? { run(BlockCommands.toggle(.codeBlock), before) }
private func heading(_ level: Int, _ before: String) -> Marked? { run(BlockCommands.toggle(.heading(level: level)), before) }

struct BlockToggleTests {
    // MARK: Headings

    @Test func headingMakesTheLineAHeadingOfItsLevel() {
        #expect(heading(1, "te|xt") == Marked("# te|xt"))
        #expect(heading(2, "te|xt") == Marked("## te|xt"))
        #expect(heading(3, "«text»") == Marked("### «text»"))
    }

    @Test func headingOfTheSameLevelBecomesAParagraph() {
        #expect(heading(2, "## te|xt") == Marked("te|xt"))
    }

    @Test func headingOfAnotherLevelChangesTheLevel() {
        #expect(heading(2, "# te|xt") == Marked("## te|xt"))
        #expect(heading(1, "### te|xt") == Marked("# te|xt"))
    }

    @Test func fourHashesAreTextForHeadings() {
        #expect(heading(1, "#### te|xt") == Marked("# #### te|xt"))
    }

    // MARK: Lists, tasks and quotes

    @Test func eachStyleMakesAParagraphItsKind() {
        #expect(bullet("te|xt") == Marked("- te|xt"))
        #expect(ordered("te|xt") == Marked("1. te|xt"))
        #expect(task("te|xt") == Marked("- [ ] te|xt"))
        #expect(quote("te|xt") == Marked("> te|xt"))
    }

    @Test func eachStyleMakesItsKindAParagraph() {
        #expect(bullet("- te|xt") == Marked("te|xt"))
        #expect(bullet("* te|xt") == Marked("te|xt"))
        #expect(ordered("12. te|xt") == Marked("te|xt"))
        #expect(task("- [x] te|xt") == Marked("te|xt"))
        #expect(quote("> te|xt") == Marked("te|xt"))
    }

    @Test func aParagraphGetsLevelZero() {
        #expect(bullet("    - te|xt") == Marked("te|xt"))
        #expect(task("  - [ ] te|xt") == Marked("te|xt"))
    }

    @Test func aMixedSelectionBecomesTheStyleAndAUniformOneParagraphs() {
        #expect(bullet("«a\n- b\n# c»") == Marked("- «a\n- b\n- c»"))
        #expect(bullet("«- a\n* b»") == Marked("«a\nb»"))
        #expect(quote("«> a\nb»") == Marked("«> a\n> b»"))
    }

    @Test func changingTheKindReplacesTheMarkerAndKeepsTheLevel() {
        #expect(bullet("- [ ] a|") == Marked("- a|"))
        #expect(bullet("  * [x] a|") == Marked("  - a|"))
        #expect(task("  - a|") == Marked("  - [ ] a|"))
        #expect(task("1. a|") == Marked("- [ ] a|"))
        #expect(ordered("  - a|") == Marked("  1. a|"))
        #expect(ordered("\t- [ ] a|") == Marked("\t1. a|"))
        #expect(bullet("> a|") == Marked("- a|"))
        #expect(bullet("## a|") == Marked("- a|"))
    }

    @Test func headingsAndQuotesHaveNoIndent() {
        #expect(quote("  - a|") == Marked("> a|"))
        #expect(heading(1, "    1. a|") == Marked("# a|"))
        #expect(quote("# a|") == Marked("> a|"))
    }

    @Test func blankLinesInTheSelectionStayBlank() {
        #expect(bullet("«a\n\nb»") == Marked("- «a\n\n- b»"))
        #expect(task("«a\n  \nb»") == Marked("- [ ] «a\n  \n- [ ] b»"))
    }

    @Test func aBlankLineUnderTheCaretGetsTheMarker() {
        #expect(bullet("|") == Marked("- |"))
        #expect(bullet("a\n|") == Marked("a\n- |"))
        #expect(task("a\n  |\nb") == Marked("a\n- [ ] |\nb"))
        #expect(quote("|") == Marked("> |"))
        #expect(heading(2, "|") == Marked("## |"))
    }

    @Test func aSelectionOfBlankLinesDeclines() {
        #expect(bullet("«\n\n»") == nil)
    }

    @Test func aCaretInTheOldMarkerGoesToTheStartOfTheText() {
        #expect(quote("-| a") == Marked("> |a"))
        #expect(bullet("##| a") == Marked("- |a"))
        #expect(bullet("|- a") == Marked("|a"))
        #expect(task("- [|x] a") == Marked("|a"))
    }

    @Test func eachStyleDeclinesInACodeBlock() {
        #expect(bullet("```\na|\n```") == nil)
        #expect(heading(1, "```\na|\n```") == nil)
        #expect(quote("«a\n```\nb»\n```") == nil)
    }

    @Test func togglesHandleCRLFAndCountUTF16() {
        #expect(bullet("a\r\n«b\r\nc»") == Marked("a\r\n- «b\r\n- c»"))
        #expect(quote("🎉 мир|") == Marked("> 🎉 мир|"))
        #expect(heading(1, "# 🎉 мир|") == Marked("🎉 мир|"))
    }

    // MARK: Numbering

    @Test func orderedNumbersTheLinesInOrder() {
        #expect(ordered("«a\nb\nc»") == Marked("1. «a\n2. b\n3. c»"))
        #expect(ordered("«- a\n  - b\n  - c»") == Marked("1. «a\n  1. b\n  2. c»"))
    }

    @Test func orderedContinuesFromTheItemAbove() {
        #expect(ordered("4. a\nb|") == Marked("4. a\n5. b|"))
        #expect(ordered("1. a\n  - x\nb|") == Marked("1. a\n  - x\n2. b|"))
        #expect(ordered("1. a\n|") == Marked("1. a\n2. |"))
    }

    @Test func orderedRenumbersTheItemsBelow() {
        #expect(ordered("1. a\nb|\n2. c\n3. d") == Marked("1. a\n2. b|\n3. c\n4. d"))
        #expect(ordered("a|\n5. b") == Marked("1. a|\n2. b"))
    }

    @Test func orderedNumbersAMixedSelectionAgain() {
        #expect(ordered("«3. a\nb\n7. c»") == Marked("1. «a\n2. b\n3. c»"))
    }

    @Test func leavingTheNumberedListKeepsTheNumbersBelow() {
        #expect(ordered("1. a\n2. b|\n3. c") == Marked("1. a\nb|\n3. c"))
        #expect(bullet("1. a\n2. b|\n3. c") == Marked("1. a\n- b|\n3. c"))
    }

    // MARK: Code blocks

    @Test func codeBlockFencesTheLinesAndPutsTheCaretWhereTheLanguageGoes() {
        #expect(codeBlock("x\n«a\nb»\ny") == Marked("x\n```|\na\nb\n```\ny"))
        #expect(codeBlock("- a|") == Marked("```|\n- a\n```"))
    }

    @Test func codeBlockLeavesBlankLinesAtTheEdgesOfTheSelectionOutside() {
        #expect(codeBlock("«\na\n\nb\n»") == Marked("\n```|\na\n\nb\n```\n"))
    }

    @Test func codeBlockOnABlankLineInsertsAnEmptyBlock() {
        #expect(codeBlock("|") == Marked("```\n|\n```"))
        #expect(codeBlock("a\n|\nb") == Marked("a\n```\n|\n```\nb"))
        #expect(codeBlock("«\n\n»") == nil)
    }

    @Test func codeBlockInsideACodeBlockRemovesBothFences() {
        #expect(codeBlock("x\n```swift\na|\nb\n```\ny") == Marked("x\na|\nb\ny"))
        #expect(codeBlock("```\n«a»\n```") == Marked("«a»"))
    }

    @Test func codeBlockOnAFenceMovesTheCaretIntoTheCode() {
        #expect(codeBlock("```sw|ift\na\n```") == Marked("|a"))
        #expect(codeBlock("```\na\n``|`") == Marked("a|"))
    }

    @Test func codeBlockRemovesAnUnclosedFence() {
        #expect(codeBlock("x\n```\na|") == Marked("x\na|"))
        #expect(codeBlock("```|") == Marked("|"))
    }

    @Test func codeBlockRemovesAnEmptyBlock() {
        #expect(codeBlock("a\n```|\n```\nb") == Marked("a\n|\nb"))
    }

    @Test func codeBlockUsesTheLineBreakOfTheText() {
        #expect(codeBlock("«a\r\nb»") == Marked("```|\r\na\r\nb\r\n```"))
        #expect(codeBlock("```\r\na|\r\n```") == Marked("a|"))
    }
}
