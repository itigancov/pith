import AppKit
import PithEditor
import PithNotes

/// What the Panel shows when the notes cannot be read or written; `PanelController` puts these on the Panel as sheets.
protocol StorageAlerts: AnyObject {
    func presentCorruptionRecoveryAlert(movedFile: URL)
    func presentOpenFailureAlert(reason: String, canRetry: Bool, onRetry: @escaping () -> Void)
    func presentSaveFailureAlert(reason: String)
}

/// The Note screen: the editor with the open Note, the store it lives in and the autosaver that writes it.
///
/// It opens the latest Note of the Stack (or a Blank), restores the cursor and scroll position, saves the text
/// after a pause and everything on `flush()`, and shows the size pill. The id of the open Note is not kept between launches.
final class NoteScreen: NSObject, PanelScreen, NSTextViewDelegate {
    static let placeholder = "Start typing, or paste with ⌘V"
    /// `editor.inset`: left, right and top; the bottom is `bottomInset`.
    static let inset: CGFloat = 22
    /// `editor.bottomInset`: room under the last line for the footer of the Stack.
    static let bottomInset: CGFloat = 40

    let editor = EditorTextView()
    let scrollView = NSScrollView()
    let hud: SizeHUDView
    let view: NSView

    var preferredFirstResponder: NSResponder? { editor }
    var usesTextCursor: Bool { true }

    private let openStore: () throws -> (store: NoteStore, recovery: CorruptionRecovery?)
    private let scheduler: Scheduler
    /// Set once the Panel exists; it owns the screen.
    weak var alerts: StorageAlerts?
    private let textSize: TextSizeModel

    private var autosaver: Autosaver?
    /// The notes, once they are open; `nil` while they are not.
    private(set) var store: NoteStore?
    /// The open Note; `nil` for a Blank.
    private var noteID: UUID?
    /// One history per slot, a Note or the Blank; it lives for the session only.
    private var undoManagers: [UUID: UndoManager] = [:]
    private var blankUndoManager = UndoManager()
    /// A scroll position still to be applied: it needs a laid-out view.
    private var pendingScroll: CGFloat?

    /// - Parameter openStore: Opens the notes; called by `load()` and again by Try Again.
    init(
        openStore: @escaping () throws -> (store: NoteStore, recovery: CorruptionRecovery?),
        scheduler: Scheduler, alerts: StorageAlerts? = nil, textSize: TextSizeModel
    ) {
        self.openStore = openStore
        self.scheduler = scheduler
        self.alerts = alerts
        self.textSize = textSize
        hud = SizeHUDView(scheduler: scheduler)
        let container = NoteScreenView()
        view = container
        super.init()
        container.onLayout = { [weak self] in self?.applyPendingScroll() }
        configureEditor()
        layOut(in: container)
        editor.theme = Theme(textSize: CGFloat(textSize.size))
        observeChanges({ [textSize] in textSize.size }) { [weak self] size in
            self?.editor.theme = Theme(textSize: CGFloat(size))
        }
    }

    private func configureEditor() {
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.placeholder = Self.placeholder
        editor.delegate = self
        editor.onLayout = { [weak self] in self?.editorDidLayout() }
    }

    private func layOut(in container: NSView) {
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        // The title bar is invisible, so the text starts at the editor's own inset, not below it.
        scrollView.automaticallyAdjustsContentInsets = false
        // The editor's inset gives 22 under the last line; the rest of `bottomInset` is this.
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Self.bottomInset - Self.inset, right: 0)
        scrollView.documentView = editor
        container.addSubview(scrollView)

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewDidScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )

        hud.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            hud.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
    }

    // MARK: Opening

    /// Opens the notes and shows the latest Note. A failure puts up the alert and locks the editor until Try Again works.
    func load() {
        do {
            let (store, recovery) = try openStore()
            let autosaver = Autosaver(
                store: store, scheduler: scheduler,
                onNoteCreated: { [weak self] id in self?.noteWasCreated(id) },
                onSaveFailure: { [weak self] error in self?.alerts?.presentSaveFailureAlert(reason: error.localizedDescription) }
            )
            let latest = try store.stack().last
            let note = try latest.flatMap { try store.note(id: $0.id) }
            self.autosaver = autosaver
            self.store = store
            show(note)
            editor.isEditable = true
            if let recovery { alerts?.presentCorruptionRecoveryAlert(movedFile: recovery.movedFile) }
        } catch {
            autosaver = nil
            store = nil
            editor.isEditable = false
            let canRetry: Bool
            if case NoteStoreError.newerSchema = error { canRetry = false } else { canRetry = true }
            alerts?.presentOpenFailureAlert(reason: error.localizedDescription, canRetry: canRetry) { [weak self] in self?.load() }
        }
    }

    /// Makes `note` (or a Blank for `nil`) the open one, with its cursor, scroll position and own undo history.
    private func show(_ note: Note?) {
        autosaver?.open(note?.id)
        noteID = note?.id
        let undo = note.map { undoManagers[$0.id] ?? UndoManager() } ?? UndoManager()
        if let note { undoManagers[note.id] = undo } else { blankUndoManager = undo }
        editor.string = note?.text ?? ""
        undo.removeAllActions()
        let length = (editor.string as NSString).length
        let location = min(max(note?.selection.location ?? 0, 0), length)
        let selectionLength = min(max(note?.selection.length ?? 0, 0), length - location)
        editor.setSelectedRange(NSRange(location: location, length: selectionLength))
        pendingScroll = CGFloat(note?.scrollOffset ?? 0)
        applyPendingScroll()
    }

    /// Saves the open Note and opens the one with `id`. With a `query` the cursor goes to its first match, selected and
    /// in view; without one the Note comes back with the cursor and scroll position it was left with.
    /// Does nothing when the Note is gone.
    func open(id: UUID, query: SearchQuery? = nil) {
        flush()
        guard let note = (try? store?.note(id: id)) ?? nil else { return }
        show(note)
        guard let query, let first = query.ranges(in: note.text).first else { return }
        editor.setSelectedRange(NSRange(location: first.lowerBound, length: first.count))
        pendingScroll = nil
        scrollSelectionToVisible()
    }

    /// Selects the match of `query` after the selection (before it, `backwards`), wrapping around at the ends of the
    /// text. `false` when the open Note has none.
    func findNext(_ query: SearchQuery, backwards: Bool) -> Bool {
        let ranges = query.ranges(in: editor.string)
        guard !ranges.isEmpty else { return false }
        let selection = editor.selectedRange()
        let found: Range<Int>
        if backwards {
            found = ranges.last { $0.upperBound <= selection.location } ?? ranges[ranges.count - 1]
        } else {
            found = ranges.first { $0.lowerBound >= NSMaxRange(selection) } ?? ranges[0]
        }
        editor.setSelectedRange(NSRange(location: found.lowerBound, length: found.count))
        scrollSelectionToVisible()
        return true
    }

    // MARK: Scroll position

    private var scrollOffset: CGFloat { scrollView.contentView.bounds.origin.y }

    /// Scrolls to the restored position once the view has a size; the offset is as it was, whatever the text size.
    private func applyPendingScroll() {
        guard let offset = pendingScroll, scrollView.contentView.bounds.height > 0 else { return }
        pendingScroll = nil
        guard offset > 0, let layout = editor.textLayoutManager else {
            scrollTo(0)
            return
        }
        let visibleHeight = scrollView.contentView.bounds.height
        // Lays out down to the target only: the estimate for the fragments below it is not good enough to scroll by.
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            fragment.layoutFragmentFrame.maxY < offset + visibleHeight
        }
        // The view's own height catches up with the layout later; the scroll needs room for the target now.
        let laidOut = layout.usageBoundsForTextContainer.maxY + 2 * editor.textContainerInset.height
        if laidOut > editor.frame.height { editor.setFrameSize(NSSize(width: editor.frame.width, height: laidOut)) }
        let contentHeight = editor.frame.height + scrollView.contentInsets.bottom
        let target = min(offset, max(0, contentHeight - visibleHeight))
        scrollTo(target)
        // The first layout of the text view scrolls to the cursor; once it is done, the position goes back.
        restoredScroll = target
    }

    /// The position `applyPendingScroll` set, until the first layout after it has been undone or the user edits.
    private var restoredScroll: CGFloat?

    private func scrollTo(_ offset: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func editorDidLayout() {
        guard let offset = restoredScroll else { return }
        restoredScroll = nil
        if abs(scrollOffset - offset) > 0.5 { scrollTo(offset) }
    }

    // MARK: Saving

    /// Writes everything dirty now. `false` when a write failed; the Panel hides anyway and the alert says why.
    @discardableResult
    func flush() -> Bool {
        autosaver?.flush() ?? true
    }

    /// Replaces the whole text as an edit: it is saved like typing.
    func replaceText(_ text: String) {
        editor.string = text
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
        blankOrNoteUndoManager?.removeAllActions()
        autosaver?.textDidChange(text)
    }

    private var blankOrNoteUndoManager: UndoManager? {
        noteID.flatMap { undoManagers[$0] } ?? blankUndoManager
    }

    private func noteWasCreated(_ id: UUID) {
        noteID = id
        // The history of the Blank goes with its text.
        undoManagers[id] = blankUndoManager
        blankUndoManager = UndoManager()
    }

    func textDidChange(_ notification: Notification) {
        restoredScroll = nil
        autosaver?.textDidChange(editor.string)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        reportViewState()
    }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        reportViewState()
    }

    private func reportViewState() {
        let range = editor.selectedRange()
        autosaver?.viewStateDidChange(
            selection: NoteSelection(location: range.location, length: range.length), scrollOffset: Double(scrollOffset)
        )
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        blankOrNoteUndoManager
    }

    /// Scrolls to the cursor and drops the restored scroll position, for a start with a chosen selection.
    func scrollSelectionToVisible() {
        restoredScroll = nil
        editor.scrollRangeToVisible(editor.selectedRange())
    }

    // MARK: Size pill

    /// Shows the pill; `autoHide: false` keeps it up, for screenshots.
    func showSizeHUD(size: Int, autoHide: Bool = true) {
        hud.show(size: size, autoHide: autoHide)
    }

    // MARK: PanelScreen

    func handleCancel() -> Bool { false }

    func willHide() {
        hud.dismiss()
    }

    func willCover() {
        flush()
    }

    /// The margins around the text and the space below its last line move the Panel.
    func isDragZone(atWindowPoint point: NSPoint) -> Bool {
        let inEditor = editor.convert(point, from: nil)
        guard editor.visibleRect.contains(inEditor) else { return true }
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
}

/// The root view of the Note screen; reports its layout so a restored scroll position can wait for a size.
private final class NoteScreenView: NSView {
    var onLayout: () -> Void = {}

    override func layout() {
        super.layout()
        onLayout()
    }
}
