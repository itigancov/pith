import Foundation
import Testing
@testable import PithEditor

private struct Parsed {
    let text: String
    let spans: [Span]

    /// Parses `text` as the content of one Block, or only its `content` part.
    init(_ text: String, in content: NSRange? = nil) {
        self.text = text
        self.spans = InlineParser.parse(text, in: content ?? NSRange(location: 0, length: (text as NSString).length))
    }

    func substring(_ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    /// Every Span as "substring → kind", in result order.
    func pairs() -> [Pair] { spans.map { Pair(substring($0.range), $0.kind) } }
    /// Substrings of the Spans of one kind, in result order.
    func strings(_ kind: SpanKind) -> [String] {
        spans.filter { $0.kind == kind }.map { substring($0.range) }
    }
}

private struct Pair: Equatable, CustomStringConvertible {
    let string: String
    let kind: SpanKind

    init(_ string: String, _ kind: SpanKind) {
        self.string = string
        self.kind = kind
    }

    var description: String { "\(string) → \(kind)" }
}

struct InlineParserTests {
    // MARK: Plain text

    @Test func emptyContentHasNoSpans() {
        #expect(Parsed("").spans == [])
    }

    @Test func plainTextHasNoSpans() {
        #expect(Parsed("just some words").spans == [])
    }

    // MARK: Code spans

    @Test func codeSpanCoversItsBackticks() {
        let p = Parsed("a `x` b")
        #expect(p.pairs() == [Pair("`x`", .code), Pair("`", .inlineMarker), Pair("`", .inlineMarker)])
    }

    @Test func longerRunClosesOnlyAtARunOfTheSameLength() {
        let p = Parsed("``a`b`` c")
        #expect(p.strings(.code) == ["``a`b``"])
        #expect(p.strings(.inlineMarker) == ["``", "``"])
    }

    @Test func codeSpanKeepsSurroundingSpaces() {
        #expect(Parsed("` a `").strings(.code) == ["` a `"])
    }

    @Test func unclosedBacktickRunIsText() {
        #expect(Parsed("a `b").spans == [])
        #expect(Parsed("``a`").spans == [])
    }

    @Test func unclosedRunDoesNotHideALaterCodeSpan() {
        #expect(Parsed("``a `b`").strings(.code) == ["`b`"])
    }

    // MARK: Emphasis

    @Test func starsAndUnderscoresMakeEmphasis() {
        #expect(Parsed("a *x* b").pairs() == [Pair("*x*", .emphasis), Pair("*", .inlineMarker), Pair("*", .inlineMarker)])
        #expect(Parsed("a _x_ b").pairs() == [Pair("_x_", .emphasis), Pair("_", .inlineMarker), Pair("_", .inlineMarker)])
    }

    @Test func doubledStarsAndUnderscoresMakeStrong() {
        #expect(Parsed("**x**").pairs() == [Pair("**x**", .strong), Pair("**", .inlineMarker), Pair("**", .inlineMarker)])
        #expect(Parsed("__x__").pairs() == [Pair("__x__", .strong), Pair("__", .inlineMarker), Pair("__", .inlineMarker)])
    }

    @Test func codeIsOpaqueToEmphasis() {
        #expect(Parsed("`**x**`").strings(.strong) == [])
    }

    @Test func starInsideCodeDoesNotCloseEmphasis() {
        let p = Parsed("*a`*`b*")
        #expect(p.strings(.emphasis) == ["*a`*`b*"])
        #expect(p.strings(.code) == ["`*`"])
    }

    @Test func markersSurroundedBySpacesAreText() {
        #expect(Parsed("a * b * c").spans == [])
        #expect(Parsed("a ** b ** c").spans == [])
    }

    @Test func underscoreInsideAWordIsText() {
        #expect(Parsed("snake_case_name").spans == [])
        #expect(Parsed("__init__ method").strings(.strong) == ["__init__"])
    }

    @Test func starWorksInsideAWord() {
        #expect(Parsed("a*b*c").strings(.emphasis) == ["*b*"])
        #expect(Parsed("пол**слова**").strings(.strong) == ["**слова**"])
    }

    @Test func underscoreNextToPunctuationStillMarks() {
        #expect(Parsed("(_x_)").strings(.emphasis) == ["_x_"])
        #expect(Parsed("«_слово_»").strings(.emphasis) == ["_слово_"])
    }

    @Test func tripleStarsAreEmphasisAroundStrong() {
        #expect(Parsed("***x***").pairs() == [
            Pair("***x***", .emphasis), Pair("*", .inlineMarker),
            Pair("**x**", .strong), Pair("**", .inlineMarker),
            Pair("**", .inlineMarker), Pair("*", .inlineMarker),
        ])
    }

    @Test func emphasisNests() {
        let p = Parsed("**a *b* c**")
        #expect(p.strings(.strong) == ["**a *b* c**"])
        #expect(p.strings(.emphasis) == ["*b*"])
        #expect(p.strings(.inlineMarker) == ["**", "*", "*", "**"])
    }

    @Test func unclosedMarkerIsText() {
        #expect(Parsed("**abc").spans == [])
        #expect(Parsed("_abc").spans == [])
    }

    @Test func unpairedMarkersFollowCommonMark() {
        let p = Parsed("**a*")
        #expect(p.pairs() == [Pair("*a*", .emphasis), Pair("*", .inlineMarker), Pair("*", .inlineMarker)])
        #expect(Parsed("*a**").strings(.emphasis) == ["*a*"])
    }

    @Test func ruleOfThreeKeepsRunsApart() {
        // CommonMark: `*foo**bar**baz*` is emphasis around strong.
        let p = Parsed("*foo**bar**baz*")
        #expect(p.strings(.emphasis) == ["*foo**bar**baz*"])
        #expect(p.strings(.strong) == ["**bar**"])
    }

    @Test func differentCharactersDoNotPair() {
        #expect(Parsed("*a_").spans == [])
        #expect(Parsed("**a__").spans == [])
    }

    // MARK: Strikethrough and highlight

    @Test func doubledTildesMakeStrikethrough() {
        #expect(Parsed("~~x~~").pairs() == [Pair("~~x~~", .strikethrough), Pair("~~", .inlineMarker), Pair("~~", .inlineMarker)])
    }

    @Test func doubledEqualsMakeHighlight() {
        #expect(Parsed("==x==").pairs() == [Pair("==x==", .highlight), Pair("==", .inlineMarker), Pair("==", .inlineMarker)])
    }

    @Test func runsOtherThanTwoAreText() {
        #expect(Parsed("~x~ =x= ~~~x~~~ ===x===").spans == [])
        #expect(Parsed("~~x~~~").spans == [])
    }

    @Test func strikethroughAndHighlightFollowFlanking() {
        #expect(Parsed("a == b == c").spans == [])
        #expect(Parsed("a==b==c").strings(.highlight) == ["==b=="])
    }

    @Test func anyInlineNestsInAnother() {
        let p = Parsed("**a ==b==**")
        #expect(p.strings(.strong) == ["**a ==b==**"])
        #expect(p.strings(.highlight) == ["==b=="])
        let q = Parsed("~~a **b** `c`~~")
        #expect(q.strings(.strikethrough) == ["~~a **b** `c`~~"])
        #expect(q.strings(.strong) == ["**b**"])
        #expect(q.strings(.code) == ["`c`"])
    }

    // MARK: Escapes

    @Test func escapedPunctuationIsLiteral() {
        #expect(Parsed(#"\*a\*"#).pairs() == [Pair(#"\"#, .inlineMarker), Pair(#"\"#, .inlineMarker)])
        #expect(Parsed(#"\_a_"#).strings(.emphasis) == [])
        #expect(Parsed(#"\`a`"#).strings(.code) == [])
    }

    @Test func escapedStarLeavesTheRestOfTheRun() {
        #expect(Parsed(#"\**a*"#).strings(.emphasis) == ["*a*"])
    }

    @Test func escapedBackslashIsLiteral() {
        #expect(Parsed(#"\\*a*"#).pairs() == [
            Pair(#"\"#, .inlineMarker), Pair("*a*", .emphasis), Pair("*", .inlineMarker), Pair("*", .inlineMarker),
        ])
    }

    @Test func backslashBeforeOtherCharactersIsText() {
        #expect(Parsed(#"\a \ж \ \1"#).spans == [])
        #expect(Parsed(#"a\"#).spans == [])
    }

    @Test func codeHasNoEscapes() {
        let p = Parsed(#"`a\`b`"#)
        #expect(p.strings(.code) == [#"`a\`"#])
        #expect(p.strings(.inlineMarker) == ["`", "`"])
    }

    @Test func escapedBracketIsNotALink() {
        #expect(Parsed(#"\[a](u)"#).pairs() == [Pair(#"\"#, .inlineMarker)])
        #expect(Parsed(#"[a\](u)"#).pairs() == [Pair(#"\"#, .inlineMarker)])
    }

    // MARK: Links

    @Test func linkHasBracketsTextAndURL() {
        #expect(Parsed("see [text](url) now").pairs() == [
            Pair("[text](url)", .link), Pair("[", .inlineMarker), Pair("text", .linkText),
            Pair("](", .inlineMarker), Pair("url", .url), Pair(")", .inlineMarker),
        ])
    }

    @Test func linkTextIsParsedFully() {
        let p = Parsed("[**a** ~~b~~ ==c== `d` \\*](u)")
        #expect(p.strings(.linkText) == ["**a** ~~b~~ ==c== `d` \\*"])
        #expect(p.strings(.strong) == ["**a**"])
        #expect(p.strings(.strikethrough) == ["~~b~~"])
        #expect(p.strings(.highlight) == ["==c=="])
        #expect(p.strings(.code) == ["`d`"])
        #expect(p.strings(.inlineMarker) == ["[", "**", "**", "~~", "~~", "==", "==", "`", "`", "\\", "](", ")"])
    }

    @Test func urlIsEverythingInTheParentheses() {
        #expect(Parsed("[a](тест)").strings(.url) == ["тест"])
        #expect(Parsed("[a](example.com)").strings(.url) == ["example.com"])
    }

    @Test func whitespaceInTheParenthesesMakesText() {
        #expect(Parsed("[x](a b)").spans == [])
        #expect(Parsed("[x](a\tb)").spans == [])
        #expect(Parsed("[x]( a)").spans == [])
        #expect(Parsed("[x](a )").spans == [])
    }

    @Test func textOfAFailedLinkIsParsed() {
        #expect(Parsed("[**a**](b c)").pairs() == [
            Pair("**a**", .strong), Pair("**", .inlineMarker), Pair("**", .inlineMarker),
        ])
        #expect(Parsed("[https://a](b c)").pairs() == [Pair("https://a", .url)])
        #expect(Parsed("[x](https://a b)").pairs() == [Pair("https://a", .url)])
    }

    @Test func aLinkAfterAFailedOneIsParsed() {
        let p = Parsed("[x](a b) [y](c)")
        #expect(p.strings(.link) == ["[y](c)"])
        #expect(p.strings(.url) == ["c"])
    }

    @Test func balancedParenthesesStayInTheURL() {
        let p = Parsed("[a](https://en.wikipedia.org/wiki/Foo_(bar)) b)")
        #expect(p.strings(.url) == ["https://en.wikipedia.org/wiki/Foo_(bar)"])
        #expect(p.strings(.link) == ["[a](https://en.wikipedia.org/wiki/Foo_(bar))"])
    }

    @Test func urlIsOpaque() {
        #expect(Parsed("[a](x_y_z)").strings(.emphasis) == [])
        #expect(Parsed("[a](a*b*c)").strings(.emphasis) == [])
        #expect(Parsed("[a](a**b**c)").strings(.strong) == [])
        #expect(Parsed(#"[a](x\*y)"#).strings(.inlineMarker) == ["[", "](", ")"])
    }

    @Test func emptyTextAndURLStillMakeALink() {
        #expect(Parsed("[]()").pairs() == [
            Pair("[]()", .link), Pair("[", .inlineMarker), Pair("](", .inlineMarker), Pair(")", .inlineMarker),
        ])
        #expect(Parsed("[](u)").strings(.url) == ["u"])
        #expect(Parsed("[](u)").strings(.linkText) == [])
        #expect(Parsed("[a]()").strings(.linkText) == ["a"])
        #expect(Parsed("[a]()").strings(.url) == [])
    }

    @Test func bracketsWithoutParenthesesAreText() {
        #expect(Parsed("[a]").spans == [])
        #expect(Parsed("[a] (u)").spans == [])
        #expect(Parsed("[a](u").spans == [])
        #expect(Parsed("a](u)").spans == [])
    }

    @Test func emphasisDoesNotPairAcrossALinkBoundary() {
        let p = Parsed("*a [b* c](u)")
        #expect(p.strings(.link) == ["[b* c](u)"])
        #expect(p.strings(.emphasis) == [])
        #expect(Parsed("[*a](u)*").strings(.emphasis) == [])
    }

    @Test func emphasisMayWrapALink() {
        let p = Parsed("**see [a](u)**")
        #expect(p.strings(.strong) == ["**see [a](u)**"])
        #expect(p.strings(.link) == ["[a](u)"])
    }

    @Test func linksDoNotNest() {
        let p = Parsed("[a [b](u) c](v)")
        #expect(p.strings(.link) == ["[b](u)"])
    }

    @Test func innerBracketsInLinkText() {
        #expect(Parsed("[a [b] c](u)").strings(.linkText) == ["a [b] c"])
    }

    @Test func codeSpanWinsOverALink() {
        let p = Parsed("[a`](u)`")
        #expect(p.strings(.link) == [])
        #expect(p.strings(.code) == ["`](u)`"])
    }

    // MARK: Bare URLs

    @Test func httpAndHttpsURLsAreRecognized() {
        #expect(Parsed("go to https://x.com now").pairs() == [Pair("https://x.com", .url)])
        #expect(Parsed("http://x.com").strings(.url) == ["http://x.com"])
        #expect(Parsed("HTTPS://X.com/a?b=c#d").strings(.url) == ["HTTPS://X.com/a?b=c#d"])
    }

    @Test func trailingPunctuationIsNotPartOfTheURL() {
        #expect(Parsed("see https://x.com.").strings(.url) == ["https://x.com"])
        #expect(Parsed("https://x.com/a, b").strings(.url) == ["https://x.com/a"])
        #expect(Parsed("https://x.com?!'\"").strings(.url) == ["https://x.com"])
    }

    @Test func unpairedClosingParenthesisIsCutOff() {
        #expect(Parsed("(см. https://x.com)").strings(.url) == ["https://x.com"])
        #expect(Parsed("https://x.com/Foo_(bar)").strings(.url) == ["https://x.com/Foo_(bar)"])
        #expect(Parsed("(https://x.com/Foo_(bar)).").strings(.url) == ["https://x.com/Foo_(bar)"])
    }

    @Test func otherAddressesAreText() {
        #expect(Parsed("example.com www.x.com me@x.com ftp://x.com").spans == [])
        #expect(Parsed("https:// http:").spans == [])
    }

    @Test func urlWinsOverEmphasisMarkers() {
        #expect(Parsed("https://x.com/a_b_c and _d_").pairs() == [
            Pair("https://x.com/a_b_c", .url), Pair("_d_", .emphasis), Pair("_", .inlineMarker), Pair("_", .inlineMarker),
        ])
        let p = Parsed("*https://x.com/*a*")
        #expect(p.strings(.url) == ["https://x.com/*a"])
        #expect(p.strings(.emphasis) == ["*https://x.com/*a*"])
    }

    @Test func urlInsideStrongIsRecognized() {
        let p = Parsed("**https://x.com**")
        #expect(p.strings(.url) == ["https://x.com"])
        #expect(p.strings(.strong) == ["**https://x.com**"])
    }

    @Test func urlIsNotRecognizedInsideCodeOrALinkURL() {
        #expect(Parsed("`https://x.com`").strings(.url) == [])
        #expect(Parsed("[a](https://x.com)").strings(.url) == ["https://x.com"])
        #expect(Parsed("[a](https://x.com)").spans.count == 6)
    }

    @Test func urlStopsAtACodeSpan() {
        let p = Parsed("https://x.com`a`")
        #expect(p.strings(.url) == ["https://x.com"])
        #expect(p.strings(.code) == ["`a`"])
    }

    @Test func urlInLinkTextDoesNotSwallowTheLink() {
        let p = Parsed("[see https://x.com](u)")
        #expect(p.strings(.link) == ["[see https://x.com](u)"])
        #expect(p.strings(.url) == ["https://x.com", "u"])
    }

    // MARK: Content range, UTF-16

    @Test func rangesAreAbsoluteAndStayInsideTheContent() {
        let text = "**a\n- *b* [c](u)\nd**"
        let content = NSRange(location: 6, length: 11)
        let p = Parsed(text, in: content)
        #expect(p.strings(.strong) == [])
        #expect(p.strings(.emphasis) == ["*b*"])
        #expect(p.spans.first?.range == NSRange(location: 6, length: 3))
        #expect(p.spans.allSatisfy { NSIntersectionRange($0.range, content) == $0.range })
    }

    @Test func contentEdgesCountAsWhitespace() {
        // `_` right before the content is outside it, so `_b_` still opens at the content's start.
        #expect(Parsed("a_b_", in: NSRange(location: 1, length: 3)).strings(.emphasis) == ["_b_"])
    }

    @Test func cyrillicAndEmojiKeepUTF16Ranges() {
        let p = Parsed("😀 **жир** 👍🏽 `к` https://x.com/😀")
        #expect(p.strings(.strong) == ["**жир**"])
        #expect(p.strings(.code) == ["`к`"])
        #expect(p.strings(.url) == ["https://x.com/😀"])
        #expect(p.spans.first?.range == NSRange(location: 3, length: 7))
    }

    @Test func emojiCountsAsPunctuationForFlanking() {
        // CommonMark punctuation includes symbols, so `_` after an emoji may open.
        #expect(Parsed("😀_a_").strings(.emphasis) == ["_a_"])
        #expect(Parsed("_😀_").strings(.emphasis) == ["_😀_"])
    }
}
