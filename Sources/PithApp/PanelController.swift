import AppKit
import PithEditor

/// When the Panel hides on losing key.
enum PanelVisibility {
    /// Whether the Panel hides now that key went to `newKey` (`nil` for another app): it stays only while key is
    /// on the Panel itself or on its own sheet.
    static func shouldHide<Window: AnyObject>(panel: Window, attachedSheet: Window?, newKey: Window?) -> Bool {
        guard let newKey else { return true }
        return newKey !== panel && newKey !== attachedSheet
    }
}

/// Shows and hides the Panel, remembers its frame, and puts storage alerts on it as sheets.
final class PanelController: NSObject, NSWindowDelegate {
    let panel: PithPanel
    let editor: EditorTextView
    /// Called before the Panel starts hiding, for saving the Note at once.
    var onWillHide: () -> Void = {}

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

    init(editor: EditorTextView, defaults: UserDefaults = .standard, fixedSize: CGSize? = nil) {
        self.editor = editor
        self.defaults = defaults
        self.fixedSize = fixedSize
        panel = PithPanel(content: PanelContentView(editor: editor))
        super.init()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKeyAnywhere), name: NSWindow.didResignKeyNotification, object: nil
        )
    }

    func toggle() {
        if isShown { hide() } else { show() }
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
            panel.makeFirstResponder(editor)
        }
        panel.invalidateShadow()
        fade(to: 1, timing: .easeOut, completion: nil)
        presentNextAlert()
    }

    /// Fades the Panel out and orders it out; if Pith was active (say, opened from Finder), gives focus back.
    func hide() {
        guard isShown else { return }
        isShown = false
        transition += 1
        let current = transition
        onWillHide()
        fade(to: 0, timing: .easeIn) { [weak self] in
            guard let self, self.transition == current else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            if NSApp.isActive { NSApp.hide(nil) }
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

    /// The Panel or its sheet lost key. The new key window is known only once the switch is over.
    @objc private func windowDidResignKeyAnywhere(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel || window === panel.attachedSheet else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown else { return }
            if PanelVisibility.shouldHide(panel: self.panel, attachedSheet: self.panel.attachedSheet, newKey: NSApp.keyWindow) {
                self.hide()
            }
        }
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
            // Finder takes key, so the Panel hides by itself.
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

    private func enqueue(_ alert: NSAlert, handler: @escaping (NSApplication.ModalResponse) -> Void) {
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
            if self.panel.isKeyWindow { self.panel.makeFirstResponder(self.editor) }
            self.presentNextAlert()
        }
    }
}
