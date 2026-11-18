import Foundation

extension NSRange {
    /// Whether `other` lies within this range, ends included.
    func contains(_ other: NSRange) -> Bool {
        location <= other.location && other.upperBound <= upperBound
    }
}

extension NSString {
    func isAllSpaces(_ range: NSRange) -> Bool {
        (range.location..<range.upperBound).allSatisfy { character(at: $0) == space }
    }

    /// `range` without whitespace at its ends; empty at its start if it is all whitespace.
    func trimmingWhitespace(of range: NSRange) -> NSRange {
        var start = range.location
        while let (scalar, length) = scalar(startingAt: start, before: range.upperBound), scalar.properties.isWhitespace {
            start += length
        }
        guard start < range.upperBound else { return NSRange(location: range.location, length: 0) }
        var end = range.upperBound
        while let (scalar, length) = scalar(endingAt: end, after: start), scalar.properties.isWhitespace { end -= length }
        return NSRange(location: start, length: end - start)
    }

    /// The longest run of word characters around `location` within `bounds`, by Unicode scalars;
    /// `location` at either end of a word is in it. `nil` if there is none.
    func word(at location: Int, within bounds: NSRange) -> NSRange? {
        var start = location
        while let (scalar, length) = scalar(endingAt: start, after: bounds.location), isWordScalar(scalar) { start -= length }
        var end = location
        while let (scalar, length) = scalar(startingAt: end, before: bounds.upperBound), isWordScalar(scalar) { end += length }
        return start < end ? NSRange(location: start, length: end - start) : nil
    }

    /// The scalar that ends at `index`, if it starts at or after `lowerBound`, with its UTF-16 length.
    func scalar(endingAt index: Int, after lowerBound: Int) -> (Unicode.Scalar, Int)? {
        guard index > lowerBound else { return nil }
        let low = character(at: index - 1)
        if UTF16.isTrailSurrogate(low), index - 2 >= lowerBound, UTF16.isLeadSurrogate(character(at: index - 2)) {
            return (UTF16.decode(UTF16.EncodedScalar([character(at: index - 2), low])), 2)
        }
        return Unicode.Scalar(low).map { ($0, 1) }
    }

    /// The scalar that starts at `index`, if it ends at or before `upperBound`, with its UTF-16 length.
    func scalar(startingAt index: Int, before upperBound: Int) -> (Unicode.Scalar, Int)? {
        guard index < upperBound else { return nil }
        let high = character(at: index)
        if UTF16.isLeadSurrogate(high), index + 2 <= upperBound, UTF16.isTrailSurrogate(character(at: index + 1)) {
            return (UTF16.decode(UTF16.EncodedScalar([high, character(at: index + 1)])), 2)
        }
        return Unicode.Scalar(high).map { ($0, 1) }
    }
}

/// Letters, digits, `_`, combining marks and the parts of emoji sequences.
private func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
    let properties = scalar.properties
    if properties.isAlphabetic || properties.numericType != nil || scalar == "_" { return true }
    switch properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: return true
    default: break
    }
    // `#`, `*` and digits are emoji too; outside ASCII, emoji, their modifiers, ZWJ and tag characters join a word.
    if scalar.isASCII { return false }
    return properties.isEmoji || scalar == "\u{200D}" || (0xE0020...0xE007F).contains(scalar.value)
}

private let space = UInt16(UnicodeScalar(" ").value)
