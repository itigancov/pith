import AppKit
import PithEditor

/// The Panel's window: takes key and input without activating Pith, floats over every Space and full-screen apps,
/// and has no title bar, buttons or menu commands of its own.
final class PithPanel: NSPanel {
    /// Esc outside input method composition.
    var onCancel: () -> Void = {}

    init(content: PanelContentView) {
        // `.nonactivatingPanel` only takes effect when it is in the style mask from the start.
        super.init(
            contentRect: NSRect(origin: .zero, size: PanelFrame.defaultSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Pith"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // The content view rounds the corners; the window around it stays transparent.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentMinSize = PanelFrame.minimumSize
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel() }

    /// A key the app handles before the menu does; `true` when it did.
    var onKeyEquivalent: (NSEvent) -> Bool = { _ in false }

    // ⌘= is ⌘+ without ⇧; the menu item has the shifted one only.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent(event) { return true }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "=" {
            return NSApp.sendAction(#selector(AppDelegate.increaseTextSize(_:)), to: nil, from: self)
        }
        return super.performKeyEquivalent(with: event)
    }

    /// A press on the margins around the text, or below its last line, moves the Panel; any other event goes on as usual.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let content = contentView as? PanelContentView,
           content.isDragZone(atWindowPoint: event.locationInWindow) {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }
}

/// The Panel's root view: rounded background, the view of the top screen, the cursor in an inactive app,
/// and the contrast border.
final class PanelContentView: NSView {
    static let cornerRadius: CGFloat = 16
    /// `panel.background`.
    static let background = NSColor(name: "panel.background") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x26 / 255, green: 0x26 / 255, blue: 0x28 / 255, alpha: 1)
            : .white
    }
    /// `panel.contrastBorder`, only with Increase Contrast.
    static let contrastBorder = NSColor(name: "panel.contrastBorder") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.5)
            : NSColor(white: 0, alpha: 0.5)
    }

    private(set) var screen: PanelScreen?

    init() {
        super.init(frame: NSRect(origin: .zero, size: PanelFrame.defaultSize))
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        // `.activeAlways`: the standard cursor rects of the text view do not work while Pith is inactive.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `screen`'s view in place of the one before.
    func show(_ screen: PanelScreen) {
        self.screen?.view.removeFromSuperview()
        self.screen = screen
        screen.view.frame = bounds
        screen.view.autoresizingMask = [.width, .height]
        addSubview(screen.view)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // The dynamic colors resolve against the view's appearance while AppKit calls this.
        layer?.backgroundColor = Self.background.cgColor
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            // 1 px whatever the screen's scale.
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

    // MARK: Drag zone and cursor

    /// Whether a press at `point` (window coordinates) moves the Panel: the screen says so for its content, and
    /// the strip along the edges and the scrollers are never part of it.
    func isDragZone(atWindowPoint point: NSPoint) -> Bool {
        let local = convert(point, from: nil)
        // The strip along the edges belongs to the system's resizing.
        guard innerBounds.contains(local) else { return false }
        if isOnScroller(atWindowPoint: point) { return false }
        return screen?.isDragZone(atWindowPoint: point) ?? false
    }

    /// Width of the edge strip where a press resizes the Panel rather than moving it.
    private static let resizeBorder: CGFloat = 6

    /// The bounds without the resizing strip.
    private var innerBounds: NSRect { bounds.insetBy(dx: Self.resizeBorder, dy: Self.resizeBorder) }

    private func isOnScroller(atWindowPoint point: NSPoint) -> Bool {
        // `hitTest` takes a point in the superview's coordinates.
        guard let superview else { return false }
        return hitTest(superview.convert(point, from: nil)) is NSScroller
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private func updateCursor(for event: NSEvent) {
        let point = event.locationInWindow
        let overText = screen?.usesTextCursor == true && innerBounds.contains(convert(point, from: nil))
            && !isOnScroller(atWindowPoint: point) && !isDragZone(atWindowPoint: point)
        if !overText {
            NSCursor.arrow.set()
        } else if NSCursor.current != NSCursor.pointingHand {
            // The editor shows a pointing hand over urls itself.
            NSCursor.iBeam.set()
        }
    }
}
