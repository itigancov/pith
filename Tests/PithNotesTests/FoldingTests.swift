import Foundation
import Testing
@testable import PithNotes

@Suite struct FoldingTests {
    private func fold(_ text: String) -> String {
        Folding.fold(text).string
    }

    @Test func lowercasesLatinAndCyrillic() {
        #expect(fold("Region ЁЖИК Привет") == "region ежик привет")
    }

    @Test func stripsDiacritics() {
        #expect(fold("Café Crème Brûlée Ñandú") == "cafe creme brulee nandu")
        #expect(fold("Ångström Šíp") == "angstrom sip")
    }

    @Test func foldsYoToYe() {
        #expect(fold("ёлка Ёлка") == "елка елка")
        #expect(fold("е\u{308}лка") == "елка")
    }

    @Test func keepsShortIAsALetterOfItsOwn() {
        #expect(fold("мой Мой") == "мой мой")
        #expect(fold("мой") != fold("мои"))
        // и + combining breve, as a decomposed text has it.
        #expect(fold("и\u{306}") == "й")
        #expect(fold("И\u{306}") == "й")
        #expect(fold("мо\u{438}\u{306}") == "мой")
        // A breve on another letter goes, as any diacritic does.
        #expect(fold("a\u{306}") == "a")
    }

    @Test func decomposedAndComposedTextFoldTheSame() {
        #expect(fold("cafe\u{301}") == fold("café"))
        #expect(fold("cafe\u{301}") == "cafe")
    }

    @Test func expandsSharpSAndLigatures() {
        #expect(fold("Straße") == "strasse")
        #expect(fold("ﬁsh") == "fish")
    }

    @Test func keepsMarkdownMarkersAndEmoji() {
        #expect(fold("**Bold** # Head 🙂") == "**bold** # head 🙂")
    }

    @Test func mapsFoldedPositionsToUTF16OfTheOriginal() {
        // "Straße 🙂 café": ß is one UTF-16 unit, the emoji two.
        let text = "Straße 🙂 café"
        let folded = Folding.fold(text)
        let ns = text as NSString
        func original(of word: String) -> String? {
            let scalars = Array(word.unicodeScalars)
            let all = folded.scalars
            guard let start = (0...(all.count - scalars.count)).first(where: { Array(all[$0..<$0 + scalars.count]) == scalars })
            else { return nil }
            let range = folded.originalRange(ofFolded: start..<start + scalars.count)
            return ns.substring(with: NSRange(location: range.lowerBound, length: range.count))
        }
        #expect(original(of: "strasse") == "Straße")
        #expect(original(of: "ss") == "ß")
        #expect(original(of: "s") == "S")
        #expect(original(of: "🙂") == "🙂")
        #expect(original(of: "cafe") == "café")
    }

    @Test func mapsAcrossDecomposedMarks() {
        let text = "cafe\u{301} ёж"
        let folded = Folding.fold(text)
        let ns = text as NSString
        // The accent that went belongs to the letter before it.
        let range = folded.originalRange(ofFolded: 0..<4)
        #expect(ns.substring(with: NSRange(location: range.lowerBound, length: range.count)) == "cafe\u{301}")
    }
}
