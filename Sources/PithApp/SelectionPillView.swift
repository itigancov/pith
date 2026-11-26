import AppKit

/// The pill under the list of Search while several rows are selected: "3 selected · ⌘⌫ Move to Trash". It is only a hint:
/// it takes no clicks.
final class SelectionPillView: NSView {
    private let count = NSTextField(labelWithString: "")
    private let divider = NSView()
    private let hint = NSTextField(labelWithString: "⌘⌫ Move to Trash")

    /// How many rows are selected, as the pill says.
    var selectedCount = 0 {
        didSet {
            count.stringValue = "\(selectedCount) selected"
            setAccessibilityLabel("\(selectedCount) selected, Command-Delete moves them to Trash")
        }
    }

    /// "3 selected".
    var text: String { count.stringValue }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = ToastView.height / 2
        layer?.cornerCurve = .continuous
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.shadowRadius = 9
        layer?.masksToBounds = false

        count.font = .systemFont(ofSize: 13, weight: .semibold)
        count.textColor = NSColor(white: 1, alpha: 0.92)
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = NSColor(white: 1, alpha: 0.70)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1, alpha: 0.20).cgColor
        for label in [count, hint] {
            label.lineBreakMode = .byTruncatingTail
            label.setAccessibilityElement(false)
        }
        for view in [count, divider, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: ToastView.height),
            count.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: count.trailingAnchor, constant: 12),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 14),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        isHidden = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsDidChange), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The pill never takes a press: it goes to the list under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func updateAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        PillStyle.apply(
            to: layer, dark: dark, contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    @objc private func displayOptionsDidChange(_ notification: Notification) {
        updateAppearance()
    }
}
