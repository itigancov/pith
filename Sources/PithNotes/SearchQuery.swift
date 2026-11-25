import Foundation

/// What the user typed in the search field: words, each folded, all of which a Note must contain.
nonisolated public struct SearchQuery: Sendable, Equatable {
    /// The folded words in the order typed. A word that folds to nothing is not here.
    public let words: [String]

    private let scalars: [[Unicode.Scalar]]

    public init(_ raw: String) {
        var words: [String] = []
        var scalars: [[Unicode.Scalar]] = []
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let folded = Folding.fold(String(word))
            if folded.scalars.isEmpty { continue }
            words.append(folded.string)
            scalars.append(folded.scalars)
        }
        self.words = words
        self.scalars = scalars
    }

    public var isEmpty: Bool { words.isEmpty }

    /// Where the words are in `text`, in UTF-16 units of the original text: sorted, with the ranges that
    /// overlap or touch merged into one. Empty when the query is empty or nothing matches.
    public func ranges(in text: String) -> [Range<Int>] {
        guard !scalars.isEmpty else { return [] }
        let folded = Folding.fold(text)
        let haystack = folded.scalars
        var found: [Range<Int>] = []
        for word in scalars {
            let count = word.count
            guard count <= haystack.count else { continue }
            let first = word[0]
            var index = 0
            let last = haystack.count - count
            while index <= last {
                if haystack[index] == first, haystack[index..<index + count].elementsEqual(word) {
                    found.append(folded.originalRange(ofFolded: index..<index + count))
                }
                // One step, so that "aba" is found twice in "ababa"; the ranges merge below.
                index += 1
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for range in found {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
