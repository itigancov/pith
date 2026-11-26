import AppKit

/// The toast over the footer of the Note screen: "Note moved to Trash" and Undo. It reports the mouse coming and going,
/// so that the screen can hold it.
final class ToastView: NSView {
    static let height: CGFloat = 34

    /// `toast.undo` was pressed.
    var onUndo: () -> Void = {}
    /// The mouse entered (`true`) or left the toast.
    var onHover: (Bool) -> Void = { _ in }

    private let label = NSTextField(labelWithString: "")
    private let undoButton = ToastUndoButton()
    /// Bumped by every show and hide, so that a fade that finishes late knows it was overtaken.
    private var transition = 0

    var text: String { label.stringValue }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.cornerCurve = .continuous
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.shadowRadius = 9
        layer?.masksToBounds = false
        isHidden = true

        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(white: 1, alpha: 0.92)
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        undoButton.onPress = { [weak self] in self?.onUndo() }

        for view in [label, undoButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            undoButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            undoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            undoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(false)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsDidChange), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Showing

    /// Shows the toast with `text`: a fade in of 0.2 s, at once with Reduce Motion.
    func show(_ text: String) {
        transition += 1
        label.stringValue = text
        let wasHidden = isHidden
        isHidden = false
        needsDisplay = true
        updateAppearance()
        guard wasHidden || alphaValue < 1 else { return }
        fade(to: 1, timing: .easeOut, completion: nil)
    }

    /// Takes the toast away: a fade out of 0.2 s, at once with Reduce Motion.
    func hide() {
        guard !isHidden else { return }
        transition += 1
        let current = transition
        fade(to: 0, timing: .easeIn) { [weak self] in
            guard let self, self.transition == current else { return }
            self.isHidden = true
        }
    }

    private func fade(to alpha: CGFloat, timing: CAMediaTimingFunctionName, completion: (@MainActor @Sendable () -> Void)?) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: timing)
            animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    // MARK: Look

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    /// `toast.background`, `toast.edge`, `toast.shadow` and `toast.contrastBorder`.
    private func updateAppearance() {
        PillStyle.apply(
            to: layer, dark: isDark, contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            scale: window?.backingScaleFactor ?? 2
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateAppearance()
    }

    @objc private func displayOptionsDidChange(_ notification: Notification) {
        updateAppearance()
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// "Undo ⌘Z" on a lighter pill inside the toast.
final class ToastUndoButton: NSView {
    var onPress: () -> Void = {}

    private let title = NSTextField(labelWithString: "Undo")
    private let key = NSTextField(labelWithString: "⌘Z")
    private var isPressed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = NSColor(srgbRed: 0x8D / 255, green: 0xA2 / 255, blue: 0xF5 / 255, alpha: 1)
        key.font = .systemFont(ofSize: 13)
        key.textColor = NSColor(white: 1, alpha: 0.55)
        for label in [title, key] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            key.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 6),
            key.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            key.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Undo")
        setAccessibilityHelp("⌘Z")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func setHighlighted(_ highlighted: Bool) {
        layer?.backgroundColor = NSColor(white: 1, alpha: highlighted ? 0.2 : 0.10).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        setHighlighted(true)
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
        setHighlighted(isPressed)
    }

    override func mouseUp(with event: NSEvent) {
        let inside = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        setHighlighted(false)
        if inside { onPress() }
    }
}

/// The look of the dark pill over the content, the toast's and Search's selection pill: `toast.*` and `search.pill.*`.
enum PillStyle {
    static func apply(to layer: CALayer?, dark: Bool, contrast: Bool, scale: CGFloat) {
        layer?.backgroundColor = (dark
            ? NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 64 / 255, alpha: 0.94)
            : NSColor(srgbRed: 32 / 255, green: 32 / 255, blue: 34 / 255, alpha: 0.94)).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = dark ? 0.35 : 0.18
        if contrast {
            layer?.borderWidth = 1 / scale
            layer?.borderColor = NSColor(white: 1, alpha: 0.5).cgColor
        } else if dark {
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        } else {
            layer?.borderWidth = 0
        }
    }
}
