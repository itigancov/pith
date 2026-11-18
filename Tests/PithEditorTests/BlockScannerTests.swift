import Foundation
import Testing
@testable import PithEditor

private struct Scanned {
    let text: String
    let blocks: [Block]

    init(_ text: String) {
        self.text = text
        self.blocks = BlockScanner.scan(text)
    }

    func substring(_ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    func ranges() -> [String] { blocks.map { substring($0.range) } }
    func contents() -> [String] { blocks.map { substring($0.content) } }
    func kinds() -> [BlockKind] { blocks.map(\.kind) }
    func markers(_ index: Int = 0) -> [String] {
        blocks[index].markers.map { substring($0.range) }
    }
    func markerKinds(_ index: Int = 0) -> [SpanKind] {
        blocks[index].markers.map(\.kind)
    }
}

struct BlockScannerTests {
    // MARK: Paragraphs and blank lines

    @Test func everyLineIsABlock() {
        let s = Scanned("one\n\ntwo")
        #expect(s.kinds() == [.paragraph, .blank, .paragraph])
        #expect(s.ranges() == ["one", "", "two"])
        #expect(s.blocks.map(\.range) == [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 0),
            NSRange(location: 5, length: 3),
        ])
    }

    @Test func paragraphContentIsTheWholeLine() {
        let s = Scanned("hello world")
        #expect(s.contents() == ["hello world"])
        #expect(s.markers() == [])
    }

    @Test func whitespaceOnlyLineIsBlank() {
        let s = Scanned("a\n  \t\nb")
        #expect(s.kinds() == [.paragraph, .blank, .paragraph])
    }

    @Test func emptyNoteIsOneBlankBlock() {
        #expect(BlockScanner.scan("") == [Block(kind: .blank, range: NSRange(location: 0, length: 0), content: NSRange(location: 0, length: 0))])
    }

    @Test func trailingNewlineAddsABlankBlock() {
        let s = Scanned("a\n")
        #expect(s.kinds() == [.paragraph, .blank])
        #expect(s.blocks[1].range == NSRange(location: 2, length: 0))
    }

    // MARK: Headings

    @Test func headingLevelsOneToThree() {
        let s = Scanned("# a\n## b\n### c")
        #expect(s.kinds() == [.heading(level: 1), .heading(level: 2), .heading(level: 3)])
        #expect(s.contents() == ["a", "b", "c"])
        #expect(s.markers(0) == ["# "])
        #expect(s.markers(1) == ["## "])
        #expect(s.markers(2) == ["### "])
        #expect(s.markerKinds(0) == [.headingMarker])
        #expect(s.ranges() == ["# a", "## b", "### c"])
    }

    @Test func headingNeedsASpaceAndAtMostThreeHashes() {
        let s = Scanned("#### x\n#x\n####")
        #expect(s.kinds() == [.paragraph, .paragraph, .paragraph])
    }

    @Test func bareHashIsAnEmptyHeading() {
        let s = Scanned("#")
        #expect(s.kinds() == [.heading(level: 1)])
        #expect(s.markers() == ["#"])
        #expect(s.contents() == [""])
        #expect(s.blocks[0].content == NSRange(location: 1, length: 0))
    }

    @Test func headingWithSpaceOnlyHasEmptyContent() {
        let s = Scanned("## ")
        #expect(s.kinds() == [.heading(level: 2)])
        #expect(s.markers() == ["## "])
        #expect(s.blocks[0].content == NSRange(location: 3, length: 0))
    }

    @Test func indentedHashIsAParagraph() {
        #expect(Scanned("  # x").kinds() == [.paragraph])
    }

    // MARK: Bullets and ordered items

    @Test func bulletMarkers() {
        let s = Scanned("- a\n* b\n+ c")
        #expect(s.kinds() == [.bullet(level: 0), .bullet(level: 0), .bullet(level: 0)])
        #expect(s.contents() == ["a", "b", "c"])
        #expect(s.markers(0) == ["- "])
        #expect(s.markers(1) == ["* "])
        #expect(s.markers(2) == ["+ "])
        #expect(s.markerKinds(0) == [.listMarker])
    }

    @Test func loneDashAndRuleStayText() {
        #expect(Scanned("-\n---\n-x").kinds() == [.paragraph, .paragraph, .paragraph])
    }

    @Test func emptyBulletIsStillABullet() {
        let s = Scanned("- ")
        #expect(s.kinds() == [.bullet(level: 0)])
        #expect(s.markers() == ["- "])
        #expect(s.blocks[0].content == NSRange(location: 2, length: 0))
    }

    @Test func orderedItemKeepsItsNumber() {
        let s = Scanned("1. a\n3. b\n42. c")
        #expect(s.kinds() == [
            .ordered(level: 0, number: 1),
            .ordered(level: 0, number: 3),
            .ordered(level: 0, number: 42),
        ])
        #expect(s.markers(2) == ["42. "])
        #expect(s.contents() == ["a", "b", "c"])
    }

    @Test func unsupportedOrderedForms() {
        #expect(Scanned("1) a\n1.a\n1.\n1234567890. a\n. a").kinds() == Array(repeating: .paragraph, count: 5))
    }

    @Test func emptyOrderedItem() {
        let s = Scanned("1. ")
        #expect(s.kinds() == [.ordered(level: 0, number: 1)])
    }

    // MARK: Tasks

    @Test func taskCheckboxStates() {
        let s = Scanned("- [ ] a\n- [x] b\n- [X] c")
        #expect(s.kinds() == [
            .task(level: 0, checked: false),
            .task(level: 0, checked: true),
            .task(level: 0, checked: true),
        ])
        #expect(s.contents() == ["a", "b", "c"])
        #expect(s.markers(0) == ["- ", "[ ]"])
        #expect(s.markers(1) == ["- ", "[x]"])
        #expect(s.markers(2) == ["- ", "[X]"])
        #expect(s.markerKinds(0) == [.listMarker, .taskCheckbox])
    }

    @Test func taskWorksWithEveryBulletMarker() {
        #expect(Scanned("* [ ] a\n+ [x] b").kinds() == [
            .task(level: 0, checked: false),
            .task(level: 0, checked: true),
        ])
    }

    @Test func emptyTaskIsStillATask() {
        let withSpace = Scanned("- [ ] ")
        #expect(withSpace.kinds() == [.task(level: 0, checked: false)])
        #expect(withSpace.blocks[0].content == NSRange(location: 6, length: 0))

        let withoutSpace = Scanned("- [x]")
        #expect(withoutSpace.kinds() == [.task(level: 0, checked: true)])
        #expect(withoutSpace.blocks[0].content == NSRange(location: 5, length: 0))
    }

    @Test func malformedCheckboxMakesAPlainBullet() {
        let s = Scanned("- [] a\n- [y] a\n- [x]a\n- [ ]")
        #expect(s.kinds()[0] == .bullet(level: 0))
        #expect(s.kinds()[1] == .bullet(level: 0))
        #expect(s.kinds()[2] == .bullet(level: 0))
        #expect(s.kinds()[3] == .task(level: 0, checked: false))
        #expect(s.contents()[2] == "[x]a")
    }

    @Test func checkboxAfterOrderedMarkerIsPlainText() {
        let s = Scanned("1. [ ] x")
        #expect(s.kinds() == [.ordered(level: 0, number: 1)])
        #expect(s.contents() == ["[ ] x"])
        #expect(s.markers() == ["1. "])
    }

    // MARK: Nesting

    private func levels(_ text: String) -> [Int] {
        Scanned(text).kinds().map { kind in
            switch kind {
            case .bullet(let level), .ordered(let level, _), .task(let level, _): level
            default: -1
            }
        }
    }

    @Test func indentOfTwoSpacesNests() {
        #expect(levels("- a\n  - b\n    - c") == [0, 1, 2])
    }

    @Test func indentOfFourSpacesNests() {
        #expect(levels("- a\n    - b\n        - c") == [0, 1, 2])
    }

    @Test func mixedIndentsAreResolvedByTheStack() {
        #expect(levels("- a\n    - b") == [0, 1])
        #expect(levels("- a\n  - b\n    - c\n  - d\n- e") == [0, 1, 2, 1, 0])
        #expect(levels("- a\n    - b\n  - c") == [0, 1, 1])
    }

    @Test func nestingMixesItemKinds() {
        let s = Scanned("1. a\n   - b\n     - [ ] c")
        #expect(s.kinds() == [
            .ordered(level: 0, number: 1),
            .bullet(level: 1),
            .task(level: 2, checked: false),
        ])
    }

    @Test func deeperFirstItemStillStartsAtLevelZero() {
        #expect(levels("    - a\n- b") == [0, 0])
    }

    @Test func nonItemLinesResetTheSeries() {
        #expect(levels("- a\n  - b\n\n  - c") == [0, 1, -1, 0])
        #expect(levels("- a\n  - b\ntext\n  - c") == [0, 1, -1, 0])
        #expect(levels("- a\n  - b\n# h\n  - c") == [0, 1, -1, 0])
        #expect(levels("- a\n  - b\n> q\n  - c") == [0, 1, -1, 0])
    }

    @Test func indentedItemMarkerSpanSkipsTheIndent() {
        let s = Scanned("- a\n  - b")
        #expect(s.markers(1) == ["- "])
        #expect(s.ranges()[1] == "  - b")
        #expect(s.contents()[1] == "b")
    }

    // MARK: Quotes

    @Test func quoteHasMarkerAndContent() {
        let s = Scanned("> a")
        #expect(s.kinds() == [.quote])
        #expect(s.markers() == ["> "])
        #expect(s.markerKinds() == [.quoteMarker])
        #expect(s.contents() == ["a"])
    }

    @Test func emptyQuoteIsStillAQuote() {
        let s = Scanned("> ")
        #expect(s.kinds() == [.quote])
        #expect(s.blocks[0].content == NSRange(location: 2, length: 0))
    }

    @Test func unsupportedQuoteForms() {
        #expect(Scanned(">>\n>> a\n>\n>a\n  > a").kinds() == Array(repeating: .paragraph, count: 5))
    }

    @Test func quoteContainsInlineTextOnly() {
        let s = Scanned("> - x\n> # h")
        #expect(s.kinds() == [.quote, .quote])
        #expect(s.contents() == ["- x", "# h"])
    }

    @Test func listItemContainsInlineTextOnly() {
        let s = Scanned("- > x")
        #expect(s.kinds() == [.bullet(level: 0)])
        #expect(s.contents() == ["> x"])
    }

    // MARK: Code blocks

    @Test func codeBlockWithLanguage() {
        let s = Scanned("```swift\nlet a = 1\n```\nafter")
        #expect(s.kinds() == [.codeBlock(language: "swift"), .paragraph])
        #expect(s.ranges() == ["```swift\nlet a = 1\n```", "after"])
        #expect(s.contents()[0] == "let a = 1")
        #expect(s.markers() == ["```", "swift", "let a = 1", "```"])
        #expect(s.markerKinds() == [.fence, .fenceLanguage, .codeContent, .fence])
    }

    @Test func codeBlockWithoutLanguage() {
        let s = Scanned("```\ncode\n```")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.markers() == ["```", "code", "```"])
    }

    @Test func languageIsTheTrimmedRestOfTheFenceLine() {
        let s = Scanned("```  objective c  \nx\n```")
        #expect(s.kinds() == [.codeBlock(language: "objective c")])
        #expect(s.markers() == ["```", "objective c", "x", "```"])
    }

    @Test func emptyCodeBlock() {
        let s = Scanned("```\n```")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.blocks[0].content == NSRange(location: 4, length: 0))
        #expect(s.markers() == ["```", "```"])
    }

    @Test func unclosedCodeBlockRunsToTheEndOfTheNote() {
        let s = Scanned("```\na\n# b")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.ranges() == ["```\na\n# b"])
        #expect(s.contents() == ["a\n# b"])
        #expect(s.markers() == ["```", "a\n# b"])
    }

    @Test func unclosedCodeBlockOwnsTheTrailingEmptyLine() {
        let s = Scanned("```\nx\n")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.ranges() == ["```\nx\n"])
    }

    @Test func unclosedBareFence() {
        let s = Scanned("```")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.blocks[0].content == NSRange(location: 3, length: 0))
        #expect(s.markers() == ["```"])
    }

    @Test func linesInsideACodeBlockAreNotRecognized() {
        let s = Scanned("```\n# h\n- x\n> q\n1. n\n- [ ] t\n```")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.contents() == ["# h\n- x\n> q\n1. n\n- [ ] t"])
    }

    @Test func fenceMayBeIndented() {
        let s = Scanned("- a\n  ```sh\n  ls\n  ```")
        #expect(s.kinds() == [.bullet(level: 0), .codeBlock(language: "sh")])
        #expect(s.ranges()[1] == "  ```sh\n  ls\n  ```")
        #expect(s.markers(1) == ["```", "sh", "  ls", "```"])
    }

    @Test func closingFenceNeedsAtLeastAsManyBackticks() {
        let s = Scanned("````\n```\ncode\n```\n`````")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.contents() == ["```\ncode\n```"])
    }

    @Test func closingFenceMayHaveSurroundingSpaces() {
        let s = Scanned("```\nx\n  ```  \ny")
        #expect(s.kinds() == [.codeBlock(language: nil), .paragraph])
        #expect(s.ranges()[0] == "```\nx\n  ```  ")
    }

    @Test func fenceLineWithTextIsNotAClosingFence() {
        let s = Scanned("```\nx\n``` y\n```")
        #expect(s.kinds() == [.codeBlock(language: nil)])
        #expect(s.contents() == ["x\n``` y"])
    }

    @Test func codeBlockEndsAListSeries() {
        let s = Scanned("- a\n  - b\n```\nx\n```\n  - c")
        #expect(s.kinds() == [
            .bullet(level: 0), .bullet(level: 1), .codeBlock(language: nil), .bullet(level: 0),
        ])
    }

    @Test func unsupportedFenceForms() {
        #expect(Scanned("``\n~~~\n```a```").kinds() == Array(repeating: .paragraph, count: 3))
    }

    @Test func blocksAfterACodeBlockAreScannedNormally() {
        let s = Scanned("```\nx\n```\n# h\n")
        #expect(s.kinds() == [.codeBlock(language: nil), .heading(level: 1), .blank])
    }

    @Test func indentedLineWithoutMarkerIsNotCode() {
        let s = Scanned("    code")
        #expect(s.kinds() == [.paragraph])
    }

    // MARK: Line endings, tabs, UTF-16

    @Test func lineEndingsAreEquivalent() {
        let lf = Scanned("# a\n- b\n> c").kinds()
        #expect(Scanned("# a\r\n- b\r\n> c").kinds() == lf)
        #expect(Scanned("# a\r- b\r> c").kinds() == lf)
    }

    @Test func lineBreaksAreNotPartOfRangeOrContent() {
        let s = Scanned("a\r\nb\rc")
        #expect(s.ranges() == ["a", "b", "c"])
        #expect(s.blocks.map(\.range.location) == [0, 3, 5])
    }

    @Test func crLfInsideCodeBlock() {
        let s = Scanned("```\r\nx\r\ny\r\n```\r\nz")
        #expect(s.kinds() == [.codeBlock(language: nil), .paragraph])
        #expect(s.contents()[0] == "x\r\ny")
    }

    @Test func tabIndentCountsAsFourSpaces() {
        #expect(levels("- a\n\t- b\n\t\t- c") == [0, 1, 2])
        #expect(levels("- a\n    - b\n\t- c") == [0, 1, 1])
    }

    @Test func rangesAreUTF16() {
        let s = Scanned("# Привет 👋\n- мир 🌍")
        #expect(s.ranges() == ["# Привет 👋", "- мир 🌍"])
        #expect(s.contents() == ["Привет 👋", "мир 🌍"])
        #expect(s.blocks[0].range == NSRange(location: 0, length: 11))
        #expect(s.blocks[1].range == NSRange(location: 12, length: 8))
    }

    @Test func codeBlockLanguageIsDecodedFromUTF16() {
        let s = Scanned("```язык🙂\nx\n```")
        #expect(s.kinds() == [.codeBlock(language: "язык🙂")])
    }

    @Test func scanningFiveThousandLinesIsFast() {
        let note = (0..<5000).map { i in
            switch i % 5 {
            case 0: "# Heading \(i)"
            case 1: "- item \(i) with **bold** text"
            case 2: "  - [ ] nested task \(i)"
            case 3: "> quote \(i)"
            default: "plain paragraph \(i)"
            }
        }.joined(separator: "\n")

        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = BlockScanner.scan(note) }
        #expect(BlockScanner.scan(note).count == 5000)
        #expect(elapsed < .milliseconds(200))
    }
}
