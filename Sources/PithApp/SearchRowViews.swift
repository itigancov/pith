import AppKit
import PithEditor
import PithNotes

/// What one row of Search shows, ready for a cell.
struct SearchRowDisplay: Equatable {
    var content: NoteRowContent
    var time: String

    var accessibilityLabel: String {
        [content.title, time, content.detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// The colors of Search that depend on the theme, resolved while drawing (so Ink follows the appearance).
enum SearchStyle {
    static func isDark(_ view: NSView) -> Bool {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// `search.field.background`
    static func fieldBackground(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 118 / 255, green: 118 / 255, blue: 128 / 255, alpha: 0.24)
            : NSColor(srgbRed: 116 / 255, green: 116 / 255, blue: 128 / 255, alpha: 0.08)
    }

    /// `search.row.selected`
    static func selectedRow(dark: Bool) -> NSColor { Theme.ink.withAlphaComponent(dark ? 0.18 : 0.12) }

    /// `search.row.active`: the moving end of a selection of several rows.
    static func activeRow(dark: Bool) -> NSColor { Theme.ink.withAlphaComponent(dark ? 0.28 : 0.20) }

    /// The background of a hit in a snippet or a title.
    static func hit(dark: Bool) -> NSColor { Theme.ink.withAlphaComponent(dark ? 0.24 : 0.14) }

    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    /// `search.contrastBorder`, 1 px whatever the screen's scale.
    static func strokeBorder(_ path: NSBezierPath, in view: NSView) {
        guard increaseContrast else { return }
        PanelContentView.contrastBorder.setStroke()
        path.lineWidth = 1 / (view.window?.backingScaleFactor ?? 2)
        path.stroke()
    }
}

/// One line of text with the hits behind it on rounded plates: `NSTextField` cannot round a background.
final class HitTextView: NSView {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer()
    private var hits: [NSRange] = []
    private var font: NSFont = .systemFont(ofSize: 13)

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 1
        container.lineBreakMode = .byTruncatingTail
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameter hits: UTF-16 ranges of `text` to mark.
    func set(_ text: String, hits ranges: [Range<Int>], font: NSFont, color: NSColor, hitFont: NSFont? = nil) {
        self.font = font
        let length = (text as NSString).length
        hits = ranges.compactMap { range in
            let clipped = NSRange(location: range.lowerBound, length: min(range.upperBound, length) - range.lowerBound)
            return clipped.length > 0 ? clipped : nil
        }
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        for hit in hits {
            attributed.addAttributes([.font: hitFont ?? font, .foregroundColor: NSColor.labelColor], range: hit)
        }
        storage.setAttributedString(attributed)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private var lineHeight: CGFloat { ceil(layoutManager.defaultLineHeight(for: font)) }

    override var intrinsicContentSize: NSSize {
        // The unconstrained width; the cell lets the line shrink and truncate.
        let width = storage.length == 0 ? 0 : ceil(storage.size().width)
        return NSSize(width: width, height: lineHeight)
    }

    override var firstBaselineOffsetFromTop: CGFloat { ceil(font.ascender) }

    override func layout() {
        super.layout()
        container.size = NSSize(width: bounds.width, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        container.size = NSSize(width: bounds.width, height: max(bounds.height, lineHeight))
        let glyphs = layoutManager.glyphRange(for: container)
        NSBezierPath(rect: bounds).setClip()
        let color = SearchStyle.hit(dark: SearchStyle.isDark(self))
        for hit in hits {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: hit, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container
            ) { rect, _ in
                // `search.hit`: r 3, one point out on each side.
                color.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: 0), xRadius: 3, yRadius: 3).fill()
            }
        }
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }
}

/// The content of a row: title and time on one baseline, the second line under them.
final class SearchRowCell: NSTableCellView {
    private let title = HitTextView()
    private let time = HitTextView()
    private let detail = HitTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        for label in [title, time, detail] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            time.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            time.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ display: SearchRowDisplay) {
        let content = display.content
        title.set(
            content.title, hits: content.titleHits, font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor
        )
        time.set(display.time, hits: [], font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        detail.set(
            content.detail, hits: content.detailHits, font: .systemFont(ofSize: 13), color: .secondaryLabelColor,
            hitFont: .systemFont(ofSize: 13, weight: .semibold)
        )
        setAccessibilityLabel(display.accessibilityLabel)
    }
}

/// A row with an Ink fill when selected: the system's selection look is switched off here. The row is one of a block of
/// selected rows that touch: only the top of the first and the bottom of the last are rounded, and the fill reaches the
/// row next to it. The row is `SearchScreen.rowPitch` tall, with one point of the 2 between rows above and one below.
final class SearchRowView: NSTableRowView {
    /// Where the selected row sits in its block, and whether it is the active one.
    struct Pick: Equatable {
        var joinsAbove = false
        var joinsBelow = false
        var isActive = false
    }

    /// `nil` for a row that is not selected.
    var pick: Pick? {
        didSet { if pick != oldValue { needsDisplay = true } }
    }

    private static let radius: CGFloat = 10

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard let pick else { return }
        let dark = SearchStyle.isDark(self)
        // The plate lies one point in from the row's edges, except where it joins the next one.
        let top = pick.joinsAbove ? bounds.minY : bounds.minY + 1
        let bottom = pick.joinsBelow ? bounds.maxY : bounds.maxY - 1
        let plate = NSRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
        (pick.isActive ? SearchStyle.activeRow(dark: dark) : SearchStyle.selectedRow(dark: dark)).setFill()
        Self.path(plate, roundTop: !pick.joinsAbove, roundBottom: !pick.joinsBelow, radius: Self.radius).fill()
        // The border goes round the whole block: where the row joins the next one, the line that closes the shape lies
        // outside this view and is cut off.
        let reach: CGFloat = 4
        let minY = pick.joinsAbove ? plate.minY - reach : plate.minY + 0.5
        let maxY = pick.joinsBelow ? plate.maxY + reach : plate.maxY - 0.5
        let edge = NSRect(x: plate.minX + 0.5, y: minY, width: plate.width - 1, height: maxY - minY)
        SearchStyle.strokeBorder(
            Self.path(edge, roundTop: !pick.joinsAbove, roundBottom: !pick.joinsBelow, radius: Self.radius - 0.5), in: self
        )
    }

    /// A rectangle with the corners of its top (the smaller `y`: the view is flipped) and of its bottom rounded or square.
    static func path(_ rect: NSRect, roundTop: Bool, roundBottom: Bool, radius: CGFloat) -> NSBezierPath {
        let top = roundTop ? radius : 0
        let bottom = roundBottom ? radius : 0
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + top, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - top, y: rect.minY))
        if roundTop { path.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.maxX, y: rect.minY + top), radius: radius) }
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bottom))
        if roundBottom { path.appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY), to: NSPoint(x: rect.maxX - bottom, y: rect.maxY), radius: radius) }
        path.line(to: NSPoint(x: rect.minX + bottom, y: rect.maxY))
        if roundBottom { path.appendArc(from: NSPoint(x: rect.minX, y: rect.maxY), to: NSPoint(x: rect.minX, y: rect.maxY - bottom), radius: radius) }
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + top))
        if roundTop { path.appendArc(from: NSPoint(x: rect.minX, y: rect.minY), to: NSPoint(x: rect.minX + top, y: rect.minY), radius: radius) }
        path.close()
        return path
    }
}

/// The list: the screen takes the clicks (it selects by its own rules) and the focus stays in the field.
final class SearchTableView: NSTableView {
    override var acceptsFirstResponder: Bool { false }

    /// A press on a row, with its modifiers and click count.
    var onClick: (_ row: Int, _ modifiers: NSEvent.ModifierFlags, _ clickCount: Int) -> Void = { _, _, _ in }

    // No `super`: the table would select, drag-select and take the focus by itself.
    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return }
        onClick(row, event.modifierFlags.intersection(.deviceIndependentFlagsMask), event.clickCount)
    }
}

/// The field with its container: the magnifier, the input and the hint on the right.
final class SearchFieldView: NSView {
    static let height: CGFloat = 44
    static let margin: CGFloat = 6

    let field = SearchField()
    let trailing = NSTextField(labelWithString: "esc")

    override init(frame: NSRect) {
        super.init(frame: frame)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.textColor = .labelColor
        field.placeholderString = "Search notes"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("Search notes")

        trailing.font = .systemFont(ofSize: 12)
        trailing.textColor = .tertiaryLabelColor
        trailing.setAccessibilityElement(false)

        for view in [icon, field, trailing] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 10),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsDidChange), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        SearchStyle.fieldBackground(dark: SearchStyle.isDark(self)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        SearchStyle.strokeBorder(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5), in: self)
    }

    @objc private func displayOptionsDidChange(_ notification: Notification) {
        needsDisplay = true
    }
}

/// The input: its caret is Ink.
final class SearchField: NSTextField {
    /// The history of the field's text, for as long as the field is edited; while a toast is up, ⌘Z is the toast's.
    var historyManager: UndoManager?

    // The field editor asks its delegate, which is the field, for the undo manager.
    @objc(undoManagerForTextView:)
    func undoManager(for view: NSTextView) -> UndoManager? { historyManager }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.insertionPointColor = Theme.ink
        return accepted
    }
}
