import Foundation

/// Commands of block behavior: Enter continues a list item or quote; indent and outdent nest list items.
///
/// Each returns `nil` when the situation is not its own, so the editor falls back to the standard behavior.
public enum BlockCommands {
    /// Enter: continues the prefix of a list item, task or quote; on an empty one, outdents it or removes the prefix.
    /// `nil` in a paragraph, heading, blank line or code block.
    public static func newline(text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return newline(text: text, replacing: selection) }
        let note = ScannedNote(text)
        guard let index = note.blockIndex(containing: selection.location) else { return nil }
        let block = note.blocks[index]
        if case .quote = block.kind {
            return quoteNewline(note, at: index, caret: selection.location)
        }
        guard var series = Series(note, containing: index), let position = series.position(ofBlock: index),
              let item = series.entries[position].item else { return nil }
        let line = block.range

        if note.isBlank(item.content) {
            if item.level == 0 {
                series.remove(at: position)
                return series.edit(selectingFrom: line.location)
            }
            series.outdentEmptyItem(at: position)
            return series.edit(selectingAfter: line.upperBound)
        }

        let split = max(selection.location, item.content.location)
        let new = series.insertItem(after: position)
        let prefix = note.text.substring(with: item.indent) + series.entries[new].prefix
        let inserted = TextEdit.Replacement(range: NSRange(location: split, length: 0), string: note.lineBreak(of: index) + prefix)
        return series.edit(adding: inserted, selectingAfter: split)
    }

    /// Indent (Tab, ⌘]): nests the list items the selection touches, with their subtrees, one level deeper.
    /// Each item's level is its own: an item may go any number of levels deeper than the one above it.
    /// `nil` when the selection touches no list item.
    public static func indent(text: String, selection: NSRange) -> TextEdit? {
        shift(text: text, selection: selection, by: 1)
    }

    /// Outdent (⇧Tab, ⌘[): moves the list items the selection touches, with their subtrees, one level up.
    /// `nil` when the selection touches no list item; no replacements when all of them are at level 0.
    public static func outdent(text: String, selection: NSRange) -> TextEdit? {
        shift(text: text, selection: selection, by: -1)
    }

    // MARK: Newline

    /// Deletes the selection, then runs Enter at the caret; the result is expressed in the original text.
    private static func newline(text: String, replacing selection: NSRange) -> TextEdit? {
        let deleted = (text as NSString).replacingCharacters(in: selection, with: "")
        guard let edit = newline(text: deleted, selection: NSRange(location: selection.location, length: 0)) else { return nil }
        let caret = selection.location
        var replacements: [TextEdit.Replacement] = []
        // Replacements that touch the caret merge with the deletion into one.
        var merged: (location: Int, end: Int, string: String)?
        for replacement in edit.replacements {
            let range = replacement.range
            if range.upperBound < caret {
                replacements.append(replacement)
            } else if range.location > caret {
                replacements.append(.init(range: NSRange(location: range.location + selection.length, length: range.length), string: replacement.string))
            } else {
                let end = range.upperBound + selection.length
                if let current = merged {
                    merged = (current.location, end, current.string + replacement.string)
                } else {
                    merged = (range.location, end, replacement.string)
                }
            }
        }
        let deletion = merged ?? (caret, selection.upperBound, "")
        replacements.append(.init(range: NSRange(location: deletion.location, length: deletion.end - deletion.location), string: deletion.string))
        replacements.sort(by: TextEdit.Replacement.precedes)
        return TextEdit(replacements: replacements, selection: edit.selection)
    }

    private static func quoteNewline(_ note: ScannedNote, at index: Int, caret: Int) -> TextEdit {
        let block = note.blocks[index]
        if note.isBlank(block.content) {
            return TextEdit(replacements: [.init(range: block.range, string: "")], selection: NSRange(location: block.range.location, length: 0))
        }
        let split = max(caret, block.content.location)
        let inserted = note.lineBreak(of: index) + "> "
        return TextEdit(
            replacements: [.init(range: NSRange(location: split, length: 0), string: inserted)],
            selection: NSRange(location: split + inserted.utf16.count, length: 0)
        )
    }

    // MARK: Indent and outdent

    private static func shift(text: String, selection: NSRange, by delta: Int) -> TextEdit? {
        let note = ScannedNote(text)
        let touched = note.blocks.indices.filter { index in
            let line = note.blocks[index].range
            return selection.length == 0
                ? line.location <= selection.location && selection.location <= line.upperBound
                : line.location < selection.upperBound && selection.location <= line.upperBound
        }
        var seen = Set<Int>()
        var plans: [Series] = []
        for index in touched where !seen.contains(index) {
            guard var series = Series(note, containing: index) else { continue }
            let positions = touched.compactMap(series.position(ofBlock:))
            seen.formUnion(series.entries.compactMap { $0.item?.block })
            for position in positions { series.shift(at: position, by: delta) }
            plans.append(series)
        }
        guard !plans.isEmpty else { return nil }

        let replacements = plans.flatMap { $0.replacements() }.sorted(by: TextEdit.Replacement.precedes)
        let start = map(selection.location, through: replacements, staysBeforeInsertion: selection.length > 0)
        let end = selection.length > 0 ? map(selection.upperBound, through: replacements, staysBeforeInsertion: true) : start
        return TextEdit(replacements: replacements, selection: NSRange(location: start, length: end - start))
    }

    /// Where `location` of the original text ends up after `replacements`.
    /// A location inside a replaced range moves to the end of its new text; one at an insertion point stays before it only if asked.
    static func map(_ location: Int, through replacements: [TextEdit.Replacement], staysBeforeInsertion: Bool) -> Int {
        var offset = 0
        for replacement in replacements {
            let range = replacement.range
            let length = replacement.string.utf16.count
            if location < range.location { break }
            if location == range.location, range.length > 0 || staysBeforeInsertion { break }
            if location < range.upperBound { return range.location + offset + length }
            offset += length - range.length
        }
        return location + offset
    }
}

/// A list item's prefix, split into the parts the Commands rewrite.
struct Item {
    enum Marker: Equatable {
        case bullet(String)
        case number(Int)

        var number: Int? {
            if case .number(let number) = self { number } else { nil }
        }
    }

    var block: Int
    var level: Int
    var marker: Marker
    /// Leading spaces and tabs.
    var indent: NSRange
    /// The digits of a number, or the bullet character; without the `.` and the space.
    var markerText: NSRange
    /// `[ ]`, `[x]` or `[X]`, also after a number.
    var hasCheckbox: Bool
    /// Text after the prefix.
    var content: NSRange
}

/// A Note's text with its Blocks, as the Commands see it.
struct ScannedNote {
    let text: NSString
    let blocks: [Block]

    init(_ text: String) {
        self.text = text as NSString
        self.blocks = BlockScanner.scan(text)
    }

    func blockIndex(containing location: Int) -> Int? {
        blocks.firstIndex { $0.range.location <= location && location <= $0.range.upperBound }
    }

    /// Only spaces and tabs.
    func isBlank(_ range: NSRange) -> Bool {
        (range.location..<range.upperBound).allSatisfy { text.character(at: $0) == space || text.character(at: $0) == tab }
    }

    /// The line break after the Block, else the one before it, else `\n`.
    func lineBreak(of index: Int) -> String {
        for candidate in [index, index - 1] where blocks.indices.contains(candidate) {
            let end = blocks[candidate].range.upperBound
            guard end < text.length else { continue }
            if text.character(at: end) == cr {
                return end + 1 < text.length && text.character(at: end + 1) == lf ? "\r\n" : "\r"
            }
            return "\n"
        }
        return "\n"
    }

    func item(at index: Int) -> Item? {
        let block = blocks[index]
        let level: Int
        let number: Int?
        switch block.kind {
        case .bullet(let l), .task(let l, _): level = l; number = nil
        case .ordered(let l, let n): level = l; number = n
        default: return nil
        }
        guard let listMarker = block.markers.first(where: { $0.kind == .listMarker }) else { return nil }
        // Without the trailing space, and the `.` of a number.
        let markerText = NSRange(location: listMarker.range.location, length: listMarker.range.length - (number == nil ? 1 : 2))
        let marker: Item.Marker = number.map { .number($0) } ?? .bullet(text.substring(with: markerText))

        var hasCheckbox = block.markers.contains { $0.kind == .taskCheckbox }
        var content = block.content
        if !hasCheckbox, number != nil, let box = checkbox(at: content) {
            hasCheckbox = true
            let start = min(box.upperBound + 1, block.range.upperBound)
            content = NSRange(location: start, length: block.range.upperBound - start)
        }
        return Item(
            block: index,
            level: level,
            marker: marker,
            indent: NSRange(location: block.range.location, length: listMarker.range.location - block.range.location),
            markerText: markerText,
            hasCheckbox: hasCheckbox,
            content: content
        )
    }

    /// A checkbox at the start of `content`, followed by a space or the end of the line.
    private func checkbox(at content: NSRange) -> NSRange? {
        guard content.length >= 3 else { return nil }
        let range = NSRange(location: content.location, length: 3)
        guard ["[ ]", "[x]", "[X]"].contains(text.substring(with: range)) else { return nil }
        if content.length > 3, text.character(at: range.upperBound) != space { return nil }
        return range
    }
}

/// One series of consecutive list items and the change planned for it: new levels, markers, inserted and removed items.
struct Series {
    struct Entry {
        /// `nil` for an inserted item.
        var item: Item?
        var level: Int
        var marker: Item.Marker
        var hasCheckbox: Bool
        /// Moved, inserted or removed by the Command itself, not along with a parent.
        var isTarget = false
        /// Moved along with a parent that is a target.
        var isMovedWithParent = false
        var isRemoved = false
        /// The whole prefix after the indent is rewritten.
        var isRetyped = false

        var prefix: String {
            let checkbox = hasCheckbox ? "[ ] " : ""
            switch marker {
            case .bullet(let character): return "\(character) \(checkbox)"
            case .number(let number): return "\(number). \(checkbox)"
            }
        }
    }

    let note: ScannedNote
    private(set) var entries: [Entry]

    init?(_ note: ScannedNote, containing index: Int) {
        guard note.item(at: index) != nil else { return nil }
        var first = index
        while first > 0, note.item(at: first - 1) != nil { first -= 1 }
        var items: [Item] = []
        var next = first
        while next < note.blocks.count, let item = note.item(at: next) {
            items.append(item)
            next += 1
        }
        self.note = note
        self.entries = items.map { Entry(item: $0, level: $0.level, marker: $0.marker, hasCheckbox: $0.hasCheckbox) }
    }

    func position(ofBlock index: Int) -> Int? {
        entries.firstIndex { $0.item?.block == index }
    }

    // MARK: Changes

    /// Inserts an empty item after the one at `position`: same level and marker, the next number, an open checkbox.
    mutating func insertItem(after position: Int) -> Int {
        var new = entries[position]
        new.item = nil
        new.isTarget = true
        if let number = new.marker.number { new.marker = .number(number + 1) }
        entries.insert(new, at: position + 1)
        renumber()
        return position + 1
    }

    /// Removes the item's prefix, leaving its line blank. The other numbers stay: the item leaves the list rather than moves.
    mutating func remove(at position: Int) {
        entries[position].isRemoved = true
    }

    /// Moves an empty item up to its parent's level, or one level up without a parent.
    /// It takes the parent's marker and keeps its own checkbox.
    mutating func outdentEmptyItem(at position: Int) {
        let level = entries[position].level
        guard let parent = entries[..<position].last(where: { $0.level < level }) else {
            return shift(at: position, by: -1)
        }
        shift(at: position, by: parent.level - level)
        entries[position].marker = parent.marker.number.map { .number($0 + 1) } ?? parent.marker
        entries[position].isRetyped = true
        renumber()
    }

    /// Moves the item and its subtree (the following items deeper than it) by `delta` levels,
    /// unless that goes above level 0 or it already moved with its parent.
    mutating func shift(at position: Int, by delta: Int) {
        guard !entries[position].isMovedWithParent else { return }
        let level = entries[position].level
        guard level + delta >= 0 else { return }
        var end = position + 1
        while end < entries.count, entries[end].level > level { end += 1 }
        for index in position..<end {
            entries[index].level += delta
            if index > position { entries[index].isMovedWithParent = true }
        }
        entries[position].isTarget = true
        renumber()
    }

    /// Renumbers the runs of numbered items the change touched: the ones items came to and the ones they left.
    /// A run starts from the first number of the run its first item was in, or from 1 if that item moved there.
    private mutating func renumber() {
        let present = entries.indices.filter { entries[$0].item != nil }
        let before = Self.runs(present.map { index in
            entries[index].item.map { (level: $0.level, isNumbered: $0.marker.number != nil) }
        })
        var beforeRun: [Int: Int] = [:]
        var firstNumber: [Int: Int] = [:]
        for (index, run) in zip(present, before) {
            guard let run else { continue }
            beforeRun[index] = run
            if firstNumber[run] == nil { firstNumber[run] = entries[index].item?.marker.number }
        }
        let left = Set(entries.indices.filter { entries[$0].isTarget }.compactMap { beforeRun[$0] })

        let after = Self.runs(entries.map { $0.isRemoved ? nil : (level: $0.level, isNumbered: $0.marker.number != nil) })
        let touched = Set(entries.indices.compactMap { index -> Int? in
            guard let run = after[index] else { return nil }
            let leftRun = beforeRun[index].map(left.contains) ?? false
            return entries[index].isTarget || leftRun ? run : nil
        })
        var next: [Int: Int] = [:]
        for (index, run) in after.enumerated() {
            guard let run, touched.contains(run) else { continue }
            let number: Int
            if let current = next[run] {
                number = current
            } else if !entries[index].isTarget, let run = beforeRun[index], let first = firstNumber[run] {
                // A list keeps its first number, also when its first item left it.
                number = first
            } else {
                number = 1
            }
            entries[index].marker = .number(number)
            next[run] = number + 1
        }
    }

    /// Run of each node: consecutive numbered items of one level under one parent. A `nil` node breaks every run.
    private static func runs(_ nodes: [(level: Int, isNumbered: Bool)?]) -> [Int?] {
        var open: [Int: Int] = [:]
        var count = 0
        return nodes.map { node in
            guard let node else {
                open.removeAll()
                return nil
            }
            open = open.filter { $0.key < node.level || ($0.key == node.level && node.isNumbered) }
            guard node.isNumbered else { return nil }
            if let run = open[node.level] { return run }
            count += 1
            open[node.level] = count
            return count
        }
    }

    // MARK: Result

    /// The minimal replacements that turn the original lines into the planned ones; inserted items are left out.
    func replacements() -> [TextEdit.Replacement] {
        var result: [TextEdit.Replacement] = []
        for entry in entries {
            guard let item = entry.item else { continue }
            let line = note.blocks[item.block].range
            if entry.isRemoved {
                result.append(.init(range: line, string: ""))
                continue
            }
            // A moved line gets two spaces per level; the indent of the others stays as typed.
            if entry.level != item.level {
                result.append(.init(range: item.indent, string: String(repeating: " ", count: 2 * entry.level)))
            }
            if entry.isRetyped {
                let prefix = NSRange(location: item.markerText.location, length: item.content.location - item.markerText.location)
                result.append(.init(range: prefix, string: entry.prefix))
            } else if let number = entry.marker.number, number != item.marker.number {
                result.append(.init(range: item.markerText, string: String(number)))
            }
        }
        return result
    }

    func edit(selectingFrom location: Int) -> TextEdit {
        let replacements = replacements()
        let caret = BlockCommands.map(location, through: replacements, staysBeforeInsertion: true)
        return TextEdit(replacements: replacements, selection: NSRange(location: caret, length: 0))
    }

    func edit(selectingAfter location: Int) -> TextEdit {
        edit(adding: nil, selectingAfter: location)
    }

    func edit(adding extra: TextEdit.Replacement?, selectingAfter location: Int) -> TextEdit {
        let replacements = (replacements() + [extra].compactMap { $0 }).sorted(by: TextEdit.Replacement.precedes)
        let caret = BlockCommands.map(location, through: replacements, staysBeforeInsertion: false)
        return TextEdit(replacements: replacements, selection: NSRange(location: caret, length: 0))
    }
}

private let space = UInt16(UnicodeScalar(" ").value)
private let tab = UInt16(UnicodeScalar("\t").value)
private let lf = UInt16(UnicodeScalar("\n").value)
private let cr = UInt16(UnicodeScalar("\r").value)
