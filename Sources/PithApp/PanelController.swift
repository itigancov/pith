import AppKit
import PithEditor

/// What the Hotkey does to the Panel.
enum HotkeyAction: Equatable {
    case show, hide, reveal

    /// Hidden: show. Shown and key: hide. Shown without key (the user went to another app): bring it forward and
    /// focus it, never hide; the Panel stays until the user hides it.
    static func decide(isShown: Bool, isKey: Bool) -> HotkeyAction {
        guard isShown else { return .show }
        return isKey ? .hide : .reveal
    }
}

/// Shows and hides the Panel, remembers its frame, keeps its screens and puts storage alerts on it as sheets.
/// It knows only `PanelScreen`: the Note is the bottom screen, others go on top of it.
final class PanelController: NSObject, NSWindowDelegate, StorageAlerts, PanelHosting {
    let panel: PithPanel
    private let content: PanelContentView
    let screens: ScreenStack
    /// Called before the Panel starts hiding, for saving the Note at once.
    var onWillHide: () -> Void = {}
    /// Called when the Panel loses key (not its sheet), for saving the Note at once: the Panel may stay shown.
    var onResignKey: () -> Void = {}

    /// `panel.fade`.
    private static let fadeDuration: TimeInterval = 0.15
    private static let frameKey = "PanelFrame"

    private let defaults: UserDefaults
    /// A fixed content size that replaces the stored one and is never saved (`-PithWindowSize`).
    private let fixedSize: CGSize?
    /// Whether the Panel is shown or on its way in; `false` once a hide starts, even while it fades out.
    private(set) var isShown = false
    /// Bumped by every show and hide, so a fade that finishes late knows it was overtaken.
    private var transition = 0
    /// True while the controller sets the frame itself, so the move is not saved as the user's.
    private var isPlacing = false
    /// Alerts waiting for the Panel to show, oldest first.
    private var pendingAlerts: [(alert: NSAlert, handler: (NSApplication.ModalResponse) -> Void)] = []

    init(note: PanelScreen, defaults: UserDefaults = .standard, fixedSize: CGSize? = nil) {
        self.defaults = defaults
        self.fixedSize = fixedSize
        content = PanelContentView()
        content.show(note)
        screens = ScreenStack(root: note)
        panel = PithPanel(content: content)
        super.init()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }
        screens.onChange = { [weak self] _, new in self?.screenDidChange(to: new) }
    }

    /// The screen on top now.
    var topScreen: PanelScreen { screens.top }

    /// Puts `screen` on top of the others.
    func push(_ screen: PanelScreen) { screens.push(screen) }

    /// Takes `screen` off the stack.
    func pop(_ screen: PanelScreen) { screens.pop(screen) }

    /// Esc: the top screen first; the Panel hides when it leaves Esc alone.
    private func cancel() {
        if !screens.cancel() { hide() }
    }

    private func screenDidChange(to screen: PanelScreen) {
        content.show(screen)
        focusTopScreen()
    }

    /// Focus goes to the top screen, except while a sheet has it.
    private func focusTopScreen() {
        guard panel.attachedSheet == nil, panel.isKeyWindow else { return }
        if let responder = screens.top.preferredFirstResponder { panel.makeFirstResponder(responder) }
    }

    var isKey: Bool { panel.isKeyWindow }

    /// An alert waits for the Panel to show, or is up on it.
    var hasAlert: Bool { panel.attachedSheet != nil || !pendingAlerts.isEmpty }

    /// Shows the Panel, or, if it is shown already, brings it forward where it is, with its waiting alert.
    func reveal() {
        guard isShown, panel.isVisible else {
            show()
            return
        }
        panel.makeKeyAndOrderFront(nil)
        if let sheet = panel.attachedSheet {
            sheet.makeKey()
        } else {
            focusTopScreen()
        }
        presentNextAlert()
    }

    /// The Hotkey: shows a hidden Panel, hides a focused one, focuses a shown one that lost focus. The sheet of an
    /// alert counts as the Panel's own focus.
    func pressHotkey() {
        let isKey = panel.isKeyWindow || panel.attachedSheet?.isKeyWindow == true
        switch HotkeyAction.decide(isShown: isShown, isKey: isKey) {
        case .show: show()
        case .hide: hide()
        case .reveal: reveal()
        }
    }

    /// Shows the Panel on the screen under the mouse, takes key without activating Pith, and shows a waiting alert.
    func show() {
        let wasFadingOut = panel.isVisible && !isShown
        isShown = true
        transition += 1
        // After `NSApp.hide` Pith's windows stay hidden until it is unhidden.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }

        if !wasFadingOut {
            place(on: screenUnderMouse())
            panel.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        if let sheet = panel.attachedSheet {
            sheet.makeKey()
        } else {
            focusTopScreen()
        }
        panel.invalidateShadow()
        fade(to: 1, timing: .easeOut, completion: nil)
        presentNextAlert()
    }

    /// Whether another window of Pith (Settings) is open, so that hiding the Panel must not hide the app.
    var keepsAppVisible: () -> Bool = { false }

    /// Fades the Panel out and orders it out; if Pith was active (say, opened from Finder), gives focus back.
    func hide() {
        guard isShown else { return }
        isShown = false
        transition += 1
        let current = transition
        onWillHide()
        screens.hide()
        fade(to: 0, timing: .easeIn) { [weak self] in
            guard let self, self.transition == current else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            if NSApp.isActive, !self.keepsAppVisible() { NSApp.hide(nil) }
        }
    }

    private func fade(to alpha: CGFloat, timing: CAMediaTimingFunctionName, completion: (@MainActor @Sendable () -> Void)?) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    // MARK: Frame

    /// Forgets the stored frame; a shown Panel moves to the default size in the center of its screen at once.
    @objc func resetPanelFrame(_ sender: Any?) {
        defaults.removeObject(forKey: Self.frameKey)
        if isShown { place(on: panel.screen ?? screenUnderMouse()) }
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func place(on screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { return }
        var stored = storedFrame
        if let fixedSize {
            stored = StoredPanelFrame(width: fixedSize.width, height: fixedSize.height, fx: stored?.fx ?? 0.5, fy: stored?.fy ?? 0.5)
        }
        isPlacing = true
        panel.setFrame(PanelFrame.frame(stored: stored, visibleFrame: visible), display: true)
        isPlacing = false
        panel.invalidateShadow()
    }

    private var storedFrame: StoredPanelFrame? {
        guard let data = defaults.data(forKey: Self.frameKey) else { return nil }
        return try? JSONDecoder().decode(StoredPanelFrame.self, from: data)
    }

    private func saveFrame() {
        guard isShown, !isPlacing, fixedSize == nil, let visible = panel.screen?.visibleFrame else { return }
        let stored = PanelFrame.stored(from: panel.frame, visibleFrame: visible)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.frameKey) }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let visible = sender.screen?.visibleFrame else { return frameSize }
        return NSSize(width: min(frameSize.width, visible.width), height: min(frameSize.height, visible.height))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        panel.invalidateShadow()
        saveFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    // MARK: Losing key

    /// Only the Panel itself: its sheet is not this window.
    func windowDidResignKey(_ notification: Notification) {
        onResignKey()
    }

    // MARK: Storage alerts

    /// The notes file was damaged and set aside as `movedFile`; Show in Finder selects it there.
    func presentCorruptionRecoveryAlert(movedFile: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Pith couldn’t read your notes"
        alert.informativeText = "The notes file was damaged, so Pith set it aside and started a new one. You may be able to restore it from Time Machine."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")
        enqueue(alert) { response in
            if response == .alertSecondButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([movedFile]) }
        }
    }

    /// The notes could not be opened. With `canRetry` the alert shows `reason` and offers Try Again; without it the notes
    /// are from a newer Pith and the only way out is Quit.
    func presentOpenFailureAlert(reason: String, canRetry: Bool, onRetry: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Pith couldn’t open your notes"
        if canRetry {
            alert.informativeText = "\(reason) Your notes file wasn’t changed."
            alert.addButton(withTitle: "Try Again")
        } else {
            alert.informativeText = "Your notes were saved by a newer version of Pith. Update Pith to open them."
        }
        alert.addButton(withTitle: "Quit")
        enqueue(alert) { response in
            if canRetry && response == .alertFirstButtonReturn { onRetry() } else { NSApp.terminate(nil) }
        }
    }

    /// Notes cannot be written: the text stays in memory and Pith keeps trying while it runs.
    func presentSaveFailureAlert(reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Pith couldn’t save your notes"
        alert.informativeText = "\(reason) Pith keeps trying while it runs. Changes since the last save are lost if you quit."
        alert.addButton(withTitle: "OK")
        enqueue(alert) { _ in }
    }

    /// Puts `alert` on the Panel as a sheet, after the ones waiting; `handler` gets the answer.
    func enqueue(_ alert: NSAlert, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        pendingAlerts.append((alert, handler))
        presentNextAlert()
    }

    /// Puts the oldest waiting alert on the Panel while it is shown and has no sheet yet.
    private func presentNextAlert() {
        guard isShown, panel.attachedSheet == nil, !pendingAlerts.isEmpty else { return }
        let (alert, handler) = pendingAlerts.removeFirst()
        alert.beginSheetModal(for: panel) { [weak self] response in
            handler(response)
            guard let self else { return }
            self.focusTopScreen()
            self.presentNextAlert()
        }
    }
}
