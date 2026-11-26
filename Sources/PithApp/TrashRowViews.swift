import AppKit
import PithEditor

/// What one row of the Trash shows, ready for a cell.
struct TrashRowDisplay: Equatable {
    var title: String
    var time: String

    var accessibilityLabel: String { [title, time].filter { !$0.isEmpty }.joined(separator: ", ") }
}

/// The colors of the Trash that depend on the theme.
enum TrashStyle {
    /// `trash.empty` and `trash.delete`: #B42318, #FF6B5E in the dark.
    static let red = NSColor(name: "trash.red") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0x6B / 255, blue: 0x5E / 255, alpha: 1)
            : NSColor(srgbRed: 0xB4 / 255, green: 0x23 / 255, blue: 0x18 / 255, alpha: 1)
    }

    /// `trash.restore` background: Ink, #3B5BDB, #4C6EF5 in the dark.
    static let restoreFill = NSColor(name: "trash.restore") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x4C / 255, green: 0x6E / 255, blue: 0xF5 / 255, alpha: 1)
            : NSColor(srgbRed: 0x3B / 255, green: 0x5B / 255, blue: 0xDB / 255, alpha: 1)
    }

    /// `trash.row.hover`
    static func hoveredRow(dark: Bool) -> NSColor { dark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.04) }

    /// `trash.row.selected`, the same as Search's.
    static func selectedRow(dark: Bool) -> NSColor { SearchStyle.selectedRow(dark: dark) }

    /// `trash.delete` background.
    static func deleteFill(dark: Bool) -> NSColor { dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.05) }
}

/// A round button with a symbol: Delete permanently.
final class TrashIconButton: NSView {
    var onPress: () -> Void = {}
    private var isPressed = false
    private let icon = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        icon.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        icon.contentTintColor = TrashStyle.red
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Delete permanently")
        updateLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = SearchStyle.isDark(self)
        layer?.backgroundColor = TrashStyle.deleteFill(dark: dark).cgColor
    }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { isPressed = true; alphaValue = 0.6 }
    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
        alphaValue = isPressed ? 0.6 : 1
    }
    override func mouseUp(with event: NSEvent) {
        let inside = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        alphaValue = 1
        if inside { onPress() }
    }
}

/// "Restore" with an arrow on an Ink pill.
final class TrashRestoreButton: NSView {
    var onPress: () -> Void = {}
    private var isPressed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        icon.contentTintColor = .white
        icon.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: "Restore")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.setAccessibilityElement(false)
        for view in [icon, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Restore")
        updateLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = TrashStyle.restoreFill.cgColor
    }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { isPressed = true; alphaValue = 0.7 }
    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
        alphaValue = isPressed ? 0.7 : 1
    }
    override func mouseUp(with event: NSEvent) {
        let inside = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        alphaValue = 1
        if inside { onPress() }
    }
}

/// The content of a row: title and time on the left, the two buttons on the right while the row is hovered or selected.
final class TrashRowCell: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let delete = TrashIconButton()
    private let restore = TrashRestoreButton()
    private let actions: NSStackView

    var onRestore: (TrashRowCell) -> Void = { _ in }
    var onDelete: (TrashRowCell) -> Void = { _ in }

    /// The buttons are visible: the mouse is on the row, or it is selected.
    var showsActions = false {
        didSet { actions.isHidden = !showsActions }
    }

    override init(frame: NSRect) {
        actions = NSStackView(views: [delete, restore])
        super.init(frame: frame)
        actions.orientation = .horizontal
        actions.spacing = 6
        actions.isHidden = true
        title.font = .systemFont(ofSize: 14)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        time.font = .systemFont(ofSize: 12)
        time.textColor = .secondaryLabelColor
        time.lineBreakMode = .byTruncatingTail
        let texts = NSStackView(views: [title, time])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        for view in [texts, actions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)
        actions.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            texts.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -16),
        ])
        delete.onPress = { [weak self] in if let self { self.onDelete(self) } }
        restore.onPress = { [weak self] in if let self { self.onRestore(self) } }
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ display: TrashRowDisplay) {
        title.stringValue = display.title
        time.stringValue = display.time
        setAccessibilityLabel(display.accessibilityLabel)
    }
}

/// A row with a hover fill and a rounded Ink fill when selected; it tells its cell when to show the buttons.
final class TrashRowView: NSTableRowView {
    private var isHovered = false {
        didSet {
            needsDisplay = true
            updateActions()
        }
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override var isSelected: Bool {
        didSet { updateActions() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func addSubview(_ view: NSView) {
        super.addSubview(view)
        updateActions()
    }

    private func updateActions() {
        for case let cell as TrashRowCell in subviews { cell.showsActions = isHovered || isSelected }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, !isSelected else { return }
        TrashStyle.hoveredRow(dark: SearchStyle.isDark(self)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        TrashStyle.selectedRow(dark: SearchStyle.isDark(self)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        SearchStyle.strokeBorder(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5), in: self)
    }
}

/// The list: ↩ restores, ⌘⌫ deletes for good; both are the screen's, so they never reach the menu.
final class TrashTableView: NSTableView {
    var onReturn: () -> Void = {}
    var onDelete: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.keyCode == 51 {
            onDelete()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
