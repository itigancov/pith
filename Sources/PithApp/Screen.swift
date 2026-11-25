import AppKit

/// One face of the Panel: the Note, and later Search and the Trash. The Panel's controller knows only this protocol.
protocol PanelScreen: AnyObject {
    /// Fills the Panel; the controller sizes it to the Panel's content.
    var view: NSView { get }
    /// What takes keyboard focus when the screen comes up.
    var preferredFirstResponder: NSResponder? { get }
    /// Esc. `true` when the screen took it (a screen above the Note removes itself); `false` lets the Panel hide.
    func handleCancel() -> Bool
    /// The Panel is about to hide with this screen on top.
    func willHide()
    /// Another screen is about to go on top of this one.
    func willCover()
    /// Whether a press at `point` (window coordinates) moves the Panel rather than the screen's own content.
    func isDragZone(atWindowPoint point: NSPoint) -> Bool
    /// Whether the I-beam cursor shows over the screen's content, outside its drag zone.
    var usesTextCursor: Bool { get }
}

extension PanelScreen {
    func willCover() {}
    func isDragZone(atWindowPoint point: NSPoint) -> Bool { false }
    var usesTextCursor: Bool { false }
}

/// The Panel's screens, the Note at the bottom. The top one is shown, gets Esc and keeps the focus.
final class ScreenStack {
    private(set) var screens: [PanelScreen]
    /// The top screen changed from the first to the second.
    var onChange: (_ old: PanelScreen, _ new: PanelScreen) -> Void = { _, _ in }

    init(root: PanelScreen) {
        screens = [root]
    }

    var top: PanelScreen { screens[screens.count - 1] }

    func push(_ screen: PanelScreen) {
        let old = top
        old.willCover()
        screens.append(screen)
        onChange(old, screen)
    }

    /// Removes `screen`, except the Note. Does nothing when it is not on the stack.
    func pop(_ screen: PanelScreen) {
        guard let index = screens.lastIndex(where: { $0 === screen }), index > 0 else { return }
        let old = top
        screens.remove(at: index)
        if top !== old { onChange(old, top) }
    }

    /// Esc: the top screen decides. `false` means the Panel should hide.
    func cancel() -> Bool {
        top.handleCancel()
    }

    /// The Panel hides: the top screen is told, everything above the Note goes, the next show opens on the Note.
    func hide() {
        let old = top
        old.willHide()
        screens.removeSubrange(1...)
        if top !== old { onChange(old, top) }
    }
}
