import AppKit

/// Keeps a text storage styled: after every edit of its characters, restyles the Blocks that changed.
public final class Styler: NSObject, NSTextStorageDelegate {
    public let theme: Theme
    /// Ranges (without the line break) of the Blocks restyled by the last edit.
    public private(set) var restyledRanges: [NSRange] = []
    /// Blocks of the last scan.
    private var blocks: [Block] = []

    public init(theme: Theme = Theme()) {
        self.theme = theme
    }

    /// Becomes the storage's delegate and styles its current text.
    public func attach(to storage: NSTextStorage) {
        storage.delegate = self
        blocks = []
        restyle(storage, edited: NSRange(location: 0, length: storage.length), delta: storage.length)
    }

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        restyle(textStorage, edited: editedRange, delta: delta)
    }

    /// Rescans the whole Note and restyles each Block that touches `edited` or differs from the last scan.
    private func restyle(_ storage: NSTextStorage, edited: NSRange, delta: Int) {
        let text = storage.string
        let unchanged = shiftedBlocks(edited: edited, delta: delta)
        let scanned = BlockScanner.scan(text)
        restyledRanges = []
        for (index, block) in scanned.enumerated() {
            // The Block with its line break; the storage extends an edit through the line break of its paragraph.
            let end = index + 1 < scanned.count ? scanned[index + 1].range.location : storage.length
            let touchesEdit = edited.length == 0
                ? block.range.location <= edited.location && edited.location <= block.range.upperBound
                : block.range.location < edited.upperBound && edited.location < end
            guard touchesEdit || unchanged[block.range.location] != block else { continue }
            restyle(block, through: end, in: storage, text: text)
            restyledRanges.append(block.range)
        }
        blocks = scanned
    }

    /// Blocks of the last scan outside the edit, moved to where they are after it, by location.
    private func shiftedBlocks(edited: NSRange, delta: Int) -> [Int: Block] {
        let oldEditEnd = edited.upperBound - delta
        var result: [Int: Block] = [:]
        for block in blocks {
            if block.range.upperBound < edited.location {
                result[block.range.location] = block
            } else if block.range.location >= oldEditEnd {
                let moved = block.shifted(by: delta)
                result[moved.range.location] = moved
            }
        }
        return result
    }

    /// Restyles `block` and its line break, which runs up to `end`.
    private func restyle(_ block: Block, through end: Int, in storage: NSTextStorage, text: String) {
        let whole = NSRange(location: block.range.location, length: end - block.range.location)
        storage.setAttributes(theme.baseAttributes, range: whole)

        let isCode = block.isCodeBlock
        // A code block's body is not parsed for Inline.
        var spans = block.markers + (isCode ? [] : InlineParser.parse(text, in: block.content))
        spans.sort { $0.range.location < $1.range.location || ($0.range.location == $1.range.location && $0.range.length > $1.range.length) }

        // Cut the Block into pieces where any Span starts or ends; each piece has one set of covering Spans.
        var cuts = Set([block.range.location, block.range.upperBound])
        for span in spans { cuts.formUnion([span.range.location, span.range.upperBound]) }
        let points = cuts.sorted()
        for (start, stop) in zip(points, points.dropFirst()) where start < stop {
            let kinds = spans.filter { $0.range.location <= start && stop <= $0.range.upperBound }.map(\.kind)
            let style = theme.style(block: block.kind, spans: kinds)
            storage.addAttributes(theme.attributes(for: style), range: NSRange(location: start, length: stop - start))
        }
        if isCode { removeBackground(fromLineBreaksIn: block.content, of: storage) }
        storage.addAttribute(.paragraphStyle, value: theme.paragraphStyle(headIndent: headIndent(of: block, in: storage)), range: whole)
    }

    /// Wrapped lines of a list item, task or quote line up with the text after the Marker.
    private func headIndent(of block: Block, in storage: NSTextStorage) -> CGFloat {
        switch block.kind {
        case .bullet, .ordered, .task, .quote:
            let prefix = NSRange(location: block.range.location, length: block.content.location - block.range.location)
            return storage.attributedSubstring(from: prefix).size().width
        case .paragraph, .blank, .heading, .codeBlock:
            return 0
        }
    }

    /// A background drawn behind a line break would mark empty lines of a code block.
    private func removeBackground(fromLineBreaksIn range: NSRange, of storage: NSTextStorage) {
        let text = storage.mutableString
        for location in range.location..<range.upperBound {
            let unit = text.character(at: location)
            if unit == lineFeed || unit == carriageReturn {
                storage.removeAttribute(.backgroundColor, range: NSRange(location: location, length: 1))
            }
        }
    }
}

private let lineFeed = UInt16(UnicodeScalar("\n").value)
private let carriageReturn = UInt16(UnicodeScalar("\r").value)
