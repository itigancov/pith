import Foundation

public enum InlineParser {
    /// Inline Spans of one Block's `content` range of `text`; ranges are absolute.
    public static func parse(_ text: String, in content: NSRange) -> [Span] {
        let utf16 = text.utf16
        let start = utf16.index(utf16.startIndex, offsetBy: content.location)
        let end = utf16.index(start, offsetBy: content.length)
        var parser = Parser(units: Array(utf16[start..<end]), base: content.location)
        return parser.parse()
    }
}

private func unit(_ c: Unicode.Scalar) -> UInt16 { UInt16(c.value) }

private let backtick = unit("`")
private let star = unit("*")
private let underscore = unit("_")
private let tilde = unit("~")
private let equals = unit("=")
private let backslash = unit("\\")
private let openBracket = unit("[")
private let closeBracket = unit("]")
private let openParen = unit("(")
private let closeParen = unit(")")
private let schemes = ["https://", "http://"].map { Array($0.utf16) }
private let trailingPunctuation = Set(#"?!.,:*_~'""#.utf16)

/// A run of emphasis characters that can still open or close.
private struct Delimiter {
    var char: UInt16
    /// The unused part of the run: openers use it from the end, closers from the start.
    var range: Range<Int>
    let originalCount: Int
    let canOpen: Bool
    let canClose: Bool
}

private func isDelimiterChar(_ u: UInt16) -> Bool {
    u == star || u == underscore || u == tilde || u == equals
}

private func lowercased(_ u: UInt16) -> UInt16 {
    (unit("A")...unit("Z")).contains(u) ? u + 0x20 : u
}

private struct OpenersBottomKey: Hashable {
    let char: UInt16
    let canOpen: Bool
    let countMod3: Int
}

/// The content's edges count as whitespace; a lone surrogate counts as neither.
private func isWhitespace(_ scalar: Unicode.Scalar?) -> Bool {
    scalar?.properties.isWhitespace ?? true
}

/// Whitespace is all in the BMP, so a surrogate is never whitespace.
private func isWhitespaceUnit(_ u: UInt16) -> Bool {
    Unicode.Scalar(u)?.properties.isWhitespace ?? false
}

/// Unicode punctuation as CommonMark defines it: the P and S general categories.
private func isPunctuation(_ scalar: Unicode.Scalar?) -> Bool {
    switch scalar?.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
         .initialPunctuation, .finalPunctuation, .otherPunctuation,
         .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
        return true
    default:
        return false
    }
}

private struct Parser {
    let units: [UInt16]
    let base: Int
    /// End of the code span that starts at an index, `-1` elsewhere.
    var codeEnd: [Int]
    /// Index of the `)` matching the `(` at an index, `-1` elsewhere; parentheses inside code don't count.
    var closingParen: [Int]
    var delimiters: [Delimiter] = []
    /// Open `[` of possible links, each with the index of the last delimiter before it.
    var brackets: [(start: Int, bottom: Int)] = []
    var spans: [Span] = []

    init(units: [UInt16], base: Int) {
        self.units = units
        self.base = base
        self.codeEnd = Array(repeating: -1, count: units.count)
        self.closingParen = Array(repeating: -1, count: units.count)
    }

    mutating func parse() -> [Span] {
        findCodeSpans()
        matchParentheses()
        var i = 0
        while i < units.count {
            if codeEnd[i] >= 0 {
                emitCode(i..<codeEnd[i])
                i = codeEnd[i]
            } else if isEscape(at: i) {
                emit(i..<i + 1, .inlineMarker)
                i += 2
            } else if units[i] == openBracket {
                brackets.append((i, delimiters.count - 1))
                i += 1
            } else if units[i] == closeBracket {
                i = closeLink(at: i)
            } else if let end = bareURL(at: i) {
                emit(i..<end, .url)
                i = end
            } else if isDelimiterChar(units[i]) {
                i = pushDelimiter(at: i)
            } else {
                i += 1
            }
        }
        processEmphasis(above: -1)
        // Sorted by start, outer first; the sort is stable, and an element is emitted before its Markers.
        return spans.enumerated()
            .sorted { a, b in
                let (x, y) = (a.element.range, b.element.range)
                if x.location != y.location { return x.location < y.location }
                if x.length != y.length { return x.length > y.length }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: Code spans

    /// A run of N backticks closes at the nearest later run of exactly N.
    private mutating func findCodeSpans() {
        // Maximal runs by length; a closer ignores escapes, since there are none inside code.
        var runs: [Int: [Int]] = [:]
        var i = 0
        while i < units.count {
            let length = runLength(of: backtick, at: i)
            if length > 0 { runs[length, default: []].append(i) }
            i += max(length, 1)
        }
        var cursors: [Int: Int] = [:]
        i = 0
        while i < units.count {
            if isEscape(at: i) {
                i += 2
                continue
            }
            let length = runLength(of: backtick, at: i)
            guard length > 0 else {
                i += 1
                continue
            }
            let openerEnd = i + length
            let starts = runs[length] ?? []
            var cursor = cursors[length] ?? 0
            while cursor < starts.count, starts[cursor] < openerEnd { cursor += 1 }
            cursors[length] = cursor
            if cursor < starts.count {
                codeEnd[i] = starts[cursor] + length
                i = codeEnd[i]
            } else {
                i = openerEnd
            }
        }
    }

    private mutating func emitCode(_ range: Range<Int>) {
        let length = runLength(of: backtick, at: range.lowerBound)
        emit(range, .code)
        emit(range.lowerBound..<range.lowerBound + length, .inlineMarker)
        emit(range.upperBound - length..<range.upperBound, .inlineMarker)
    }

    // MARK: Links

    private mutating func matchParentheses() {
        var open: [Int] = []
        var i = 0
        while i < units.count {
            if codeEnd[i] >= 0 {
                i = codeEnd[i]
                continue
            }
            if units[i] == openParen {
                open.append(i)
            } else if units[i] == closeParen, let start = open.popLast() {
                closingParen[start] = i
            }
            i += 1
        }
    }

    /// Makes a link if `]` closes an open `[` and is followed by `(` with a matching `)` and no whitespace between them.
    /// Returns the index to continue from.
    private mutating func closeLink(at textEnd: Int) -> Int {
        guard let opener = brackets.popLast() else { return textEnd + 1 }
        let urlStart = textEnd + 2
        guard urlStart <= units.count, units[textEnd + 1] == openParen, closingParen[textEnd + 1] >= 0 else {
            return textEnd + 1
        }
        let urlEnd = closingParen[textEnd + 1]
        // An address has no whitespace: with it, the brackets and parentheses are text, and parsing goes on inside them.
        guard !units[urlStart..<urlEnd].contains(where: isWhitespaceUnit) else { return textEnd + 1 }
        // Emphasis inside the text pairs only there.
        processEmphasis(above: opener.bottom)
        emit(opener.start..<urlEnd + 1, .link)
        emit(opener.start..<opener.start + 1, .inlineMarker)
        if opener.start + 1 < textEnd { emit(opener.start + 1..<textEnd, .linkText) }
        emit(textEnd..<urlStart, .inlineMarker)
        if urlStart < urlEnd { emit(urlStart..<urlEnd, .url) }
        emit(urlEnd..<urlEnd + 1, .inlineMarker)
        // A link never contains another link, so every earlier `[` is now text.
        brackets.removeAll()
        return urlEnd + 1
    }

    // MARK: Bare URLs

    /// End of an `http://` or `https://` URL starting at `start`.
    /// It runs to whitespace, a code span or, inside a possible link text, `]`; the tail is trimmed as in GFM.
    private func bareURL(at start: Int) -> Int? {
        guard lowercased(units[start]) == unit("h") else { return nil }
        guard let schemeEnd = scheme(at: start) else { return nil }
        var end = schemeEnd
        var opened = 0
        var closed = 0
        while end < units.count, !isWhitespaceUnit(units[end]), codeEnd[end] < 0 {
            if units[end] == closeBracket, !brackets.isEmpty { break }
            if units[end] == openParen { opened += 1 }
            if units[end] == closeParen { closed += 1 }
            end += 1
        }
        while end > schemeEnd {
            let last = units[end - 1]
            if trailingPunctuation.contains(last) {
                end -= 1
            } else if last == closeParen, closed > opened {
                closed -= 1
                end -= 1
            } else {
                break
            }
        }
        return end > schemeEnd ? end : nil
    }

    /// End of a case-insensitive `http://` or `https://` at `start`.
    private func scheme(at start: Int) -> Int? {
        for prefix in schemes where start + prefix.count <= units.count {
            let matches = prefix.indices.allSatisfy { lowercased(units[start + $0]) == prefix[$0] }
            if matches { return start + prefix.count }
        }
        return nil
    }

    // MARK: Emphasis

    /// Pushes the delimiter run at `start` and returns the index after it.
    private mutating func pushDelimiter(at start: Int) -> Int {
        let char = units[start]
        let end = start + runLength(of: char, at: start)
        // `~~` and `==` are exactly two characters; other runs of them are text.
        if char == tilde || char == equals, end - start != 2 { return end }
        let before = scalar(before: start)
        let after = scalar(at: end)
        let leftFlanking = !isWhitespace(after) && (!isPunctuation(after) || isWhitespace(before) || isPunctuation(before))
        let rightFlanking = !isWhitespace(before) && (!isPunctuation(before) || isWhitespace(after) || isPunctuation(after))
        var canOpen = leftFlanking
        var canClose = rightFlanking
        if char == underscore {
            // `_` inside a word marks nothing.
            canOpen = leftFlanking && (!rightFlanking || isPunctuation(before))
            canClose = rightFlanking && (!leftFlanking || isPunctuation(after))
        }
        if canOpen || canClose {
            delimiters.append(Delimiter(
                char: char, range: start..<end, originalCount: end - start, canOpen: canOpen, canClose: canClose
            ))
        }
        return end
    }

    /// CommonMark "process emphasis" over the delimiters above index `bottom`, which are then dropped.
    private mutating func processEmphasis(above bottom: Int) {
        let first = bottom + 1
        guard first < delimiters.count else { return }
        // A doubly linked list over the delimiters above `bottom`; `-1` and `count` are the ends.
        var prev = Array(first - 1..<delimiters.count - 1)
        var next = Array(first + 1...delimiters.count)
        func link(_ a: Int, _ b: Int) {
            if a >= first { next[a - first] = b }
            if b < delimiters.count { prev[b - first] = a }
        }
        var openersBottom: [OpenersBottomKey: Int] = [:]

        var closer = first
        while closer < delimiters.count {
            let c = delimiters[closer]
            guard c.canClose else {
                closer = next[closer - first]
                continue
            }
            let key = OpenersBottomKey(char: c.char, canOpen: c.canOpen, countMod3: c.originalCount % 3)
            let floor = max(bottom, openersBottom[key] ?? bottom)
            var opener = prev[closer - first]
            while opener > floor, !matches(delimiters[opener], c) { opener = prev[opener - first] }

            guard opener > floor else {
                openersBottom[key] = prev[closer - first]
                let following = next[closer - first]
                if !c.canOpen { link(prev[closer - first], following) }
                closer = following
                continue
            }

            let use = delimiters[opener].range.count >= 2 && c.range.count >= 2 ? 2 : 1
            let openerEnd = delimiters[opener].range.upperBound
            let closerStart = c.range.lowerBound
            emit(openerEnd - use..<closerStart + use, kind(of: c.char, count: use))
            emit(openerEnd - use..<openerEnd, .inlineMarker)
            emit(closerStart..<closerStart + use, .inlineMarker)

            // Delimiters between the pair can no longer match.
            link(opener, closer)
            delimiters[opener].range = delimiters[opener].range.lowerBound..<openerEnd - use
            delimiters[closer].range = closerStart + use..<c.range.upperBound
            if delimiters[opener].range.isEmpty { link(prev[opener - first], closer) }
            if delimiters[closer].range.isEmpty {
                let following = next[closer - first]
                link(prev[closer - first], following)
                closer = following
            }
        }
        delimiters.removeSubrange(first...)
    }

    private func kind(of char: UInt16, count: Int) -> SpanKind {
        switch char {
        case tilde: .strikethrough
        case equals: .highlight
        default: count == 2 ? .strong : .emphasis
        }
    }

    /// Same character, and for `*`/`_` the CommonMark "rule of 3".
    private func matches(_ opener: Delimiter, _ closer: Delimiter) -> Bool {
        guard opener.char == closer.char, opener.canOpen else { return false }
        if closer.char == star || closer.char == underscore, opener.canClose || closer.canOpen {
            let sum = opener.originalCount + closer.originalCount
            if sum % 3 == 0, opener.originalCount % 3 != 0 || closer.originalCount % 3 != 0 { return false }
        }
        return true
    }

    // MARK: Helpers

    /// `\` before ASCII punctuation.
    private func isEscape(at index: Int) -> Bool {
        guard units[index] == backslash, index + 1 < units.count else { return false }
        let u = units[index + 1]
        return (0x21...0x2F).contains(u) || (0x3A...0x40).contains(u) || (0x5B...0x60).contains(u) || (0x7B...0x7E).contains(u)
    }

    private func runLength(of u: UInt16, at index: Int) -> Int {
        var end = index
        while end < units.count, units[end] == u { end += 1 }
        return end - index
    }

    /// The scalar ending just before `index`; `nil` at the content's start.
    private func scalar(before index: Int) -> Unicode.Scalar? {
        guard index > 0 else { return nil }
        let low = units[index - 1]
        if UTF16.isTrailSurrogate(low), index >= 2, UTF16.isLeadSurrogate(units[index - 2]) {
            return UTF16.decode(UTF16.EncodedScalar([units[index - 2], low]))
        }
        return Unicode.Scalar(low)
    }

    /// The scalar starting at `index`; `nil` at the content's end.
    private func scalar(at index: Int) -> Unicode.Scalar? {
        guard index < units.count else { return nil }
        let high = units[index]
        if UTF16.isLeadSurrogate(high), index + 1 < units.count, UTF16.isTrailSurrogate(units[index + 1]) {
            return UTF16.decode(UTF16.EncodedScalar([high, units[index + 1]]))
        }
        return Unicode.Scalar(high)
    }

    private mutating func emit(_ range: Range<Int>, _ kind: SpanKind) {
        spans.append(Span(range: NSRange(location: base + range.lowerBound, length: range.count), kind: kind))
    }
}
