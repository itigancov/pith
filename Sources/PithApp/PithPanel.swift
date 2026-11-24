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

/// The Panel's root view: rounded background, the editor in its scroll view, the cursor in an inactive app,
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

    let editor: EditorTextView
    let scrollView = NSScrollView()

    init(editor: EditorTextView) {
        self.editor = editor
        super.init(frame: NSRect(origin: .zero, size: PanelFrame.defaultSize))
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        // The title bar is invisible, so the text starts at the editor's own inset, not below it.
        scrollView.automaticallyAdjustsContentInsets = false
        editor.drawsBackground = false
        scrollView.documentView = editor
        addSubview(scrollView)

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

    /// Whether a press at `point` (window coordinates) moves the Panel: it is in the editor's inset around the text
    /// or below the last line, and not on a scroller.
    func isDragZone(atWindowPoint point: NSPoint) -> Bool {
        let local = convert(point, from: nil)
        guard bounds.contains(local) else { return false }
        if hitTest(local) is NSScroller { return false }
        let inEditor = editor.convert(point, from: nil)
        let visible = editor.visibleRect
        guard visible.contains(inEditor) else { return true }
        let inset = editor.textContainerInset
        if inEditor.x < inset.width || inEditor.x > editor.bounds.width - inset.width { return true }
        if inEditor.y < inset.height { return true }
        return inEditor.y > textBottom
    }

    /// The bottom of the last laid-out line in the editor's coordinates; the first line's height for an empty Note.
    private var textBottom: CGFloat {
        guard let layout = editor.textLayoutManager else { return .greatestFiniteMagnitude }
        var bottom = layout.usageBoundsForTextContainer.maxY
        layout.enumerateTextLayoutFragments(from: layout.documentRange.endLocation, options: [.reverse]) { fragment in
            bottom = max(bottom, fragment.layoutFragmentFrame.maxY)
            return false
        }
        if bottom <= 0, let font = editor.typingAttributes[.font] as? NSFont {
            bottom = font.ascender - font.descender + font.leading
        }
        return editor.textContainerOrigin.y + bottom
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
        if isDragZone(atWindowPoint: event.locationInWindow) || hitTest(convert(event.locationInWindow, from: nil)) is NSScroller {
            NSCursor.arrow.set()
        } else if NSCursor.current != NSCursor.pointingHand {
            // The editor shows a pointing hand over urls itself.
            NSCursor.iBeam.set()
        }
    }
}
