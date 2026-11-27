import AppKit
import PithNotes

/// The footer of the Note screen: the window of dots and the counter. It lies over the text, never takes a click
/// (its area is the Panel's drag zone) and is lit only for a moment after a move through the Stack.
///
/// Rest: dark dots, no counter. Every `activate` lights it, holds it for 1.2 s from the last one and lets it fade.
final class StackFooterView: NSView {
    /// `footer.bottom`: the bottom of the row of dots above the bottom of the Panel.
    static let bottom: CGFloat = 12
    /// `footer.counterGap`: from the bottom of the counter to the top of the row.
    static let counterGap: CGFloat = 6
    static let height: CGFloat = 40
    /// The widest row: 7 current-size dots and 6 gaps.
    static let maxRowWidth: CGFloat = 7 * 12 + 6 * 5
    static let hold: TimeInterval = 1.2

    private static let rowCenter: CGFloat = 14.5
    private static let gap: CGFloat = 5
    private static let strokeWidth: CGFloat = 1.25

    private static func size(of kind: StackDots.Kind) -> CGSize {
        switch kind {
        case .regular: CGSize(width: 5, height: 5)
        case .current, .blank: CGSize(width: 12, height: 5)
        case .edge: CGSize(width: 3, height: 3)
        }
    }

    /// `dot.alpha`: the ink's alpha of a dot by kind, for rest and active, normal and Increase Contrast.
    static func alpha(of kind: StackDots.Kind, active: Bool, increasedContrast: Bool) -> CGFloat {
        let strong = kind == .current || kind == .blank
        switch (active, increasedContrast) {
        case (false, false): return strong ? 0.25 : 0.12
        case (true, false): return strong ? 0.45 : (kind == .edge ? 0.14 : 0.20)
        case (false, true): return strong ? 0.55 : 0.30
        case (true, true): return strong ? 0.85 : (kind == .edge ? 0.35 : 0.45)
        }
    }

    private let scheduler: Scheduler
    private let counter = NSTextField(labelWithString: "")
    private var dotLayers: [String: CALayer] = [:]
    private var hold: Cancellable?
    private var isPinned = false

    /// The dots on show, left to right.
    private(set) var dots: [StackDots.Dot] = []
    /// Lit: the counter is visible and the dots are dark. `false` from the end of the hold.
    private(set) var isActive = false
    /// The text of the counter, whether visible or not.
    var counterText: String { counter.stringValue }

    init(scheduler: Scheduler) {
        self.scheduler = scheduler
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.height))
        wantsLayer = true
        autoresizingMask = [.width, .maxYMargin]
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        counter.alignment = .center
        counter.alphaValue = 0
        addSubview(counter)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsDidChange), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The area that belongs to the footer, in this view's coordinates: the Panel moves when it is pressed.
    var dragArea: NSRect {
        NSRect(x: (bounds.width - Self.maxRowWidth) / 2, y: 0, width: Self.maxRowWidth, height: Self.height)
    }

    override func layout() {
        super.layout()
        layoutContent(animated: false)
    }

    // MARK: State

    /// Shows `dots` and the counter without lighting the footer: the Panel opens, or a Blank got its first text.
    func update(dots: [StackDots.Dot], counter text: String, spoken: String) {
        apply(dots: dots, counter: text, spoken: spoken, animated: false)
    }

    /// Shows `dots` and the counter and lights the footer; it holds for 1.2 s from now, and fades. With `pinned` it stays lit.
    func activate(dots: [StackDots.Dot], counter text: String, spoken: String, pinned: Bool = false) {
        apply(dots: dots, counter: text, spoken: spoken, animated: true)
        isPinned = pinned
        setActive(true, duration: 0.1, timing: .easeOut)
        hold?.cancel()
        hold = nil
        if !pinned { hold = scheduler.schedule(after: Self.hold) { [weak self] in self?.holdDidEnd() } }
        // Reaches VoiceOver though the footer is not focused.
        Announcer.announce(spoken, priority: .high)
    }

    /// Back to rest at once, for the next time the Panel shows.
    func reset() {
        hold?.cancel()
        hold = nil
        isPinned = false
        isActive = false
        counter.alphaValue = 0
        recolorWithoutAnimation()
    }

    private func holdDidEnd() {
        hold = nil
        setActive(false, duration: 0.25, timing: .easeInEaseOut)
    }

    private func setActive(_ active: Bool, duration: TimeInterval, timing: CAMediaTimingFunctionName) {
        isActive = active
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: timing))
        recolor()
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? duration : 0
            context.timingFunction = CAMediaTimingFunction(name: timing)
            counter.animator().alphaValue = active ? 1 : 0
        }
    }

    private func apply(dots newDots: [StackDots.Dot], counter text: String, spoken: String, animated: Bool) {
        setAccessibilityLabel(spoken)
        counter.stringValue = text
        counter.textColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .labelColor : .secondaryLabelColor
        counter.sizeToFit()
        let motion = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && window != nil
        let old = dots
        dots = newDots
        syncLayers(old: old, animated: motion)
        layoutContent(animated: motion)
        recolor()
    }

    // MARK: Layers

    /// Adds a layer for every new dot and fades out the ones that left the window.
    private func syncLayers(old: [StackDots.Dot], animated: Bool) {
        let keys = Set(dots.map(\.key))
        for (key, layer) in dotLayers where !keys.contains(key) {
            dotLayers[key] = nil
            guard animated else { layer.removeFromSuperlayer(); continue }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
            layer.opacity = 0
            CATransaction.commit()
        }
        for dot in dots where dotLayers[dot.key] == nil {
            let layer = CALayer()
            // The new layer starts invisible at its place; it does not slide in from nowhere.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = animated ? 0 : 1
            self.layer?.addSublayer(layer)
            CATransaction.commit()
            dotLayers[dot.key] = layer
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.15)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                layer.opacity = 1
                CATransaction.commit()
            }
        }
    }

    /// Frames of the dots in a centered row, and the counter above it.
    private func layoutContent(animated: Bool) {
        let widths = dots.map { Self.size(of: $0.kind).width }
        let total = widths.reduce(0, +) + CGFloat(max(dots.count - 1, 0)) * Self.gap
        var x = ((bounds.width - total) / 2).rounded()
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for dot in dots {
            let size = Self.size(of: dot.kind)
            dotLayers[dot.key]?.frame = CGRect(x: x, y: Self.rowCenter - size.height / 2, width: size.width, height: size.height)
            dotLayers[dot.key]?.cornerRadius = min(3, size.height / 2)
            x += size.width + Self.gap
        }
        CATransaction.commit()
        let rowTop = Self.rowCenter + 2.5
        let counterHeight = counter.frame.height
        counter.frame = NSRect(
            x: ((bounds.width - counter.frame.width) / 2).rounded(), y: rowTop + Self.counterGap, width: counter.frame.width, height: counterHeight
        )
    }

    private func recolorWithoutAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        recolor()
        CATransaction.commit()
    }

    /// Ink and alpha of every dot for the state and the theme.
    private func recolor() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink: CGFloat = dark ? 1 : 0
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        for dot in dots {
            guard let layer = dotLayers[dot.key] else { continue }
            let color = CGColor(gray: ink, alpha: Self.alpha(of: dot.kind, active: isActive, increasedContrast: contrast))
            if dot.kind == .blank {
                layer.backgroundColor = nil
                layer.borderColor = color
                layer.borderWidth = Self.strokeWidth
            } else {
                layer.backgroundColor = color
                layer.borderWidth = 0
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolorWithoutAnimation()
    }

    @objc private func displayOptionsDidChange(_ notification: Notification) {
        counter.textColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .labelColor : .secondaryLabelColor
        recolorWithoutAnimation()
    }
}
