import Foundation
import Testing
@testable import PithEditor

/// The url under the caret of `marked`: its range as a `«…»` selection and its address.
private func url(_ marked: String) -> (Marked, String)? {
    let input = Marked(marked)
    guard let (range, url) = Links.url(in: input.text, at: input.selection.location) else { return nil }
    return (Marked(text: input.text, selection: range), url.absoluteString)
}

private func expectURL(_ marked: String, _ range: String, _ address: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let found = url(marked)
    #expect(found?.0 == Marked(range), sourceLocation: sourceLocation)
    #expect(found?.1 == address, sourceLocation: sourceLocation)
}

struct LinksTests {
    // MARK: url

    @Test func indexInALinksURLFindsIt() {
        expectURL("a [t](https://x.c|om) b", "a [t](«https://x.com») b", "https://x.com")
        expectURL("a [t](|https://x.com) b", "a [t](«https://x.com») b", "https://x.com")
        expectURL("a [t](https://x.co|m) b", "a [t](«https://x.com») b", "https://x.com")
    }

    @Test func indexInABareURLFindsIt() {
        expectURL("see |https://x.com now", "see «https://x.com» now", "https://x.com")
        expectURL("see https://x.co|m.", "see «https://x.com».", "https://x.com")
    }

    @Test func bareURLInALinksTextOpensItsOwnAddress() {
        expectURL("[|https://a.com](https://b.com)", "[«https://a.com»](https://b.com)", "https://a.com")
        expectURL("[https://a.com](|https://b.com)", "[https://a.com](«https://b.com»)", "https://b.com")
    }

    @Test func urlWithoutASchemeOpensOverHTTPS() {
        expectURL("[a](exa|mple.com)", "[a](«example.com»)", "https://example.com")
        expectURL("[a](|example.com/path?q=1)", "[a](«example.com/path?q=1»)", "https://example.com/path?q=1")
    }

    @Test func urlWithASchemeOpensAsIs() {
        expectURL("[a](|mailto:a@b)", "[a](«mailto:a@b»)", "mailto:a@b")
        expectURL("[a](|file:///x)", "[a](«file:///x»)", "file:///x")
        expectURL("[a](|obsidian://x)", "[a](«obsidian://x»)", "obsidian://x")
        expectURL("[a](|HTTP://x)", "[a](«HTTP://x»)", "HTTP://x")
        expectURL("[a](|a+b.c-d:x)", "[a](«a+b.c-d:x»)", "a+b.c-d:x")
        expectURL("[a](|localhost:3000)", "[a](«localhost:3000»)", "localhost:3000")
    }

    @Test func aColonAfterOtherCharactersIsNotAScheme() {
        expectURL("[a](|x.com/a:b)", "[a](«x.com/a:b»)", "https://x.com/a:b")
        expectURL("[a](|x.com?t=1:2)", "[a](«x.com?t=1:2»)", "https://x.com?t=1:2")
    }

    @Test func urlInCodeOrEmptyFindsNothing() {
        #expect(url("[a](|)") == nil)
        #expect(url("`|https://x.com`") == nil)
        #expect(url("`[a](|u)`") == nil)
        #expect(url("```\n|https://x.com\n```") == nil)
        #expect(url("```\n[a](|u)\n```") == nil)
        #expect(url("```\n|https://x.com") == nil)
    }

    @Test func textThatMakesNoURLFindsNothing() {
        #expect(url("[a](|http://[x)") == nil)
        #expect(url("[a](|x%zz)") == nil)
    }

    @Test func nonASCIIURLsAreEncoded() {
        expectURL("[a](|пример.рф/тест)", "[a](«пример.рф/тест»)", "https://xn--e1afmkfd.xn--p1ai/%D1%82%D0%B5%D1%81%D1%82")
        expectURL("see |https://x.com/😀 now", "see «https://x.com/😀» now", "https://x.com/%F0%9F%98%80")
    }

    @Test func urlIsFoundInAnyBlockOfTheNote() {
        expectURL("# h\n\n- [ ] see [a](|u.com)", "# h\n\n- [ ] see [a](«u.com»)", "https://u.com")
        expectURL("a\r\n> |https://x.com\r\nb", "a\r\n> «https://x.com»\r\nb", "https://x.com")
        expectURL("🎉 [a](u)\n## 🚀 [b](|v)", "🎉 [a](u)\n## 🚀 [b](«v»)", "https://v")
        expectURL("```\nx\n```\n[a](|u)", "```\nx\n```\n[a](«u»)", "https://u")
    }

    @Test func indexOutsideAURLFindsNothing() {
        for marked in [
            "a [t|ext](https://x.com) b", "a |[text](https://x.com) b", "a [text|](https://x.com) b",
            "a [text]|(https://x.com) b", "a [text](https://x.com|) b", "a| [text](https://x.com) b",
            "a [text](https://x.com)| b", "see https://x.com|. now", "plain| text", "|", "",
        ] {
            #expect(url(marked) == nil, "\(marked)")
        }
    }

    // MARK: gesture

    @Test func aQuickStillPressOpens() {
        #expect(Links.gesture(duration: 0, distance: 0) == .open)
        #expect(Links.gesture(duration: 0.349, distance: 3) == .open)
    }

    @Test func aLongStillPressSelects() {
        #expect(Links.gesture(duration: 0.35, distance: 0) == .select)
        #expect(Links.gesture(duration: 5, distance: 3) == .select)
    }

    @Test func movingMoreThanThreePointsDrags() {
        #expect(Links.gesture(duration: 0, distance: 3.01) == .drag)
        #expect(Links.gesture(duration: 5, distance: 3.01) == .drag)
    }
}
