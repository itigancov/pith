import AppKit

/// What the context menu asks of the spell checker; `SystemSpellChecker` is the live one, tests substitute a fake.
protocol SpellChecking: AnyObject {
    /// The range of the misspelled word at `index` of `text`, or `nil` if there is no word there or it is spelled right.
    func misspelledRange(at index: Int, in text: String) -> NSRange?
    /// The corrections for the word at `range`, best first; none is an empty list.
    func guesses(for range: NSRange, in text: String) -> [String]
    /// Stops marking `word` in this document.
    func ignore(word: String)
}

/// The system spell checker for the document of one editor, which is the tag the editor's own underlines use.
final class SystemSpellChecker: SpellChecking {
    private let tag: Int

    init(documentTag: Int) { tag = documentTag }

    func misspelledRange(at index: Int, in text: String) -> NSRange? {
        let length = (text as NSString).length
        guard index >= 0, index <= length, length > 0 else { return nil }
        let word = NSAttributedString(string: text).doubleClick(at: min(index, length - 1))
        guard word.length > 0, NSLocationInRange(index, NSRange(location: word.location, length: word.length + 1)) else { return nil }
        let candidate = (text as NSString).substring(with: word)
        let found = NSSpellChecker.shared.checkSpelling(
            of: candidate, startingAt: 0, language: nil, wrap: false, inSpellDocumentWithTag: tag, wordCount: nil
        )
        guard found.location != NSNotFound, found.length == word.length else { return nil }
        return word
    }

    func guesses(for range: NSRange, in text: String) -> [String] {
        NSSpellChecker.shared.guesses(forWordRange: range, in: text, language: nil, inSpellDocumentWithTag: tag) ?? []
    }

    func ignore(word: String) {
        NSSpellChecker.shared.ignoreWord(word, inSpellDocumentWithTag: tag)
    }
}
