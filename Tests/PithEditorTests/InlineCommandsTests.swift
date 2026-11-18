import Foundation
import Testing
@testable import PithEditor

private func bold(_ before: String) -> Marked? { run(InlineCommands.toggle(.strong), before) }
private func italic(_ before: String) -> Marked? { run(InlineCommands.toggle(.emphasis), before) }
private func highlight(_ before: String) -> Marked? { run(InlineCommands.toggle(.highlight), before) }
private func strike(_ before: String) -> Marked? { run(InlineCommands.toggle(.strikethrough), before) }
private func code(_ before: String) -> Marked? { run(InlineCommands.toggle(.code), before) }
private func link(_ before: String) -> Marked? { run(InlineCommands.toggleLink, before) }

struct InlineCommandsTests {
    // MARK: Wrapping

    @Test func boldWrapsTheSelectionAndSelectsItsContent() {
        #expect(bold("a «bc» d") == Marked("a **«bc»** d"))
    }

    @Test func boldWrapsTheWordAtTheCaretAndKeepsTheCaretAmongItsLetters() {
        #expect(bold("a wo|rd b") == Marked("a **wo|rd** b"))
        #expect(bold("a |word b") == Marked("a **|word** b"))
        #expect(bold("a word| b") == Marked("a **word|** b"))
    }

    @Test func boldOutsideAWordInsertsAnEmptyPair() {
        #expect(bold("a | b") == Marked("a **|** b"))
        #expect(bold("|") == Marked("**|**"))
        #expect(bold("a.|") == Marked("a.**|**"))
    }

    // MARK: Unwrapping

    @Test func boldRemovesTheMarkersAroundTheCaret() {
        #expect(bold("a **bo|ld** b") == Marked("a bo|ld b"))
        #expect(bold("a |**bold** b") == Marked("a |bold b"))
        #expect(bold("a **bold**| b") == Marked("a bold| b"))
        #expect(bold("a *|*bold** b") == Marked("a |bold b"))
    }

    @Test func boldRemovesTheMarkersAroundTheSelection() {
        #expect(bold("**b«ol»d**") == Marked("b«ol»d"))
        #expect(bold("«**bold**»") == Marked("«bold»"))
    }

    @Test func boldRemovesUnderscoreMarkersToo() {
        #expect(bold("a __bo|ld__ b") == Marked("a bo|ld b"))
    }

    @Test func boldInAnEmptyPairRemovesIt() {
        #expect(bold("a **|** b") == Marked("a | b"))
        #expect(bold("__|__") == Marked("|"))
    }

    @Test func boldLeavesWhitespaceAtTheEdgesOfTheSelectionOutside() {
        #expect(bold("a« word »b") == Marked("a **«word»** b"))
        #expect(bold("«word\t»") == Marked("**«word»**\t"))
    }

    @Test func boldOnAWhitespaceSelectionInsertsAnEmptyPair() {
        #expect(bold("a«  »b") == Marked("a**|**  b"))
    }

    // MARK: Other styles

    @Test func everyStyleWrapsAndUnwrapsWithItsMarker() {
        #expect(italic("a «b» c") == Marked("a *«b»* c"))
        #expect(italic("a *b|* c") == Marked("a b| c"))
        #expect(highlight("a b|c d") == Marked("a ==b|c== d"))
        #expect(highlight("a ==b|c== d") == Marked("a b|c d"))
        #expect(strike("| a") == Marked("~~|~~ a"))
        #expect(strike("~~«b»~~") == Marked("«b»"))
        #expect(code("a «b» c") == Marked("a `«b»` c"))
        #expect(code("a `b|c` d") == Marked("a b|c d"))
    }

    @Test func everyStyleRemovesItsEmptyPair() {
        #expect(italic("*|*") == Marked("|"))
        #expect(italic("_|_") == Marked("|"))
        #expect(highlight("==|==") == Marked("|"))
        #expect(strike("~~|~~") == Marked("|"))
        #expect(code("`|`") == Marked("|"))
    }

    @Test func italicRemovesUnderscoreMarkersToo() {
        #expect(italic("a _it|alic_ b") == Marked("a it|alic b"))
    }

    @Test func italicInsideBoldAddsItalic() {
        #expect(italic("**bo|ld**") == Marked("***bo|ld***"))
        #expect(italic("**«bold»**") == Marked("***«bold»***"))
        #expect(italic("**|**") == Marked("***|***"))
    }

    @Test func nestedEmptyPairsComeOffOneAtATime() {
        #expect(italic("***|***") == Marked("**|**"))
        #expect(bold("***|***") == Marked("*|*"))
    }

    @Test func boldInsideBoldItalicRemovesOnlyBold() {
        #expect(bold("***bo|ld***") == Marked("*bo|ld*"))
        #expect(italic("***bo|ld***") == Marked("**bo|ld**"))
    }

    // MARK: Merging

    @Test func boldMergesWithTheBoldTheSelectionOverlaps() {
        #expect(bold("te«xt **bo»ld**") == Marked("te**«xt bold»**"))
        #expect(bold("**a «b** c»") == Marked("**«a b c»**"))
    }

    @Test func boldMergesTheBoldInsideTheSelection() {
        #expect(bold("«a **b** c»") == Marked("**«a b c»**"))
        #expect(bold("«**a** b __c__»") == Marked("**«a b c»**"))
    }

    // MARK: Code

    @Test func stylesOtherThanCodeDeclineInsideInlineCode() {
        #expect(bold("`co|de`") == nil)
        #expect(italic("`«code»`") == nil)
        #expect(highlight("a `b|` c") == nil)
        #expect(bold("a«b `c»d`") == nil)
    }

    @Test func boldWrapsInlineCodeAsAWhole() {
        #expect(bold("«`code`»") == Marked("**«`code`»**"))
        #expect(bold("`code`|") == Marked("`code`**|**"))
    }

    @Test func codeRemovesTheBackticksFromInside() {
        #expect(code("`co|de`") == Marked("co|de"))
        #expect(code("`«code»`") == Marked("«code»"))
        #expect(code("``a`|b``") == Marked("a`|b"))
    }

    @Test func codeRemovesThePaddingSpacesWithTheBackticks() {
        #expect(code("`` a`|b ``") == Marked("a`|b"))
    }

    @Test func codeWrapsTextWithBackticksInLongerRunsWithSpaces() {
        #expect(code("«a`b»") == Marked("`` «a`b» ``"))
        #expect(code("«a``b»") == Marked("``` «a``b» ```"))
    }

    @Test func codeMergesInlineCodeInsideTheSelection() {
        #expect(code("«a `b` c»") == Marked("`«a b c»`"))
    }

    @Test func everyStyleDeclinesInACodeBlock() {
        #expect(bold("```\nco|de\n```") == nil)
        #expect(code("```\n«code»\n```") == nil)
        #expect(italic("```swift\na|") == nil)
    }

    @Test func codeWrapsBoldAsAWhole() {
        #expect(code("«**a**»") == Marked("`«**a**»`"))
    }

    // MARK: Blocks and text

    @Test func boldOnAHeadingOrItemLineWrapsOnlyTheTextAfterTheMarker() {
        #expect(bold("«# Heading»") == Marked("# **«Heading»**"))
        #expect(bold("«- [ ] task»") == Marked("- [ ] **«task»**"))
        #expect(bold("> quo|te") == Marked("> **quo|te**"))
        #expect(bold("#| Heading") == Marked("# **|Heading**"))
        #expect(bold("  - |") == Marked("  - **|**"))
    }

    @Test func wordsAreCyrillicDigitsUnderscoresAndEmoji() {
        #expect(bold("а сло|во б") == Marked("а **сло|во** б"))
        #expect(bold("v2|_beta x") == Marked("**v2|_beta** x"))
        #expect(bold("a 🎉|🚀 b") == Marked("a **🎉|🚀** b"))
        #expect(bold("a 👩‍💻| b") == Marked("a **👩‍💻|** b"))
        #expect(bold("a 👍🏽| b") == Marked("a **👍🏽|** b"))
        #expect(bold("сло|во🎉, b") == Marked("**сло|во🎉**, b"))
    }

    @Test func togglesCountUTF16() {
        #expect(bold("🎉 «мир»") == Marked("🎉 **«мир»**"))
        #expect(bold("🎉 **м|ир** 🚀") == Marked("🎉 м|ир 🚀"))
    }

    @Test func togglesWorkWithCRLF() {
        #expect(bold("a\r\nb|c\r\nd") == Marked("a\r\n**b|c**\r\nd"))
        #expect(bold("a\r\n**b|c**\r\nd") == Marked("a\r\nb|c\r\nd"))
    }

    @Test func boldMergesIntoBoldItalic() {
        #expect(bold("te«xt ***bo»ld***") == Marked("te**«xt *bold»***"))
    }

    // MARK: Several lines

    @Test func boldWrapsEveryLineOfTheSelectionApart() {
        #expect(bold("«a\nb»") == Marked("**«a**\n**b»**"))
        #expect(bold("x«a\nb»y") == Marked("x**«a**\n**b»**y"))
    }

    @Test func boldKeepsBlockMarkersOutsideOnEveryLine() {
        #expect(bold("«- a\n# b\n> c»") == Marked("«- **a**\n# **b**\n> **c»**"))
    }

    @Test func boldUnwrapsEveryLineWhenAllAreBold() {
        #expect(bold("**«a**\n**b»**") == Marked("«a\nb»"))
        #expect(bold("«- **a**\n- __b__»") == Marked("«- a\n- b»"))
    }

    @Test func boldWrapsTheLinesThatAreNotBoldYetInAMixedSelection() {
        #expect(bold("«**a**\nb»") == Marked("«**a**\n**b»**"))
    }

    @Test func boldSkipsBlankLinesAndCodeBlocks() {
        #expect(bold("«a\n\n```\nc\n```\nd»") == Marked("**«a**\n\n```\nc\n```\n**d»**"))
    }

    @Test func boldOnASelectionWithOneNonEmptyLineActsOnThatLine() {
        #expect(bold("a«\nb»") == Marked("a\n**«b»**"))
        #expect(bold("«a\n»b") == Marked("**«a»**\nb"))
    }

    @Test func boldDeclinesASelectionThatCutsInlineCode() {
        #expect(bold("«a\n`b»c`") == nil)
    }

    // MARK: Link

    @Test func linkMakesTheSelectionTheTextAndPutsTheCaretInTheURL() {
        #expect(link("a «b c» d") == Marked("a [b c](|) d"))
        #expect(link("a« b »c") == Marked("a [b](|) c"))
    }

    @Test func linkMakesTheWordAtTheCaretTheText() {
        #expect(link("a wo|rd b") == Marked("a [word](|) b"))
    }

    @Test func linkOutsideAWordInsertsAnEmptyLinkWithTheCaretInTheText() {
        #expect(link("a | b") == Marked("a [|]() b"))
        #expect(link("|") == Marked("[|]()"))
    }

    @Test func linkOnAURLMakesItTheURLAndPutsTheCaretInTheText() {
        #expect(link("see «https://example.com/a?b=1»") == Marked("see [|](https://example.com/a?b=1)"))
        #expect(link("see http://exa|mple.com") == Marked("see [|](http://example.com)"))
    }

    @Test func linkInsideALinkLeavesOnlyItsText() {
        #expect(link("a [te|xt](https://x.com) b") == Marked("a te|xt b"))
        #expect(link("a [text](https://x|.com) b") == Marked("a text| b"))
        #expect(link("«[text](https://x.com)»") == Marked("«text»"))
        #expect(link("[**b|old**](u)") == Marked("**b|old**"))
        #expect(link("a [](u|) b") == Marked("a | b"))
    }

    @Test func linkDeclinesInCodeAcrossLinesAndAcrossALinksEdge() {
        #expect(link("```\nco|de\n```") == nil)
        #expect(link("`co|de`") == nil)
        #expect(link("«a\nb»") == nil)
        #expect(link("«a [b»](u)") == nil)
        #expect(link("«a [b](u) c»") == nil)
    }

    @Test func linkOnAHeadingWrapsOnlyItsText() {
        #expect(link("«# Title»") == Marked("# [Title](|)"))
    }
}
