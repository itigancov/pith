import Foundation
import Testing
@testable import PithNotes

@Suite struct SearchQueryTests {
    /// The matched pieces of `text`, as the UI would cut them out.
    private func pieces(_ query: String, in text: String) -> [String] {
        let ns = text as NSString
        return SearchQuery(query).ranges(in: text).map { ns.substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
    }

    @Test func splitsIntoFoldedWords() {
        #expect(SearchQuery("  Café\tРЕГИОН\nёлка  ").words == ["cafe", "регион", "елка"])
    }

    @Test func emptyAndBlankQueriesHaveNoWords() {
        #expect(SearchQuery("").words.isEmpty)
        #expect(SearchQuery(" \t\n").words.isEmpty)
        #expect(SearchQuery("").ranges(in: "anything").isEmpty)
        #expect(SearchQuery("   ").ranges(in: "anything").isEmpty)
    }

    @Test func wordsThatFoldToNothingAreDropped() {
        #expect(SearchQuery("\u{301} a").words == ["a"])
        #expect(SearchQuery("\u{301}").words.isEmpty)
    }

    @Test func quotesAndWildcardsAreOrdinaryCharacters() {
        #expect(pieces("\"a", in: "say \"a\" and a*b") == ["\"a"])
        #expect(pieces("a*", in: "say \"a\" and a*b") == ["a*"])
        #expect(pieces("-b", in: "a-b") == ["-b"])
        #expect(pieces("**", in: "**bold**") == ["**", "**"])
        #expect(pieces("#", in: "# Head") == ["#"])
    }

    @Test func findsASubstringIgnoringCaseAndDiacritics() {
        #expect(pieces("gion", in: "Region of REGIONS") == ["gion", "GION"])
        #expect(pieces("cafe", in: "Un café, un CAFÉ") == ["café", "CAFÉ"])
        #expect(pieces("елка", in: "Ёлка и ёлка") == ["Ёлка", "ёлка"])
        #expect(pieces("ёлка", in: "елка") == ["елка"])
    }

    @Test func shortIIsNotTheSameAsI() {
        #expect(pieces("мой", in: "мои мой") == ["мой"])
    }

    @Test func rangesAreUTF16OfTheOriginal() {
        // The emoji takes two UTF-16 units, ß one.
        #expect(SearchQuery("ss").ranges(in: "🙂 Straße") == [7..<8])
        #expect(SearchQuery("stra").ranges(in: "🙂 Straße") == [3..<7])
    }

    @Test func allWordsAreSearchedInAnyOrder() {
        #expect(pieces("beta alpha", in: "alpha x beta") == ["alpha", "beta"])
    }

    @Test func overlappingAndTouchingRangesMerge() {
        #expect(SearchQuery("abc bcd").ranges(in: "abcd") == [0..<4])
        #expect(SearchQuery("ab cd").ranges(in: "abcd") == [0..<4])
        #expect(SearchQuery("ab ab").ranges(in: "ab ab") == [0..<2, 3..<5])
    }

    @Test func noMatchGivesNoRanges() {
        #expect(SearchQuery("zzz").ranges(in: "alpha").isEmpty)
        // A word that is missing does not stop the others from being highlighted.
        #expect(pieces("alpha zzz", in: "alpha") == ["alpha"])
    }
}
