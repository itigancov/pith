import AppKit
import PithEditor
import PithNotes

/// The pill that shows the text size when it changes: small A, a slider, big A and "N pt".
/// It sits over the Note for a second, then fades.
final class SizeHUDView: NSView {
    static let height: CGFloat = 36
    static let hold: TimeInterval = 1
    static let fadeDuration: TimeInterval = 0.15
    /// `hud.background`: the Panel's light gray in light, a lifted dark gray in dark; 96 % opaque.
    static let background = NSColor(name: "hud.background") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 0.96)
            : NSColor(srgbRed: 246 / 255, green: 246 / 255, blue: 245 / 255, alpha: 0.96)
    }
    /// `hud.contrastBorder`, only with Increase Contrast.
    static let contrastBorder = NSColor(name: "hud.contrastBorder") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.5)
            : NSColor(white: 0, alpha: 0.5)
    }

    /// How full the slider is for `size`: the position of the size in the range of sizes.
    static func fraction(for size: Int) -> CGFloat {
        let range = TextSizeModel.range
        let clamped = min(max(size, range.lowerBound), range.upperBound)
        return CGFloat(clamped - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }

    /// What VoiceOver says and the pill reads.
    static func announcement(for size: Int) -> String { "Text size \(size) points" }

    private let slider = SizeSliderView()
    private let valueLabel = NSTextField(labelWithString: "")
    private let scheduler: Scheduler
    private var hold: Cancellable?
    /// Bumped by every show, so a fade that finishes late knows it was overtaken.
    private var generation = 0
    private(set) var size = TextSizeModel.defaultSize

    init(scheduler: Scheduler = TaskScheduler()) {
        self.scheduler = scheduler
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.cornerCurve = .continuous
        isHidden = true
        alphaValue = 0

        func letter(_ size: CGFloat) -> NSTextField {
            let label = NSTextField(labelWithString: "A")
            label.font = .systemFont(ofSize: size)
            label.textColor = .secondaryLabelColor
            return label
        }
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = .labelColor
        let row = NSStackView(views: [letter(11), slider, letter(16), valueLabel])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
            slider.widthAnchor.constraint(equalToConstant: 96),
            slider.heightAnchor.constraint(equalToConstant: 4),
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityElement(false)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsDidChange), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Self.background.cgColor
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
            layer?.borderColor = Self.contrastBorder.cgColor
        } else {
            layer?.borderWidth = 0
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    @objc private func displayOptionsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    /// Shows the pill for `size` and holds it for a second; a new call starts the second again. Without `autoHide` it stays.
    func show(size: Int, autoHide: Bool = true) {
        self.size = size
        valueLabel.stringValue = "\(size) pt"
        slider.fraction = Self.fraction(for: size)
        let text = Self.announcement(for: size)
        setAccessibilityLabel(text)
        setAccessibilityElement(true)
        generation += 1
        isHidden = false
        alphaValue = 1
        // Reaches VoiceOver even though the pill is not focused.
        Announcer.announce(text, priority: .medium)
        hold?.cancel()
        hold = nil
        if autoHide { hold = scheduler.schedule(after: Self.hold) { [weak self] in self?.fadeOut() } }
    }

    /// Hides the pill at once, without a fade.
    func dismiss() {
        hold?.cancel()
        generation += 1
        alphaValue = 0
        isHidden = true
        setAccessibilityElement(false)
    }

    private func fadeOut() {
        hold = nil
        let current = generation
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, self.generation == current else { return }
            self.isHidden = true
            self.setAccessibilityElement(false)
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            alphaValue = 0
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { finish() }
        }
    }
}

/// The slider of the pill: a 4 pt track with Ink up to `fraction`. Nothing is dragged.
private final class SizeSliderView: NSView {
    var fraction: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        // The track: 12 % of black, of white in dark.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.12)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        Theme.ink.setFill()
        let fill = NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
