import AppKit

/// Keeps a text storage styled: after every edit of its characters, restyles the Blocks that changed.
public final class Styler: NSObject, NSTextStorageDelegate {
    public private(set) var theme: Theme
    /// Ranges (without the line break) of the Blocks restyled by the last edit.
    public private(set) var restyledRanges: [NSRange] = []
    /// Blocks of the last scan: those of the storage's text after its last edit, except while composing,
    /// when the Styler does not scan.
    private(set) var blocks: [Block] = []

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
        if isComposing {
            pending = pending.map { $0.followed(by: editedRange, delta: delta) } ?? PendingEdit(range: editedRange, delta: delta)
        } else {
            restyle(textStorage, edited: editedRange, delta: delta)
        }
    }

    /// Switches to `theme` and restyles the whole storage with it; the text and its Blocks stay as they are.
    public func apply(_ theme: Theme, to storage: NSTextStorage) {
        self.theme = theme
        attributesCache = [:]
        prefixWidths = [:]
        openingFenceParagraph = theme.paragraphStyle(headIndent: 0, spacingBefore: Theme.codeBlockPadding)
        closingFenceParagraph = theme.paragraphStyle(headIndent: 0, spacingAfter: Theme.codeBlockPadding)
        attach(to: storage)
    }

    // MARK: Composition

    /// Whether input method text is being composed. Meanwhile the Styler leaves attributes alone,
    /// so it neither breaks the composition nor restyles the text around it on every change.
    private(set) var isComposing = false

    /// The edits made since composition began, as one.
    private var pending: PendingEdit?

    /// Holds off restyling until `endComposition(in:)`.
    func beginComposition() {
        isComposing = true
    }

    /// Restyles everything edited since `beginComposition()` in one pass, by the rule of a single edit.
    func endComposition(in storage: NSTextStorage) {
        guard isComposing else { return }
        isComposing = false
        guard let edit = pending else { return }
        pending = nil
        storage.beginEditing()
        restyle(storage, edited: edit.range, delta: edit.delta)
        storage.endEditing()
    }

    /// Rescans the whole Note and restyles each Block that touches `edited` or differs from the last scan.
    private func restyle(_ storage: NSTextStorage, edited: NSRange, delta: Int) {
        let text = storage.string
        let unchanged = shiftedBlocks(edited: edited, delta: delta)
        let scanned = BlockScanner.scan(text)
        var changed: [(block: Block, end: Int)] = []
        for (index, block) in scanned.enumerated() {
            // The Block with its line break; the storage extends an edit through the line break of its paragraph.
            let end = index + 1 < scanned.count ? scanned[index + 1].range.location : storage.length
            let touchesEdit = edited.length == 0
                ? block.range.location <= edited.location && edited.location <= block.range.upperBound
                : block.range.location < edited.upperBound && edited.location < end
            guard touchesEdit || unchanged[block.range.location] != block else { continue }
            changed.append((block, end))
        }
        collapseRuns(of: changed, in: storage)
        for (block, end) in changed {
            restyle(block, through: end, in: storage, text: text)
        }
        restyledRanges = changed.map(\.block.range)
        blocks = scanned
    }

    /// Gives each stretch of adjacent changed Blocks one set of attributes, before they are restyled piece by piece.
    /// The storage keeps its attributes as a flat array of attribute runs: a piece set over many old runs moves all
    /// the runs after it, and restyling a whole Note that way was the hotspot. Over one run, it moves only the few after it.
    private func collapseRuns(of changed: [(block: Block, end: Int)], in storage: NSTextStorage) {
        var stretch: NSRange?
        for (block, end) in changed {
            if let current = stretch, current.upperBound == block.range.location {
                stretch = NSRange(location: current.location, length: end - current.location)
                continue
            }
            if let current = stretch { storage.setAttributes(theme.baseAttributes, range: current) }
            stretch = NSRange(location: block.range.location, length: end - block.range.location)
        }
        if let stretch { storage.setAttributes(theme.baseAttributes, range: stretch) }
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
        let isCode = block.isCodeBlock
        // A code block's body is not parsed for Inline.
        var spans = block.markers + (isCode ? [] : InlineParser.parse(text, in: block.content))
        spans.sort { $0.range.location < $1.range.location || ($0.range.location == $1.range.location && $0.range.length > $1.range.length) }

        // A prefix measured before keeps its width; a new one is measured once it is styled, below.
        let prefix = hangingPrefix(of: block, in: storage)
        let measured = prefix.flatMap { prefixWidths[$0.text] }
        let indent = measured ?? 0

        // Cut the Block into pieces where any Span starts or ends; each piece has one set of covering Spans.
        var cuts = Set([block.range.location, block.range.upperBound, end])
        for span in spans { cuts.formUnion([span.range.location, span.range.upperBound]) }
        let points = cuts.sorted()

        // Each `setAttributes` costs the storage an attribute run, so neighbors of one style go in one call.
        var stretch: (start: Int, style: TextStyle)?
        func flush(upTo stop: Int) {
            guard let stretch else { return }
            storage.setAttributes(attributes(for: stretch.style, headIndent: indent), range: NSRange(location: stretch.start, length: stop - stretch.start))
        }
        for (start, stop) in zip(points, points.dropFirst()) where start < stop {
            let style: TextStyle
            if start >= block.range.upperBound {
                // The line break after the Block.
                style = TextStyle(color: .label)
            } else {
                let kinds = spans.filter { $0.range.location <= start && stop <= $0.range.upperBound }.map(\.kind)
                style = theme.style(block: block.kind, spans: kinds)
            }
            if stretch?.style != style {
                flush(upTo: start)
                stretch = (start, style)
            }
        }
        flush(upTo: end)

        if isCode { padFences(of: block, through: end, in: storage) }

        if let prefix, measured == nil {
            let width = storage.attributedSubstring(from: prefix.range).size().width
            prefixWidths[prefix.text] = width
            let whole = NSRange(location: block.range.location, length: end - block.range.location)
            storage.addAttribute(.paragraphStyle, value: theme.paragraphStyle(headIndent: width), range: whole)
        }
    }

    /// The attributes of `style` in a paragraph with `headIndent`, built once: building fonts and paragraph
    /// styles for every piece of every Block was the hotspot of restyling a whole Note.
    private func attributes(for style: TextStyle, headIndent: CGFloat) -> [NSAttributedString.Key: Any] {
        let key = AttributesKey(style: style, headIndent: headIndent)
        if let cached = attributesCache[key] { return cached }
        var attributes = theme.attributes(for: style)
        attributes[.paragraphStyle] = theme.paragraphStyle(headIndent: headIndent)
        attributesCache[key] = attributes
        return attributes
    }

    private struct AttributesKey: Hashable {
        var style: TextStyle
        var headIndent: CGFloat
    }

    private var attributesCache: [AttributesKey: [NSAttributedString.Key: Any]] = [:]

    /// Widths of the hanging prefixes measured so far, by their text. A prefix's attributes follow from its text alone:
    /// indent spaces in the text font and Markers in mono, whatever the Block's color.
    private var prefixWidths: [String: CGFloat] = [:]

    /// Wrapped lines of a list item, task or quote line up with the text after the prefix: its indent and Marker.
    /// `nil` for the other Blocks, which do not hang.
    private func hangingPrefix(of block: Block, in storage: NSTextStorage) -> (range: NSRange, text: String)? {
        switch block.kind {
        case .bullet, .ordered, .task, .quote:
            let range = NSRange(location: block.range.location, length: block.content.location - block.range.location)
            return (range, storage.mutableString.substring(with: range))
        case .paragraph, .blank, .heading, .codeBlock:
            return nil
        }
    }

    /// Pads a code block's plate above its opening fence and below its closing one: paragraph spacing inside the plate.
    /// An unclosed block runs to the end of the Note and has no bottom padding.
    private func padFences(of block: Block, through end: Int, in storage: NSTextStorage) {
        let text = storage.mutableString
        let lines = block.range
        let first = text.rangeOfCharacter(from: lineBreakCharacters, options: .literal, range: lines)
        guard first.location != NSNotFound else {
            // A lone opening fence: one paragraph, padded on top.
            storage.addAttribute(.paragraphStyle, value: openingFenceParagraph, range: NSRange(location: lines.location, length: end - lines.location))
            return
        }
        var openingEnd = first.upperBound
        if text.character(at: first.location) == carriageReturn, openingEnd < lines.upperBound, text.character(at: openingEnd) == lineFeed {
            openingEnd += 1
        }
        storage.addAttribute(.paragraphStyle, value: openingFenceParagraph, range: NSRange(location: lines.location, length: openingEnd - lines.location))

        let isClosed = block.markers.filter { $0.kind == .fence }.count == 2
        guard isClosed else { return }
        let closingStart = text.rangeOfCharacter(from: lineBreakCharacters, options: [.literal, .backwards], range: lines).upperBound
        storage.addAttribute(.paragraphStyle, value: closingFenceParagraph, range: NSRange(location: closingStart, length: end - closingStart))
    }

    private lazy var openingFenceParagraph = theme.paragraphStyle(headIndent: 0, spacingBefore: Theme.codeBlockPadding)
    private lazy var closingFenceParagraph = theme.paragraphStyle(headIndent: 0, spacingAfter: Theme.codeBlockPadding)
}

/// Edits of the storage merged into one: the range they cover, in the text after them, and their total change in length.
private struct PendingEdit {
    var range: NSRange
    var delta: Int

    /// This edit and then one that replaced `edited.length - delta` units at `edited.location` with `edited.length`.
    func followed(by edited: NSRange, delta change: Int) -> PendingEdit {
        let replacedEnd = edited.location + edited.length - change
        // Where a point of the text before the later edit is after it; one inside the replaced units goes to an end.
        func moved(_ point: Int, inside: Int) -> Int {
            if point <= edited.location { return point }
            if point >= replacedEnd { return point + change }
            return inside
        }
        let start = min(moved(range.location, inside: edited.location), edited.location)
        let end = max(moved(range.upperBound, inside: edited.upperBound), edited.upperBound)
        return PendingEdit(range: NSRange(location: start, length: end - start), delta: delta + change)
    }
}

private let lineBreakCharacters = CharacterSet(charactersIn: "\n\r")
private let lineFeed = UInt16(UnicodeScalar("\n").value)
private let carriageReturn = UInt16(UnicodeScalar("\r").value)
