import Foundation

/// Toggles of Inline: wrap the selection, the word at the caret or an empty pair in a Marker, or remove the wrapping.
public enum InlineCommands {
    public enum Kind: Sendable {
        case strong
        case emphasis
        case highlight
        case strikethrough
        case code

        /// The Marker a new wrapping is written with.
        var marker: String {
            switch self {
            case .strong: "**"
            case .emphasis: "*"
            case .highlight: "=="
            case .strikethrough: "~~"
            case .code: "`"
            }
        }

        var spanKind: SpanKind {
            switch self {
            case .strong: .strong
            case .emphasis: .emphasis
            case .highlight: .highlight
            case .strikethrough: .strikethrough
            case .code: .code
            }
        }

        /// Characters of the Markers an empty pair may be written with.
        var pairCharacters: [UInt16] {
            switch self {
            case .strong, .emphasis: [star, underscore]
            case .highlight: [equals]
            case .strikethrough: [tilde]
            case .code: [backtick]
            }
        }

        /// The length of a Marker of an empty pair, if runs of `count` characters on both sides of the caret are one.
        /// Three stars are `**` and `*` nested in either order.
        func pairMarkerLength(runs count: Int) -> Int? {
            switch self {
            case .strong: (2...3).contains(count) ? 2 : nil
            case .emphasis: count == 1 || count == 3 ? 1 : nil
            case .highlight, .strikethrough: count == 2 ? 2 : nil
            case .code: count == 1 ? 1 : nil
            }
        }
    }

    /// The Toggle of `kind` as a Command.
    public static func toggle(_ kind: Kind) -> (String, NSRange) -> TextEdit? {
        { text, selection in toggle(kind, text: text, selection: selection) }
    }

    static func toggle(_ kind: Kind, text: String, selection: NSRange) -> TextEdit? {
        let note = ScannedNote(text)
        if selection.length > 0 {
            let pieces = pieces(of: note, in: selection)
            if kind != .code, pieces.contains(where: { $0.line.cutsCode($0.range) }) { return nil }
            if pieces.count > 1 { return toggle(kind, lines: pieces, selection: selection) }
            if let (line, range) = pieces.first {
                if let span = line.innermost(kind, containing: range) {
                    return line.edit(line.unwrap(span), moving: selection)
                }
                let wrapped = line.wrap(range, in: kind)
                return TextEdit(replacements: wrapped.replacements, selection: wrapped.content)
            }
        }
        guard let index = note.blockIndex(containing: selection.location) else { return nil }
        let block = note.blocks[index]
        if block.isCodeBlock { return nil }
        let line = Line(note, block: block)
        // Only whitespace is selected: an empty pair goes where it starts.
        if selection.length > 0 { return line.insertPair(of: kind, at: selection.location) }

        // A caret in the Block's Marker acts at the start of its content.
        let caret = NSRange(location: max(selection.location, line.content.location), length: 0)
        if kind != .code, line.cutsCode(caret) { return nil }
        if let span = line.innermost(kind, containing: caret) {
            return line.edit(line.unwrap(span), moving: selection)
        }
        if let pair = line.emptyPair(of: kind, around: caret.location) {
            return line.edit([.init(range: pair.opening, string: ""), .init(range: pair.closing, string: "")], moving: selection)
        }
        guard let word = note.text.word(at: caret.location, within: line.content) else {
            return line.insertPair(of: kind, at: caret.location)
        }
        let wrapped = line.wrap(word, in: kind)
        // The caret keeps its place among the letters, also at the word's end.
        let moved = BlockCommands.map(caret.location, through: wrapped.replacements, staysBeforeInsertion: false)
        let location = min(max(moved, wrapped.content.location), wrapped.content.upperBound)
        return TextEdit(replacements: wrapped.replacements, selection: NSRange(location: location, length: 0))
    }

    /// Link Toggle: the selection or the word at the caret becomes the text of a link, the caret goes to its URL;
    /// a selected bare URL becomes the URL, the caret goes to the text. Inside a link, leaves only its text.
    /// `nil` in code, across lines and across the edge of a link.
    public static func toggleLink(text: String, selection: NSRange) -> TextEdit? {
        let note = ScannedNote(text)
        guard let index = note.blockIndex(containing: selection.location) else { return nil }
        let block = note.blocks[index]
        if block.isCodeBlock { return nil }
        guard selection.upperBound <= block.range.upperBound else { return nil }
        let line = Line(note, block: block)
        let range = selection.length > 0
            ? note.text.trimmingWhitespace(of: NSIntersectionRange(selection, line.content))
            : NSRange(location: max(selection.location, line.content.location), length: 0)
        if line.cutsCode(range) { return nil }

        let links = line.spans.filter { $0.kind == .link }
        if let link = links.first(where: { $0.range.contains(range) }) {
            return line.edit(line.unlink(link), moving: selection)
        }
        if links.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { return nil }

        let bareURL = line.spans.first { $0.kind == .url && $0.range.contains(range) && (range.length == 0 || $0.range == range) }
        if let url = bareURL?.range {
            return TextEdit(
                replacements: [.init(range: NSRange(location: url.location, length: 0), string: "[](")
                               , .init(range: NSRange(location: url.upperBound, length: 0), string: ")")],
                selection: NSRange(location: url.location + 1, length: 0)
            )
        }
        let wrapped = range.length > 0 ? range : note.text.word(at: range.location, within: line.content)
        guard let wrapped else {
            return TextEdit(
                replacements: [.init(range: range, string: "[]()")],
                selection: NSRange(location: range.location + 1, length: 0)
            )
        }
        return TextEdit(
            replacements: [
                .init(range: NSRange(location: wrapped.location, length: 0), string: "["),
                .init(range: NSRange(location: wrapped.upperBound, length: 0), string: "]()"),
            ],
            // Between the parentheses.
            selection: NSRange(location: wrapped.upperBound + 3, length: 0)
        )
    }

    /// The selected text of each Block the selection touches, without whitespace at its ends; empty ones and code blocks left out.
    private static func pieces(of note: ScannedNote, in selection: NSRange) -> [(line: Line, range: NSRange)] {
        note.blockIndices(touchedBy: selection).compactMap { index in
            let block = note.blocks[index]
            if block.isCodeBlock { return nil }
            let range = note.text.trimmingWhitespace(of: NSIntersectionRange(selection, block.content))
            return range.length > 0 ? (Line(note, block: block), range) : nil
        }
    }

    /// Several lines: if all are in a Span of `kind`, unwraps each, otherwise wraps those that are not.
    private static func toggle(_ kind: Kind, lines: [(line: Line, range: NSRange)], selection: NSRange) -> TextEdit {
        let wrapped = lines.map { $0.line.innermost(kind, containing: $0.range) }
        let replacements: [TextEdit.Replacement]
        if wrapped.allSatisfy({ $0 != nil }) {
            replacements = zip(lines, wrapped).flatMap { $0.line.unwrap($1!) }
        } else {
            replacements = zip(lines, wrapped).flatMap { piece, span in
                span == nil ? piece.line.wrap(piece.range, in: kind).replacements : []
            }
        }
        let sorted = replacements.sorted(by: TextEdit.Replacement.precedes)
        // The selection keeps the outer Markers out.
        let start = BlockCommands.map(selection.location, through: sorted, staysBeforeInsertion: false)
        let end = BlockCommands.map(selection.upperBound, through: sorted, staysBeforeInsertion: true)
        return TextEdit(replacements: sorted, selection: NSRange(location: start, length: end - start))
    }
}

/// One Block's content with its Inline Spans.
private struct Line {
    let text: NSString
    let content: NSRange
    let spans: [Span]

    init(_ note: ScannedNote, block: Block) {
        self.text = note.text
        self.content = block.content
        self.spans = InlineParser.parse(note.text as String, in: block.content)
    }

    /// The smallest Span of `kind` that contains `range`, ends included.
    func innermost(_ kind: InlineCommands.Kind, containing range: NSRange) -> Span? {
        spans
            .filter { $0.kind == kind.spanKind && $0.range.contains(range) }
            .min { $0.range.length < $1.range.length }
    }

    /// Whether `range` is inside inline code or takes only part of it: a Marker there would change the code.
    func cutsCode(_ range: NSRange) -> Bool {
        spans.contains { span in
            guard span.kind == .code else { return false }
            if range.length == 0 { return span.range.location < range.location && range.location < span.range.upperBound }
            return NSIntersectionRange(span.range, range).length > 0 && !range.contains(span.range)
        }
    }

    /// The opening and closing Markers of an Inline Span.
    func markers(of span: Span) -> (opening: NSRange, closing: NSRange)? {
        let markers = spans.filter { $0.kind == .inlineMarker }
        guard let opening = markers.first(where: { $0.range.location == span.range.location }),
              let closing = markers.first(where: { $0.range.upperBound == span.range.upperBound })
        else { return nil }
        return (opening.range, closing.range)
    }

    /// Deletions of the Markers of `span`; for code, also of the spaces that pad it on both sides.
    func unwrap(_ span: Span) -> [TextEdit.Replacement] {
        guard var (opening, closing) = markers(of: span) else { return [] }
        let inner = NSRange(location: opening.upperBound, length: closing.location - opening.upperBound)
        if span.kind == .code, inner.length >= 2, text.character(at: inner.location) == space,
           text.character(at: inner.upperBound - 1) == space, !text.isAllSpaces(inner) {
            opening.length += 1
            closing.location -= 1
            closing.length += 1
        }
        return [.init(range: opening, string: ""), .init(range: closing, string: "")]
    }

    /// Deletions that leave only the text of `link`.
    func unlink(_ link: Span) -> [TextEdit.Replacement] {
        let text = spans.first { $0.kind == .linkText && link.range.contains($0.range) }?.range
            ?? NSRange(location: link.range.location + 1, length: 0)
        return [
            .init(range: NSRange(location: link.range.location, length: text.location - link.range.location), string: ""),
            .init(range: NSRange(location: text.upperBound, length: link.range.upperBound - text.upperBound), string: ""),
        ]
    }

    /// Wraps `range` in the Marker of `kind`; Spans of `kind` it overlaps are merged into it, losing their Markers.
    /// Also returns the wrapped text without the Markers, in the text after the replacements.
    func wrap(_ range: NSRange, in kind: InlineCommands.Kind) -> (replacements: [TextEdit.Replacement], content: NSRange) {
        var union = range
        var merged: [Span] = []
        while let span = spans.first(where: { span in
            span.kind == kind.spanKind && NSIntersectionRange(span.range, union).length > 0
                && !merged.contains(span)
        }) {
            merged.append(span)
            union = NSUnionRange(union, span.range)
        }
        let deletions = merged.flatMap(unwrap)
        let (opening, closing) = markers(for: kind, wrapping: union, without: deletions)
        let replacements = ([.init(range: NSRange(location: union.location, length: 0), string: opening)] + deletions
            + [.init(range: NSRange(location: union.upperBound, length: 0), string: closing)])
            .sorted(by: TextEdit.Replacement.precedes)
        let deleted = deletions.reduce(0) { $0 + $1.range.length }
        let content = NSRange(location: union.location + opening.utf16.count, length: union.length - deleted)
        return (replacements, content)
    }

    /// The Markers a new wrapping of `range` is written with, once `deletions` are made in it.
    /// Code takes a backtick run longer than any inside, padded with spaces if there are backticks inside.
    private func markers(
        for kind: InlineCommands.Kind, wrapping range: NSRange, without deletions: [TextEdit.Replacement]
    ) -> (String, String) {
        guard kind == .code else { return (kind.marker, kind.marker) }
        var longest = 0
        var run = 0
        for index in range.location..<range.upperBound {
            if deletions.contains(where: { NSLocationInRange(index, $0.range) }) { continue }
            run = text.character(at: index) == backtick ? run + 1 : 0
            longest = max(longest, run)
        }
        guard longest > 0 else { return ("`", "`") }
        let marker = String(repeating: "`", count: longest + 1)
        return (marker + " ", " " + marker)
    }

    /// Inserts an empty pair of the Marker at `location` with the caret between.
    func insertPair(of kind: InlineCommands.Kind, at location: Int) -> TextEdit {
        let marker = kind.marker
        return TextEdit(
            replacements: [.init(range: NSRange(location: location, length: 0), string: marker + marker)],
            selection: NSRange(location: location + marker.utf16.count, length: 0)
        )
    }

    /// `replacements` with the selection moved along with the text.
    func edit(_ replacements: [TextEdit.Replacement], moving selection: NSRange) -> TextEdit? {
        guard !replacements.isEmpty else { return nil }
        let sorted = replacements.sorted(by: TextEdit.Replacement.precedes)
        let start = BlockCommands.map(selection.location, through: sorted, staysBeforeInsertion: false)
        let end = BlockCommands.map(selection.upperBound, through: sorted, staysBeforeInsertion: false)
        return TextEdit(replacements: sorted, selection: NSRange(location: start, length: end - start))
    }

    /// The Markers of an empty pair of `kind` right around the caret; never part of a Marker the parser sees.
    func emptyPair(of kind: InlineCommands.Kind, around caret: Int) -> (opening: NSRange, closing: NSRange)? {
        let insideMarker = spans.contains {
            $0.kind == .inlineMarker && $0.range.location < caret && caret < $0.range.upperBound
        }
        guard !insideMarker else { return nil }
        for character in kind.pairCharacters {
            var before = 0
            while caret - before > content.location, text.character(at: caret - before - 1) == character { before += 1 }
            var after = 0
            while caret + after < content.upperBound, text.character(at: caret + after) == character { after += 1 }
            guard before == after, let length = kind.pairMarkerLength(runs: before) else { continue }
            return (NSRange(location: caret - length, length: length), NSRange(location: caret, length: length))
        }
        return nil
    }
}

private func unit(_ c: Unicode.Scalar) -> UInt16 { UInt16(c.value) }

private let star = unit("*")
private let underscore = unit("_")
private let equals = unit("=")
private let tilde = unit("~")
private let backtick = unit("`")
private let space = unit(" ")
