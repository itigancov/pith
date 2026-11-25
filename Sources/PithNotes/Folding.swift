import Foundation

/// A text folded for searching, with the way back to the original.
nonisolated public struct FoldedText: Sendable {
    public let scalars: [Unicode.Scalar]
    /// Per folded scalar: the UTF-16 range of the original text it came from. Empty when not recorded.
    fileprivate let starts: [Int]
    fileprivate let ends: [Int]

    public var string: String {
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars)
        return String(result)
    }

    /// The UTF-16 range of the original text that the folded scalars in `range` came from.
    public func originalRange(ofFolded range: Range<Int>) -> Range<Int> {
        starts[range.lowerBound]..<ends[range.upperBound - 1]
    }
}

/// Folding makes the text and the query comparable as plain substrings: lowercase, no diacritics,
/// ё as е. й stays a letter of its own.
/// Each scalar of the original gives zero or more folded ones (ß gives `ss`, a combining mark gives none).
/// The same code writes the folded column of the database and finds the ranges of a match.
nonisolated public enum Folding {
    public static func fold(_ text: String) -> FoldedText {
        fold(text, recordPositions: true)
    }

    /// For the database column: no positions.
    static func foldedString(_ text: String) -> String {
        fold(text, recordPositions: false).string
    }

    private static let ye: Unicode.Scalar = "й"
    private static let i: Unicode.Scalar = "и"
    private static let breve: Unicode.Scalar = "\u{306}"

    private static func fold(_ text: String, recordPositions: Bool) -> FoldedText {
        var scalars: [Unicode.Scalar] = []
        var starts: [Int] = []
        var ends: [Int] = []
        scalars.reserveCapacity(text.utf8.count)
        if recordPositions {
            starts.reserveCapacity(text.utf8.count)
            ends.reserveCapacity(text.utf8.count)
        }
        // What a non-ASCII scalar folds to; a text has few distinct ones.
        var cache: [Unicode.Scalar: [Unicode.Scalar]] = [:]
        // Whether the last folded scalar is a bare и that a breve can turn into й.
        var afterI = false
        var offset = 0

        for scalar in text.unicodeScalars {
            let width = scalar.value > 0xFFFF ? 2 : 1
            let start = offset
            offset += width

            if scalar.value < 0x80 {
                let value = scalar.value
                scalars.append(value >= 0x41 && value <= 0x5A ? Unicode.Scalar(value + 32)! : scalar)
                if recordPositions {
                    starts.append(start)
                    ends.append(offset)
                }
                afterI = false
                continue
            }

            if scalar == breve, afterI {
                scalars[scalars.count - 1] = ye
                if recordPositions { ends[ends.count - 1] = offset }
                afterI = false
                continue
            }

            let folded: [Unicode.Scalar]
            if let cached = cache[scalar] {
                folded = cached
            } else {
                folded = foldedScalars(of: scalar)
                cache[scalar] = folded
            }
            if folded.isEmpty {
                // A mark that went: the letter before it takes its place in the original.
                if recordPositions, !ends.isEmpty { ends[ends.count - 1] = offset }
                continue
            }
            for value in folded {
                scalars.append(value)
                if recordPositions {
                    starts.append(start)
                    ends.append(offset)
                }
            }
            afterI = folded.count == 1 && folded[0] == i
        }
        return FoldedText(scalars: scalars, starts: starts, ends: ends)
    }

    private static func foldedScalars(of scalar: Unicode.Scalar) -> [Unicode.Scalar] {
        let string = String(scalar)
        if string.lowercased() == String(ye) { return [ye] }
        let folded = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        // A lone mark of the "Combining Diacritical Marks" block goes with the diacritics.
        return folded.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }
    }
}
