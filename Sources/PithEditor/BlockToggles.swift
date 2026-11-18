import Foundation

/// Block Toggles: turn the lines the selection touches into one kind of Block, or back into paragraphs.
extension BlockCommands {
    public enum Kind: Sendable, Equatable {
        case heading(level: Int)
        case bullet
        case ordered
        case task
        case quote
        case codeBlock

        /// Whether a Block of `kind` is already of this kind; a heading of another level is not.
        func matches(_ kind: BlockKind) -> Bool {
            switch (self, kind) {
            case (.heading(let level), .heading(let other)): level == other
            case (.bullet, .bullet), (.ordered, .ordered), (.task, .task), (.quote, .quote): true
            default: false
            }
        }
    }

    /// The Toggle of `kind` as a Command.
    public static func toggle(_ kind: Kind) -> (String, NSRange) -> TextEdit? {
        { text, selection in toggle(kind, text: text, selection: selection) }
    }

    /// If any touched line is not of `kind`, all become `kind`; otherwise all become paragraphs.
    /// Blank lines are left out, except a blank line under the caret, which gets the Marker.
    /// `nil` when a code block is touched or there is nothing to change.
    static func toggle(_ kind: Kind, text: String, selection: NSRange) -> TextEdit? {
        let note = ScannedNote(text)
        let touched = note.blockIndices(touchedBy: selection)
        if kind == .codeBlock { return toggleCodeBlock(note, touched: touched, selection: selection) }
        guard !touched.contains(where: { note.blocks[$0].isCodeBlock }) else { return nil }
        var targets = touched.filter { note.blocks[$0].kind != .blank }
        let allMatch = !targets.isEmpty && targets.allSatisfy { kind.matches(note.blocks[$0].kind) }
        if targets.isEmpty {
            guard selection.length == 0, let blank = touched.first else { return nil }
            targets = [blank]
        }

        var prefixes: [Int: String] = [:]
        for index in targets {
            let block = note.blocks[index]
            if allMatch {
                prefixes[index] = ""
            } else if !kind.matches(block.kind) || kind == .ordered {
                // Touched numbered items are numbered again along with the new ones.
                prefixes[index] = prefix(of: kind, replacing: index, in: note)
            }
        }
        var rewrite = PrefixRewrite(note: note, prefixes: prefixes)
        if kind == .ordered, !allMatch { rewrite.renumber(targets) }
        return rewrite.edit(moving: selection)
    }

    /// Code block Toggle: removes the fences of the code blocks the selection touches,
    /// else fences the touched lines and puts the caret after the opening fence; a blank line becomes an empty block.
    private static func toggleCodeBlock(_ note: ScannedNote, touched: [Int], selection: NSRange) -> TextEdit? {
        let codeBlocks = touched.filter { note.blocks[$0].isCodeBlock }
        if !codeBlocks.isEmpty {
            let replacements = codeBlocks.flatMap { unfence(note.blocks[$0]) }
            let start = map(selection.location, through: replacements, staysBeforeInsertion: false)
            let end = map(selection.upperBound, through: replacements, staysBeforeInsertion: false)
            return TextEdit(replacements: replacements, selection: NSRange(location: start, length: end - start))
        }
        let lines = touched.filter { note.blocks[$0].kind != .blank }
        guard let first = lines.first, let last = lines.last else {
            guard selection.length == 0, let blank = touched.first else { return nil }
            let lineBreak = note.lineBreak(of: blank)
            let range = note.blocks[blank].range
            return TextEdit(
                replacements: [.init(range: range, string: "```" + lineBreak + lineBreak + "```")],
                selection: NSRange(location: range.location + 3 + lineBreak.utf16.count, length: 0)
            )
        }
        let lineBreak = note.lineBreak(of: first)
        let start = note.blocks[first].range.location
        return TextEdit(
            replacements: [
                .init(range: NSRange(location: start, length: 0), string: "```" + lineBreak),
                .init(range: NSRange(location: note.blocks[last].range.upperBound, length: 0), string: lineBreak + "```"),
            ],
            selection: NSRange(location: start + 3, length: 0)
        )
    }

    /// Deletes the opening fence line with its line break and the closing one, if any, with the line break before it.
    private static func unfence(_ block: Block) -> [TextEdit.Replacement] {
        var replacements = [TextEdit.Replacement(
            range: NSRange(location: block.range.location, length: block.content.location - block.range.location), string: ""
        )]
        let isClosed = block.markers.filter { $0.kind == .fence }.count == 2
        if isClosed {
            let end = block.content.upperBound
            replacements.append(.init(range: NSRange(location: end, length: block.range.upperBound - end), string: ""))
        }
        return replacements
    }

    /// The prefix a Block takes in `kind`: list items keep their indent, other Blocks start at level 0.
    private static func prefix(of kind: Kind, replacing index: Int, in note: ScannedNote) -> String {
        let indent = note.item(at: index).map { note.text.substring(with: $0.indent) } ?? ""
        switch kind {
        case .heading(let level): return String(repeating: "#", count: level) + " "
        case .quote: return "> "
        case .bullet: return indent + "- "
        case .ordered: return indent + "1. "
        case .task: return indent + "- [ ] "
        case .codeBlock: return ""
        }
    }
}

extension Block {
    /// Where the text after the Marker starts; a blank line has none, so it is all prefix.
    var contentStart: Int {
        kind == .blank ? range.upperBound : content.location
    }
}

/// New prefixes for some lines of a Note; each line keeps the text after its Marker.
private struct PrefixRewrite {
    let note: ScannedNote
    /// The text with the new prefixes.
    private(set) var text: NSString

    init(note: ScannedNote, prefixes: [Int: String]) {
        self.note = note
        let replacements = prefixes.map { index, prefix in
            let block = note.blocks[index]
            return TextEdit.Replacement(
                range: NSRange(location: block.range.location, length: block.contentStart - block.range.location),
                string: prefix
            )
        }
        self.text = Self.apply(replacements, to: note.text)
    }

    /// Numbers the lines of the Blocks `targets` (of the original Note) in order,
    /// and the numbered items after them in the same way as Enter and indent do.
    mutating func renumber(_ targets: [Int]) {
        let current = ScannedNote(text as String)
        let lines = Self.lines(of: text)
        let originalLines = Self.lines(of: note.text)
        // A line keeps its index; the Block of a line is found by where it starts.
        let blockAt = Dictionary(current.blocks.indices.map { (current.blocks[$0].range.location, $0) }, uniquingKeysWith: { a, _ in a })
        let lineOf = Dictionary(originalLines.indices.map { (originalLines[$0].location, $0) }, uniquingKeysWith: { a, _ in a })
        let moved = targets.compactMap { lineOf[note.blocks[$0].range.location].flatMap { blockAt[lines[$0].location] } }

        var seen = Set<Int>()
        var replacements: [TextEdit.Replacement] = []
        for index in moved where !seen.contains(index) {
            guard var series = Series(current, containing: index) else { continue }
            seen.formUnion(series.entries.compactMap { $0.item?.block })
            series.renumber(movedTo: moved.compactMap(series.position(ofBlock:)))
            replacements += series.replacements()
        }
        text = Self.apply(replacements, to: text)
    }

    /// The minimal replacements of each changed line; the selection keeps its place in the text after the Markers,
    /// and a selection end inside an old prefix goes to the start of that text.
    func edit(moving selection: NSRange) -> TextEdit? {
        let old = Self.lines(of: note.text)
        let new = Self.lines(of: text)
        guard old.count == new.count else { return nil }
        let contentStarts = Dictionary(note.blocks.map { ($0.range.location, $0.contentStart) }, uniquingKeysWith: { a, _ in a })

        var replacements: [TextEdit.Replacement] = []
        var changed = Set<Int>()
        for (line, (before, after)) in zip(old, new).enumerated() {
            guard let replacement = Self.difference(note.text, before, text, after) else { continue }
            replacements.append(replacement)
            changed.insert(line)
        }
        guard !replacements.isEmpty else { return nil }

        func map(_ location: Int) -> Int {
            guard let line = old.firstIndex(where: { $0.location <= location && location <= $0.upperBound }) else {
                return location
            }
            let (before, after) = (old[line], new[line])
            guard changed.contains(line) else { return after.location + location - before.location }
            let contentStart = contentStarts[before.location] ?? before.location
            let newContentStart = after.upperBound - (before.upperBound - contentStart)
            return location < contentStart ? newContentStart : newContentStart + location - contentStart
        }
        let start = map(selection.location)
        let end = selection.length > 0 ? map(selection.upperBound) : start
        return TextEdit(replacements: replacements, selection: NSRange(location: start, length: max(end - start, 0)))
    }

    /// The part of line `before` of `old` that differs from line `after` of `new`, as one replacement.
    private static func difference(_ old: NSString, _ before: NSRange, _ new: NSString, _ after: NSRange) -> TextEdit.Replacement? {
        var head = 0
        while head < before.length, head < after.length,
              old.character(at: before.location + head) == new.character(at: after.location + head) { head += 1 }
        if head == before.length, head == after.length { return nil }
        var tail = 0
        while tail < before.length - head, tail < after.length - head,
              old.character(at: before.upperBound - 1 - tail) == new.character(at: after.upperBound - 1 - tail) { tail += 1 }
        return TextEdit.Replacement(
            range: NSRange(location: before.location + head, length: before.length - head - tail),
            string: new.substring(with: NSRange(location: after.location + head, length: after.length - head - tail))
        )
    }

    private static func apply(_ replacements: [TextEdit.Replacement], to text: NSString) -> NSString {
        let result = NSMutableString(string: text)
        for replacement in replacements.sorted(by: TextEdit.Replacement.precedes).reversed() {
            result.replaceCharacters(in: replacement.range, with: replacement.string)
        }
        return result
    }

    /// Ranges of the lines of `text`, without their line breaks: `\n`, `\r` or `\r\n`.
    static func lines(of text: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var start = 0
        var index = 0
        while index < text.length {
            let unit = text.character(at: index)
            if unit == lf || unit == cr {
                lines.append(NSRange(location: start, length: index - start))
                index += unit == cr && index + 1 < text.length && text.character(at: index + 1) == lf ? 2 : 1
                start = index
            } else {
                index += 1
            }
        }
        lines.append(NSRange(location: start, length: text.length - start))
        return lines
    }
}

private let lf = UInt16(UnicodeScalar("\n").value)
private let cr = UInt16(UnicodeScalar("\r").value)
