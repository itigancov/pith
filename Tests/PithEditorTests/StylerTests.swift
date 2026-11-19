import AppKit
import Testing
@testable import PithEditor

/// A text storage with a `Styler` attached, queried by substring.
@MainActor
private final class Styled {
    let storage = NSTextStorage()
    let styler = Styler()

    init(_ text: String) {
        styler.attach(to: storage)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
    }

    var text: String { storage.string }

    /// The `occurrence`-th match of `substring`, counting from 0.
    func range(_ substring: String, _ occurrence: Int = 0) -> NSRange {
        let ns = text as NSString
        var search = NSRange(location: 0, length: ns.length)
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            found = ns.range(of: substring, range: search)
            precondition(found.location != NSNotFound, "no \(substring) in \(text)")
            search = NSRange(location: found.upperBound, length: ns.length - found.upperBound)
        }
        return found
    }

    func replace(_ substring: String, _ occurrence: Int = 0, with replacement: String) {
        storage.replaceCharacters(in: range(substring, occurrence), with: replacement)
    }

    func insert(_ string: String, at location: Int) {
        storage.replaceCharacters(in: NSRange(location: location, length: 0), with: string)
    }

    /// Attribute values at every character of the match; `nil` if they differ across it.
    private func uniform<T: Equatable>(_ key: NSAttributedString.Key, _ substring: String, _ occurrence: Int, as: T.Type) -> T?? {
        let r = range(substring, occurrence)
        let values = (r.location..<r.upperBound).map { storage.attribute(key, at: $0, effectiveRange: nil) as? T }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return .some(first)
    }

    func font(_ substring: String, _ occurrence: Int = 0) -> NSFont? {
        uniform(.font, substring, occurrence, as: NSFont.self) ?? nil
    }

    func traits(_ substring: String, _ occurrence: Int = 0) -> NSFontDescriptor.SymbolicTraits? {
        font(substring, occurrence)?.fontDescriptor.symbolicTraits
    }

    func color(_ substring: String, _ occurrence: Int = 0) -> NSColor? {
        uniform(.foregroundColor, substring, occurrence, as: NSColor.self) ?? nil
    }

    /// The kinds of the plates behind every character of the match, outer first; `nil` if they differ across it.
    func plates(_ substring: String, _ occurrence: Int = 0) -> [PlateKind]? {
        uniform(.pithBackground, substring, occurrence, as: PlateStack.self).map { $0?.kinds ?? [] }
    }

    /// The longest run of one `.pithBackground` value around `location`, and the kinds in it.
    func plateRun(at location: Int) -> (range: NSRange, kinds: [PlateKind]) {
        var range = NSRange()
        let stack = storage.attribute(.pithBackground, at: location, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
        return (range, (stack as? PlateStack)?.kinds ?? [])
    }

    func isStruck(_ substring: String, _ occurrence: Int = 0) -> Bool {
        (uniform(.strikethroughStyle, substring, occurrence, as: Int.self) ?? nil) == NSUnderlineStyle.single.rawValue
    }

    func paragraph(at location: Int) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    func paragraph(_ substring: String, _ occurrence: Int = 0) -> NSParagraphStyle? {
        paragraph(at: range(substring, occurrence).location)
    }

    /// Text of the Blocks restyled by the last edit.
    var restyled: [String] { styler.restyledRanges.map { (text as NSString).substring(with: $0) } }
}

@MainActor private var text: NSFont { .systemFont(ofSize: 14) }
@MainActor private var bold: NSFont { .systemFont(ofSize: 14, weight: .bold) }
@MainActor private var mono: NSFont { .monospacedSystemFont(ofSize: 13, weight: .regular) }

@MainActor
struct StylerTests {
    // MARK: Syntax

    @Test func strongTextIsBoldAndItsMarkersAreSecondaryMono() {
        let s = Styled("a **b** c")
        #expect(s.font("a ") == text)
        #expect(s.font("b") == bold)
        #expect(s.font("**", 0) == mono)
        #expect(s.font("**", 1) == mono)
        #expect(s.color("**") == .secondaryLabelColor)
        #expect(s.color("b") == .labelColor)
    }

    @Test func underscoreStrongIsBold() {
        let s = Styled("__b__")
        #expect(s.font("b") == bold)
        #expect(s.font("__") == mono)
    }

    @Test func emphasisIsItalic() {
        let s = Styled("*a* _b_")
        #expect(s.traits("a")?.contains(.italic) == true)
        #expect(s.traits("b")?.contains(.italic) == true)
        #expect(s.font("_") == mono)
    }

    @Test func nestedEmphasisAndStrong() {
        let s = Styled("***x*** **a *b***")
        #expect(s.traits("x")?.isSuperset(of: [.bold, .italic]) == true)
        #expect(s.font("***") == mono)
        #expect(s.font("a ") == bold)
        #expect(s.traits("b")?.isSuperset(of: [.bold, .italic]) == true)
    }

    @Test func strikethroughStrikesTheTextButNotItsMarkers() {
        let s = Styled("~~x~~")
        #expect(s.isStruck("x"))
        #expect(!s.isStruck("~~"))
        #expect(s.font("~~") == mono)
    }

    @Test func highlightPlateCoversItsMarkers() {
        let s = Styled("a ==x== b")
        #expect(s.plates("==x==") == [.highlight])
        #expect(s.plates("a ") == [])
        #expect(s.plates(" b") == [])
        #expect(s.font("==") == mono)
    }

    @Test func codeIsMonoOnAnInlineCodePlateWithItsBackticks() {
        let s = Styled("a `x` b")
        #expect(s.plates("`x`") == [.inlineCode])
        #expect(s.font("x") == mono)
        #expect(s.color("`") == .secondaryLabelColor)
        #expect(s.color("x") == .labelColor)
    }

    @Test func codeInsideStrongIsMonoBold() {
        let s = Styled("**`x`**")
        #expect(s.font("x") == .monospacedSystemFont(ofSize: 13, weight: .bold))
        #expect(s.font("`") == mono)
    }

    @Test func linkHasSecondaryBracketsPlainTextAndBlueURL() {
        let s = Styled("[text](https://a.b)")
        #expect(s.color("[") == .secondaryLabelColor)
        #expect(s.color("](") == .secondaryLabelColor)
        #expect(s.color(")") == .secondaryLabelColor)
        #expect(s.color("text") == .labelColor)
        #expect(s.font("text") == text)
        #expect(s.color("https://a.b") == .linkColor)
        #expect(s.storage.attribute(.link, at: s.range("text").location, effectiveRange: nil) == nil)
    }

    @Test func bareURLIsBlue() {
        let s = Styled("see https://a.b now")
        #expect(s.color("https://a.b") == .linkColor)
        #expect(s.color("see ") == .labelColor)
    }

    @Test func escapeBackslashIsAMarker() {
        let s = Styled(#"\*a"#)
        #expect(s.font(#"\"#) == mono)
        #expect(s.font("*") == text)
    }

    @Test func headingIsBoldWithAMonoMarker() {
        let s = Styled("# One\n## Two\n### Three")
        #expect(s.font("One") == bold)
        #expect(s.font("Two") == bold)
        #expect(s.font("Three") == bold)
        #expect(s.font("# ") == mono)
        #expect(s.color("### ") == .secondaryLabelColor)
    }

    @Test func listQuoteAndTaskMarkersAreSecondaryMono() {
        let s = Styled("- a\n1. b\n- [ ] c\n> d")
        for marker in ["- ", "1. ", "[ ]", "> "] {
            #expect(s.font(marker) == mono)
            #expect(s.color(marker) == .secondaryLabelColor)
        }
        #expect(s.font("a") == text)
    }

    @Test func checkedTaskTextIsSecondaryWithoutStrikethrough() {
        let s = Styled("- [x] done\n- [ ] todo")
        #expect(s.color("done") == .secondaryLabelColor)
        #expect(!s.isStruck("done"))
        #expect(s.color("todo") == .labelColor)
    }

    @Test func codeBlockBodyIsMonoAndFencesAreSecondary() {
        let s = Styled("```swift\nlet **x** = 1\n```\nafter")
        #expect(s.color("```", 0) == .secondaryLabelColor)
        #expect(s.color("swift") == .secondaryLabelColor)
        #expect(s.font("swift") == mono)
        #expect(s.font("```", 1) == mono)
        #expect(s.font("let **x** = 1") == mono)
        #expect(s.color("let **x** = 1") == .labelColor)
        #expect(s.font("after") == text)
    }

    @Test func codeBlockIsOneRunOfItsPlateFromTheOpeningFenceToTheEndOfTheClosingOne() {
        let s = Styled("a\n```swift\nlet `x` = 1\n\n  \n```\nafter")
        let run = s.plateRun(at: s.range("```").location)
        #expect(run.kinds == [.codeBlock])
        #expect(run.range == NSRange(location: s.range("```", 0).location, length: s.range("```", 1).upperBound - s.range("```", 0).location))
        #expect(s.plates("a\n") == [])
        #expect(s.plates("\nafter") == [])
    }

    @Test func fenceLinesHavePaddingSpacingAndTheBodyHasNone() {
        let s = Styled("a\n```swift\nb\n```\nc")
        #expect(s.paragraph("a")?.paragraphSpacing == 0)
        #expect(s.paragraph("```swift")?.paragraphSpacingBefore == 4)
        #expect(s.paragraph("```swift")?.paragraphSpacing == 0)
        #expect(s.paragraph("b")?.paragraphSpacingBefore == 0)
        #expect(s.paragraph("b")?.paragraphSpacing == 0)
        let closing = s.range("```", 1)
        for location in closing.location...closing.upperBound {
            #expect(s.paragraph(at: location)?.paragraphSpacingBefore == 0)
            #expect(s.paragraph(at: location)?.paragraphSpacing == 4)
        }
        #expect(s.paragraph("c")?.paragraphSpacingBefore == 0)
    }

    @Test func emptyCodeBlockIsOnAPlateWithPaddingOnBothFences() {
        let s = Styled("```\n```")
        #expect(s.plates("```\n```") == [.codeBlock])
        #expect(s.paragraph(at: 0)?.paragraphSpacingBefore == 4)
        #expect(s.paragraph(at: 4)?.paragraphSpacing == 4)
    }

    @Test func unclosedCodeBlockRunsToTheEndOfTheNoteWithoutBottomPadding() {
        let s = Styled("```\na\n# b")
        #expect(s.font("# b") == mono)
        #expect(s.plateRun(at: 0) == (NSRange(location: 0, length: s.text.utf16.count), [.codeBlock]))
        #expect(s.paragraph(at: 0)?.paragraphSpacingBefore == 4)
        #expect(s.paragraph("# b")?.paragraphSpacing == 0)
    }

    @Test func removingAFenceRemovesThePlateAndThePadding() {
        let s = Styled("```\na\n```\nb")
        s.replace("```", 1, with: "")
        #expect(s.plateRun(at: 0) == (NSRange(location: 0, length: s.text.utf16.count), [.codeBlock]))
        #expect(s.paragraph("b")?.paragraphSpacing == 0)
        s.replace("```", 0, with: "")
        #expect(s.text == "\na\n\nb")
        #expect(s.plates(s.text) == [])
        for location in 0..<s.text.utf16.count {
            #expect(s.paragraph(at: location)?.paragraphSpacingBefore == 0)
            #expect(s.paragraph(at: location)?.paragraphSpacing == 0)
        }
    }

    @Test func loneStarIsTextUntilItGetsAPair() {
        let s = Styled("a *b")
        #expect(s.font("*") == text)
        #expect(s.color("*") == .labelColor)
        s.insert("*", at: s.text.utf16.count)
        #expect(s.font("*", 0) == mono)
        #expect(s.font("*", 1) == mono)
        #expect(s.traits("b")?.contains(.italic) == true)
    }

    @Test func cyrillicAndEmoji() {
        let s = Styled("привет 👋 **жир 🎉** и `код`")
        #expect(s.font("жир 🎉") == bold)
        #expect(s.font("привет 👋 ") == text)
        #expect(s.font("код") == mono)
    }

    // MARK: Paragraph style

    @Test func everyBlockHasTheLineHeightMultipleThroughItsLineBreak() {
        let s = Styled("# a\nb\n- c")
        for location in 0..<s.storage.length {
            #expect(s.paragraph(at: location)?.lineHeightMultiple == 1.25)
        }
    }

    @Test func listTaskAndQuoteHangTheirWrappedLinesAfterTheMarker() {
        let s = Styled("- a\n1. b\n- [ ] c\n> d\ne")
        for content in ["a", "b", "c", "d"] {
            let paragraph = s.paragraph(content)
            #expect(paragraph?.firstLineHeadIndent == 0)
            #expect((paragraph?.headIndent ?? 0) > 0, "\(content)")
        }
        #expect(s.paragraph("1. b")!.headIndent > s.paragraph("- a")!.headIndent)
        #expect(s.paragraph("- [ ] c")!.headIndent > s.paragraph("- a")!.headIndent)
        // The line break belongs to the Block's paragraph.
        #expect(s.paragraph(at: s.range("a").upperBound)?.headIndent == s.paragraph("a")?.headIndent)
        #expect(s.paragraph("e")?.headIndent == 0)
    }

    @Test func headIndentIsTheWidthOfTheStyledPrefix() {
        let s = Styled("- a")
        let prefix = NSAttributedString(string: "- ", attributes: [.font: mono])
        #expect(abs(s.paragraph("a")!.headIndent - prefix.size().width) < 0.01)
    }

    @Test func nestedItemHangsDeeper() {
        let s = Styled("- a\n  - b\n    - c")
        let a = s.paragraph("a")!.headIndent
        let b = s.paragraph("b")!.headIndent
        let c = s.paragraph("c")!.headIndent
        #expect(a < b && b < c)
    }

    @Test func otherBlocksHaveNoIndent() {
        let s = Styled("# a\nb\n```\nc\n```")
        for content in ["a", "b", "c"] {
            #expect(s.paragraph(content)?.headIndent == 0)
        }
    }

    // MARK: Incremental restyling

    @Test func attachingStylesTheWholeNote() {
        let storage = NSTextStorage(string: "# a\n**b**")
        let styler = Styler()
        styler.attach(to: storage)
        #expect(styler.restyledRanges.count == 2)
        #expect(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont == bold)
    }

    @Test func typingInAParagraphRestylesOnlyThatBlock() {
        let s = Styled("one\ntwo\nthree")
        s.insert("*", at: s.range("two").location)
        #expect(s.restyled == ["*two"])
        s.insert("*", at: s.range("two").upperBound)
        #expect(s.restyled == ["*two*"])
        #expect(s.traits("two")?.contains(.italic) == true)
    }

    @Test func editsAtTheStartAndTheEndOfTheNote() {
        let s = Styled("one\ntwo")
        s.insert("# ", at: 0)
        #expect(s.restyled == ["# one"])
        #expect(s.font("one") == bold)
        s.insert("!", at: s.storage.length)
        #expect(s.restyled == ["two!"])
    }

    @Test func changingTheBlockKindRestylesIt() {
        let s = Styled("a\nb\nc")
        s.insert("- ", at: s.range("b").location)
        #expect(s.restyled == ["- b"])
        #expect(s.font("- ") == mono)
        #expect(s.paragraph("b")!.headIndent > 0)
        s.replace("- ", with: "")
        #expect(s.restyled == ["b"])
        #expect(s.font("b") == text)
        #expect(s.paragraph("b")?.headIndent == 0)
    }

    @Test func attributeOnlyEditsAreIgnored() {
        let s = Styled("a\n**b**")
        s.insert("x", at: 0)
        s.storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 1))
        #expect(s.restyled == ["xa"])
    }

    @Test func openingAFenceRestylesTheTail() {
        let s = Styled("a\n**b**\nc")
        s.insert("```\n", at: 0)
        #expect(s.restyled == ["```\na\n**b**\nc"])
        #expect(s.font("**b**") == mono)
        #expect(s.plates("**b**") == [.codeBlock])
    }

    @Test func closingAFenceRestylesTheTail() {
        let s = Styled("```\na\n**b**\nc")
        s.insert("```\n", at: s.range("**b**").location)
        #expect(s.restyled == ["```\na\n```", "**b**", "c"])
        #expect(s.font("b") == bold)
        #expect(s.plates("**b**") == [])
    }

    @Test func insertingSeveralLinesRestylesOnlyThem() {
        let s = Styled("one\ntwo\nthree")
        s.insert("x\n# y\n", at: s.range("two").location)
        #expect(s.restyled == ["x", "# y"])
        #expect(s.font("y") == bold)
        #expect(s.font("three") == text)
    }

    @Test func deletingSeveralLinesRestylesTheJoinedBlock() {
        let s = Styled("one\n# two\n- three\nfour")
        s.replace("e\n# two\n- th", with: "")
        #expect(s.restyled == ["onree"])
        #expect(s.font("onree") == text)
        #expect(s.paragraph("onree")?.headIndent == 0)
        #expect(s.restyled.count == 1)
    }

    @Test func undoneEditGetsTheRightStyleBack() {
        let s = Styled("a **b** c")
        s.replace("**", 1, with: "")
        #expect(s.font("**") == text)
        s.insert("**", at: s.range("b").upperBound)
        #expect(s.font("b") == bold)
        #expect(s.font("**", 1) == mono)
    }

    @Test func replacingTheWholeTextRestylesEverything() {
        let s = Styled("a\nb")
        s.storage.replaceCharacters(in: NSRange(location: 0, length: s.storage.length), with: "# x\ny\nz")
        #expect(s.restyled == ["# x", "y", "z"])
    }

    @Test func emptyNote() {
        let s = Styled("")
        #expect(s.storage.length == 0)
        s.insert("**a**", at: 0)
        #expect(s.font("a") == bold)
    }
}
