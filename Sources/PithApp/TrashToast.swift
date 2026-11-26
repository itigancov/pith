import AppKit
import PithNotes

/// The screen that shows the toast on its own `ToastView`.
protocol ToastHost: AnyObject {
    var toastView: ToastView { get }
    /// The toast came up or went (`TrashToast.isShowing` says which).
    func toastDidChange()
}

/// The toast after ⌘⌫, shared by the screens that can delete: one at a time, shown by the screen that started it. It keeps
/// the term (a timer through the scheduler, held while the mouse is on the toast), the Notes Undo brings back, and tells
/// VoiceOver what happened.
final class TrashToast {
    /// "Now" for the term of the toast.
    var now: () -> Date = Date.init

    private let scheduler: Scheduler
    private var model = TrashUndo()
    private weak var host: ToastHost?
    private var timer: Cancellable?
    /// The mouse is on the toast.
    private var isHovered = false

    init(scheduler: Scheduler) {
        self.scheduler = scheduler
    }

    var isShowing: Bool { model.isShowing }
    var text: String? { model.text }

    /// The toast is up, and on `host`.
    func isShowing(on host: ToastHost) -> Bool { model.isShowing && self.host === host }

    /// Shows the toast for `ids` on `host`, in place of the one before. The mouse that was on the old toast is on the new
    /// one, though it sends nothing.
    func show(ids: [UUID], on host: ToastHost) {
        let held = isHovered && model.isShowing
        dismiss()
        model.deleted(ids: ids, now: now())
        guard let text = model.text else { return }
        self.host = host
        host.toastView.show(text)
        host.toastDidChange()
        scheduleTimer()
        if held { hoverChanged(true) }
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    /// The mouse is on the toast or left it; the term of the toast stands while it is on.
    func hoverChanged(_ inside: Bool) {
        guard model.isShowing else { return }
        isHovered = inside
        timer?.cancel()
        timer = nil
        if inside {
            model.pause()
        } else {
            model.resume(now: now())
            scheduleTimer()
        }
    }

    /// The toast is over: the term ended, the text changed, the user left the screen or the Panel is going away.
    func dismiss() {
        guard model.isShowing else { return }
        model.dismiss()
        end()
    }

    /// Undo: the toast ends and the Notes it moved are returned; `nil` when there is no toast.
    func undo() -> [UUID]? {
        let ids = model.undo(now: now())
        end()
        return ids
    }

    private func scheduleTimer() {
        timer?.cancel()
        timer = scheduler.schedule(after: TrashUndo.duration) { [weak self] in self?.dismiss() }
    }

    private func end() {
        // A hidden toast gets no `mouseExited`; the next one starts free.
        isHovered = false
        timer?.cancel()
        timer = nil
        let host = host
        self.host = nil
        host?.toastView.hide()
        host?.toastDidChange()
    }
}

/// The history of the text in a slot or a field. While the toast of the Trash is up, ⌘Z and Edit → Undo are the toast's Undo.
final class ToastUndoManager: UndoManager {
    var isToastUp: () -> Bool = { false }
    var undoToast: () -> Bool = { false }

    override var canUndo: Bool { isToastUp() || super.canUndo }

    override func undo() {
        if isToastUp(), undoToast() { return }
        super.undo()
    }
}
