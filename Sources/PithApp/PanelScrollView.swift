import AppKit

/// The scroll view of every scrolling area of the Panel (the Note, Search, the Trash): the system's overlay scroller
/// whatever the system setting or the input device. It appears on scrolling, fades out, widens and stays under the pointer,
/// and lies over the content, so it takes no width. Colour and size are the system's.
final class PanelScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerKnobStyle = .default
        scrollerStyle = .overlay
        // The system sets the style again when a mouse or trackpad is attached or removed, or the setting changes.
        // A selector observer goes with the view, no removal is needed.
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferredStyleDidChange), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil
        )
    }

    @objc private func preferredStyleDidChange(_ notification: Notification) {
        scrollerStyle = .overlay
        // The scroll view may take the new preferred style after this observer has run.
        DispatchQueue.main.async { [weak self] in self?.scrollerStyle = .overlay }
    }
}
