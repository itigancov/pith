import Foundation

public enum BlockScanner {
    /// Scans the whole Note line by line.
    public static func scan(_ text: String) -> [Block] {
        let units = Array(text.utf16)
        var blocks: [Block] = []
        var indents: [Int] = []
        var lineStart = 0
        while true {
            let lineEnd = lineEnd(in: units, from: lineStart)
            let line = lineStart..<lineEnd
            var nextLineStart: Int? = lineEnd < units.count ? lineEnd + terminatorLength(in: units, at: lineEnd) : nil
            if let fence = openingFence(units, line: line) {
                indents.removeAll()
                let code = codeBlock(units, opening: fence, line: line, nextLineStart: nextLineStart)
                blocks.append(code.block)
                nextLineStart = code.nextLineStart
            } else {
                blocks.append(lineBlock(units, line: line, indents: &indents))
            }
            guard let next = nextLineStart else { break }
            lineStart = next
        }
        return blocks
    }

    private static func unit(_ c: Unicode.Scalar) -> UInt16 { UInt16(c.value) }

    private static let space = unit(" ")
    private static let tab = unit("\t")
    private static let lf = unit("\n")
    private static let cr = unit("\r")
    private static let hash = unit("#")
    private static let backtick = unit("`")
    private static let greater = unit(">")
    private static let dash = unit("-")
    private static let star = unit("*")
    private static let plus = unit("+")
    private static let dot = unit(".")
    private static let openBracket = unit("[")
    private static let closeBracket = unit("]")
    private static let lowerX = unit("x")
    private static let upperX = unit("X")
    private static let zero = unit("0")
    private static let nine = unit("9")

    private static func lineEnd(in units: [UInt16], from start: Int) -> Int {
        var i = start
        while i < units.count, units[i] != lf, units[i] != cr { i += 1 }
        return i
    }

    private static func terminatorLength(in units: [UInt16], at index: Int) -> Int {
        if units[index] == cr, index + 1 < units.count, units[index + 1] == lf { return 2 }
        return 1
    }

    private struct Fence {
        var backticks: Range<Int>
        var language: Range<Int>?
    }

    /// At least three backticks after any indent; the trimmed rest of the line is the language.
    private static func openingFence(_ units: [UInt16], line: Range<Int>) -> Fence? {
        guard let backticks = backtickRun(units, line: line) else { return nil }
        var restStart = backticks.upperBound
        var restEnd = line.upperBound
        while restStart < restEnd, isBlank(units[restStart]) { restStart += 1 }
        while restEnd > restStart, isBlank(units[restEnd - 1]) { restEnd -= 1 }
        guard !units[restStart..<restEnd].contains(backtick) else { return nil }
        return Fence(backticks: backticks, language: restStart < restEnd ? restStart..<restEnd : nil)
    }

    /// The first run of three or more backticks, after any indent.
    private static func backtickRun(_ units: [UInt16], line: Range<Int>) -> Range<Int>? {
        var start = line.lowerBound
        while start < line.upperBound, isBlank(units[start]) { start += 1 }
        var end = start
        while end < line.upperBound, units[end] == backtick { end += 1 }
        return end - start >= 3 ? start..<end : nil
    }

    /// A line of only backticks (and surrounding blanks), at least `minimum` of them.
    private static func closingFence(_ units: [UInt16], line: Range<Int>, minimum: Int) -> Range<Int>? {
        guard let backticks = backtickRun(units, line: line), backticks.count >= minimum else { return nil }
        guard units[backticks.upperBound..<line.upperBound].allSatisfy(isBlank) else { return nil }
        return backticks
    }

    private static func isBlank(_ unit: UInt16) -> Bool { unit == space || unit == tab }

    /// Builds the code block that opens on `line`; also returns where scanning resumes (`nil` at the end of the Note).
    private static func codeBlock(
        _ units: [UInt16], opening fence: Fence, line: Range<Int>, nextLineStart: Int?
    ) -> (block: Block, nextLineStart: Int?) {
        let bodyStart = nextLineStart ?? units.count
        var bodyEnd = bodyStart
        var closing: (backticks: Range<Int>, line: Range<Int>)?
        var next = nextLineStart
        while let lineStart = next {
            let end = lineEnd(in: units, from: lineStart)
            let current = lineStart..<end
            next = end < units.count ? end + terminatorLength(in: units, at: end) : nil
            if let backticks = closingFence(units, line: current, minimum: fence.backticks.count) {
                closing = (backticks, current)
                break
            }
            bodyEnd = end
        }
        // The last body line is the one just before the closing fence; a closed block is empty if there is none.
        let rangeEnd = closing?.line.upperBound ?? units.count
        let contentEnd = closing == nil ? units.count : bodyEnd

        var markers = [Span(range: NSRange(fence.backticks), kind: .fence)]
        if let language = fence.language { markers.append(Span(range: NSRange(language), kind: .fenceLanguage)) }
        if contentEnd > bodyStart { markers.append(Span(range: NSRange(bodyStart..<contentEnd), kind: .codeContent)) }
        if let closing { markers.append(Span(range: NSRange(closing.backticks), kind: .fence)) }

        let language = fence.language.map { String(utf16CodeUnits: Array(units[$0]), count: $0.count) }
        return (
            Block(
                kind: .codeBlock(language: language),
                range: NSRange(line.lowerBound..<rangeEnd),
                content: NSRange(bodyStart..<max(contentEnd, bodyStart)),
                markers: markers
            ),
            closing == nil ? nil : next
        )
    }

    /// `indents` is the stack of indent columns of the current series of list items.
    private static func lineBlock(_ units: [UInt16], line: Range<Int>, indents: inout [Int]) -> Block {
        if let item = listItem(units, line: line, indents: &indents) { return item }
        indents.removeAll()
        let range = NSRange(location: line.lowerBound, length: line.count)
        if units[line].allSatisfy(isBlank) {
            return Block(kind: .blank, range: range, content: range)
        }
        if let heading = heading(units, line: line) { return heading }
        if let quote = quote(units, line: line) { return quote }
        return Block(kind: .paragraph, range: range, content: range)
    }

    /// `-`, `*`, `+` or 1–9 digits with `.`, followed by a space; any leading indent.
    private static func listItem(_ units: [UInt16], line: Range<Int>, indents: inout [Int]) -> Block? {
        var markerStart = line.lowerBound
        var indent = 0
        while markerStart < line.upperBound, units[markerStart] == space || units[markerStart] == tab {
            indent += units[markerStart] == tab ? 4 : 1
            markerStart += 1
        }
        guard markerStart < line.upperBound else { return nil }

        let level = nestingLevel(indent: indent, indents: &indents)
        var kind: BlockKind
        var markerEnd = markerStart + 1
        let isBullet = units[markerStart] == dash || units[markerStart] == star || units[markerStart] == plus
        if isBullet {
            kind = .bullet(level: level)
        } else if let number = number(units, from: markerStart, to: line.upperBound) {
            markerEnd = markerStart + number.digits
            guard markerEnd < line.upperBound, units[markerEnd] == dot else { return nil }
            markerEnd += 1
            kind = .ordered(level: level, number: number.value)
        } else {
            return nil
        }
        guard markerEnd < line.upperBound, units[markerEnd] == space else { return nil }
        markerEnd += 1

        var markers = [Span(range: NSRange(location: markerStart, length: markerEnd - markerStart), kind: .listMarker)]
        var contentStart = markerEnd
        if isBullet, let checked = checked(units, at: markerEnd, to: line.upperBound) {
            kind = .task(level: level, checked: checked)
            markers.append(Span(range: NSRange(location: markerEnd, length: 3), kind: .taskCheckbox))
            contentStart = markerEnd + 3
            if contentStart < line.upperBound { contentStart += 1 }
        }

        return Block(
            kind: kind,
            range: NSRange(location: line.lowerBound, length: line.count),
            content: NSRange(location: contentStart, length: line.upperBound - contentStart),
            markers: markers
        )
    }

    /// Checked state of a `[ ]`, `[x]` or `[X]` checkbox, followed by a space or the end of the line.
    private static func checked(_ units: [UInt16], at start: Int, to end: Int) -> Bool? {
        guard start + 3 <= end, units[start] == openBracket, units[start + 2] == closeBracket else { return nil }
        if start + 3 < end, units[start + 3] != space { return nil }
        switch units[start + 1] {
        case space: return false
        case lowerX, upperX: return true
        default: return nil
        }
    }

    /// Level = number of ancestors with a smaller indent in the current series.
    private static func nestingLevel(indent: Int, indents: inout [Int]) -> Int {
        while let top = indents.last, top >= indent { indents.removeLast() }
        let level = indents.count
        indents.append(indent)
        return level
    }

    /// 1–9 ASCII digits starting at `start`.
    private static func number(_ units: [UInt16], from start: Int, to end: Int) -> (value: Int, digits: Int)? {
        var value = 0
        var digits = 0
        while start + digits < end, digits < 9, (zero...nine).contains(units[start + digits]) {
            value = value * 10 + Int(units[start + digits] - zero)
            digits += 1
        }
        guard digits > 0 else { return nil }
        // A tenth digit makes the run too long to be a list number.
        if start + digits < end, (zero...nine).contains(units[start + digits]) { return nil }
        return (value, digits)
    }

    /// `> ` at column 0.
    private static func quote(_ units: [UInt16], line: Range<Int>) -> Block? {
        guard line.count >= 2, units[line.lowerBound] == greater, units[line.lowerBound + 1] == space else { return nil }
        let contentStart = line.lowerBound + 2
        return Block(
            kind: .quote,
            range: NSRange(location: line.lowerBound, length: line.count),
            content: NSRange(location: contentStart, length: line.upperBound - contentStart),
            markers: [Span(range: NSRange(location: line.lowerBound, length: 2), kind: .quoteMarker)]
        )
    }

    /// `#`–`###` at column 0, followed by a space or the end of the line.
    private static func heading(_ units: [UInt16], line: Range<Int>) -> Block? {
        var hashes = 0
        while line.lowerBound + hashes < line.upperBound, units[line.lowerBound + hashes] == hash { hashes += 1 }
        guard (1...3).contains(hashes) else { return nil }
        let afterHashes = line.lowerBound + hashes
        var markerEnd = afterHashes
        if afterHashes < line.upperBound {
            guard units[afterHashes] == space else { return nil }
            markerEnd += 1
        }
        return Block(
            kind: .heading(level: hashes),
            range: NSRange(location: line.lowerBound, length: line.count),
            content: NSRange(location: markerEnd, length: line.upperBound - markerEnd),
            markers: [Span(range: NSRange(location: line.lowerBound, length: markerEnd - line.lowerBound), kind: .headingMarker)]
        )
    }
}
