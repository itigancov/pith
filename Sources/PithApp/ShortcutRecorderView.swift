import AppKit
import Carbon.HIToolbox

/// Colors and sizes of the recorder, from the design canvas (artboards Settings-Shortcuts and Onboarding-Hotkey).
/// Dark values and the error ring are proposed and wait for the canvas to catch up.
private enum RecorderTheme {
    static func color(light: NSColor, dark: NSColor, name: String) -> NSColor {
        NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static let ink = color(light: rgb(0x3B5BDB), dark: rgb(0x8DA2F5), name: "ink")
    static let error = color(light: rgb(0xD70015), dark: rgb(0xFF453A), name: "recorder.ring.error")
    static let compactFill = color(light: rgb(0xF5F5F5), dark: NSColor(white: 1, alpha: 0.08), name: "recorder.compact.fill")
    static let compactBorder = color(light: NSColor(white: 0, alpha: 0.16), dark: NSColor(white: 1, alpha: 0.16), name: "recorder.compact.border")
    static let largeFill = color(light: rgb(0xFAFAFA), dark: NSColor(white: 1, alpha: 0.08), name: "recorder.large.fill")
    static let largeBorder = color(light: NSColor(white: 0, alpha: 0.12), dark: NSColor(white: 1, alpha: 0.16), name: "recorder.large.border")
    static let keycapFill = color(light: .white, dark: rgb(0x3A3A3C), name: "keycap.fill")
    static let keycapBorder = color(light: NSColor(white: 0, alpha: 0.20), dark: NSColor(white: 1, alpha: 0.14), name: "keycap.border")
    static let keycapText = color(light: rgb(0x1D1D1F), dark: rgb(0xF5F5F7), name: "keycap.text")
    static let placeholder = color(light: rgb(0x6A6A70), dark: rgb(0x98989D), name: "recorder.placeholder")
    static let contrastBorder = color(light: NSColor(white: 0, alpha: 0.5), dark: NSColor(white: 1, alpha: 0.5), name: "recorder.contrastBorder")
}

/// One key of a Shortcut: a modifier glyph or the key itself.
private final class KeycapView: NSView {
    let label: NSTextField
    let compact: Bool
    let isWide: Bool

    init(text: String, compact: Bool) {
        self.compact = compact
        self.isWide = text == "Space"
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: compact ? 12 : 13, weight: .medium)
        label.alignment = .center
        label.textColor = RecorderTheme.keycapText
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override var intrinsicContentSize: NSSize {
        let text = label.intrinsicContentSize
        if isWide { return NSSize(width: compact ? 50 : 64, height: compact ? 22 : 28) }
        let padding: CGFloat = compact ? 12 : 16
        return NSSize(width: max(compact ? 24 : 30, ceil(text.width) + padding), height: compact ? 22 : 28)
    }

    override func layout() {
        super.layout()
        let size = label.intrinsicContentSize
        label.frame = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height).integral
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = compact ? 5 : 6
        layer.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = RecorderTheme.keycapFill.cgColor
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            layer.borderColor = (contrast ? RecorderTheme.contrastBorder : RecorderTheme.keycapBorder).cgColor
            layer.shadowColor = NSColor(white: 0, alpha: 0.10).cgColor
        }
        layer.borderWidth = 0.5
        layer.shadowOpacity = 1
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.shadowRadius = 0
    }
}

/// The pill that shows a Shortcut as keycaps and records a new one. It draws only itself: the text of a rejection goes
/// to `onRejection` and is the host's to show under the row; the Shortcut is the host's to assign, through `onCommit`.
final class ShortcutRecorderView: NSView {
    enum Variant { case compact, large }

    let variant: Variant
    /// The Shortcut shown at rest; the host sets it, and a successful recording sets it too.
    var shortcut: Shortcut { didSet { rebuildKeycaps() } }
    /// Asked with a recorded Shortcut; answers why it cannot be assigned, or `nil` after assigning it.
    var onCommit: (Shortcut) -> Rejection? = { _ in nil }
    /// The text for the row's caption, or `nil` to clear it.
    var onRejection: (String?) -> Void = { _ in }
    /// Called when a recording starts and ends; the host pauses the Hotkey in between.
    var onRecordingChange: (Bool) -> Void = { _ in }

    private let keyLayout: KeyLayout
    private var model = ShortcutRecorderModel()
    private var keycaps: [KeycapView] = []
    private let placeholder = NSTextField(labelWithString: "Type shortcut…")
    private let ring = CALayer()
    private var clickMonitor: Any?
    private var displayObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?

    init(variant: Variant, shortcut: Shortcut, layout: KeyLayout = LiveKeyLayout()) {
        self.variant = variant
        self.shortcut = shortcut
        self.keyLayout = layout
        super.init(frame: .zero)
        wantsLayer = true
        // The ring is drawn outside the pill.
        clipsToBounds = false
        placeholder.font = .systemFont(ofSize: 13)
        placeholder.textColor = RecorderTheme.placeholder
        placeholder.isHidden = true
        addSubview(placeholder)
        ring.opacity = 0
        ring.borderWidth = 4
        layer?.addSublayer(ring)
        rebuildKeycaps()
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshAppearance() } }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    // MARK: State

    var isRecording: Bool { model.isRecording }

    /// Shows a state without any input, for screenshots; the host's caption follows through `onRejection`.
    func showState(_ state: ShortcutRecorderModel.State) {
        let wasRecording = model.isRecording
        model = ShortcutRecorderModel(state: state)
        refreshAppearance()
        onRejection(model.error)
        if wasRecording != model.isRecording { onRecordingChange(model.isRecording) }
    }

    /// Starts the recording the way a click does, for a host that opens the screen already recording.
    func beginRecording() {
        window?.makeFirstResponder(self)
        apply(.begin)
    }

    private func apply(_ input: ShortcutRecorderModel.Input) {
        let wasRecording = model.isRecording
        let oldError = model.error
        var committed = false
        var moveFocus: Bool?
        switch model.handle(input) {
        case .none: break
        case .commit(let candidate):
            let rejection = onCommit(candidate)
            model.resolve(rejection)
            if rejection == nil {
                shortcut = candidate
                committed = true
            }
        case .moveFocus(let reverse): moveFocus = reverse
        }

        refreshAppearance()
        if model.error != oldError {
            onRejection(model.error)
            if let error = model.error { announce(error) }
        }
        if wasRecording != model.isRecording {
            model.isRecording ? startMonitoring() : stopMonitoring()
            onRecordingChange(model.isRecording)
            if model.isRecording {
                announce("Recording shortcut. Press the new combination, or Escape to cancel")
            }
        }
        if committed { announce("Shortcut set to \(shortcut.spokenName(layout: keyLayout))") }
        if let reverse = moveFocus {
            if reverse { window?.selectPreviousKeyView(self) } else { window?.selectNextKeyView(self) }
        }
    }

    // MARK: Events

    override var acceptsFirstResponder: Bool { true }
    /// In the Tab chain with Full Keyboard Access, like other controls.
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled && super.canBecomeKeyView }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        refreshAppearance()
        return true
    }

    override func resignFirstResponder() -> Bool {
        if model.isRecording { apply(.lostFocus) }
        refreshAppearance()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        apply(.click)
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event) { super.keyDown(with: event) }
    }

    /// While recording, every key is the user's answer: ⌘N, ⌘Q and ⌘W reach the checks instead of the menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        model.isRecording && handle(event) ? true : super.performKeyEquivalent(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if model.isRecording { apply(.modifiersOnly) } else { super.flagsChanged(with: event) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(Shortcut.relevantModifiers)
        let code = Int(event.keyCode)
        guard model.isRecording else {
            guard modifiers.isEmpty, [kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter].contains(code) else { return false }
            apply(.begin)
            return true
        }
        if event.isARepeat { return true }
        if modifiers.isEmpty, code == kVK_Escape {
            apply(.escape)
        } else if code == kVK_Tab, modifiers.isEmpty || modifiers == .shift {
            apply(.tab(reverse: modifiers == .shift))
        } else {
            apply(.key(Shortcut(keyCode: UInt32(code), modifiers: modifiers)))
        }
        return true
    }

    /// A click anywhere else, or the window losing key, ends the recording; the click itself still goes where it was aimed.
    private func startMonitoring() {
        stopMonitoring()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            let inside = event.window === self.window && self.bounds.contains(self.convert(event.locationInWindow, from: nil))
            if !inside { self.apply(.lostFocus) }
            return event
        }
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.apply(.lostFocus) } }
        }
    }

    private func stopMonitoring() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    // MARK: Accessibility

    override func accessibilityLabel() -> String? {
        model.isRecording
            ? "Recording shortcut. Press the new combination, or Escape to cancel"
            : "Change shortcut, now \(shortcut.spokenName(layout: keyLayout))"
    }

    override func accessibilityPerformPress() -> Bool {
        apply(.click)
        return true
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    // MARK: Drawing

    private var isCompact: Bool { variant == .compact }
    private static let compactMinimumWidth: CGFloat = 120

    override var intrinsicContentSize: NSSize {
        if !isCompact { return NSSize(width: 360, height: 44) }
        let width = keycaps.reduce(0) { $0 + $1.intrinsicContentSize.width } + CGFloat(max(keycaps.count - 1, 0)) * 4 + 8
        return NSSize(width: max(width, Self.compactMinimumWidth), height: 28)
    }

    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        let gap: CGFloat = isCompact ? 4 : 6
        let total = keycaps.reduce(0) { $0 + $1.intrinsicContentSize.width } + CGFloat(max(keycaps.count - 1, 0)) * gap
        var x = isCompact ? 4 : (bounds.width - total) / 2
        for keycap in keycaps {
            let size = keycap.intrinsicContentSize
            keycap.frame = NSRect(x: x.rounded(), y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
            x += size.width + gap
        }
        let text = placeholder.intrinsicContentSize
        placeholder.frame = NSRect(x: 10, y: ((bounds.height - text.height) / 2).rounded(), width: bounds.width - 20, height: text.height)
        let outset: CGFloat = isCompact ? 4 : 3
        ring.frame = bounds.insetBy(dx: -outset, dy: -outset)
        ring.cornerRadius = (isCompact ? 6 : 8) + outset
        ring.cornerCurve = .continuous
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = isCompact ? 6 : 8
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let recording = model.isRecording
        let focused = window?.firstResponder === self
        let failing = model.error != nil
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = (isCompact ? RecorderTheme.compactFill : RecorderTheme.largeFill).cgColor
            var border = isCompact ? RecorderTheme.compactBorder : RecorderTheme.largeBorder
            if contrast { border = RecorderTheme.contrastBorder }
            // The compact ring replaces the border with 1 pt of its color; the large one covers it.
            let ringColor = failing ? RecorderTheme.error : RecorderTheme.ink
            if isCompact, recording || focused { border = ringColor }
            layer.borderColor = border.cgColor
            ring.borderColor = ringColor.withAlphaComponent(isCompact ? 0.22 : 0.28).cgColor
        }
        layer.borderWidth = isCompact ? (recording || focused ? 1 : 0.5) : 1
        let target: Float = recording || focused ? 1 : 0
        if ring.opacity != target {
            CATransaction.begin()
            CATransaction.setAnimationDuration(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            ring.opacity = target
            CATransaction.commit()
        }
    }

    private func refreshAppearance() {
        let showsPlaceholder = isCompact && model.isRecording
        placeholder.isHidden = !showsPlaceholder
        for keycap in keycaps { keycap.isHidden = showsPlaceholder }
        needsLayout = true
        needsDisplay = true
        for keycap in keycaps { keycap.needsDisplay = true }
    }

    private func rebuildKeycaps() {
        for keycap in keycaps { keycap.removeFromSuperview() }
        keycaps = shortcut.chips(layout: keyLayout).map { KeycapView(text: $0, compact: isCompact) }
        for keycap in keycaps { addSubview(keycap) }
        invalidateIntrinsicContentSize()
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}
