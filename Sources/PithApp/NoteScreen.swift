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
/// It opens the Note that was open when Pith last hid or quit (else the last of the Stack, or a Blank), pages through
/// the Stack with the footer under the text, restores the cursor and scroll position, saves the text after a pause and
/// everything on `flush()`, and shows the size pill. A Note left empty is deleted when the user leaves it, and at launch and quit.
final class NoteScreen: NSObject, PanelScreen, NSTextViewDelegate {
    static let placeholder = "Start typing, or paste with ⌘V"
    /// `editor.inset`: left, right and top; the bottom is `bottomInset`.
    static let inset: CGFloat = 22
    /// `editor.bottomInset`: room under the last line for the footer of the Stack.
    static let bottomInset: CGFloat = 40

    let editor = EditorTextView()
    let scrollView = NSScrollView()
    let hud: SizeHUDView
    let footer: StackFooterView
    let toast = ToastView()
    let view: NSView
    /// Where the user is in the Stack; read-only for the other screens, which move through `show(noteID:)`.
    private(set) var stack = Stack(ids: [])
    /// Which Note ⌘1 jumps to.
    var latestMeans: () -> Latest
    /// The time for the toast's term.
    var now: () -> Date = Date.init

    var preferredFirstResponder: NSResponder? { editor }
    var usesTextCursor: Bool { true }

    private let openStore: () throws -> (store: NoteStore, recovery: CorruptionRecovery?)
    private let scheduler: Scheduler
    /// Set once the Panel exists; it owns the screen.
    weak var alerts: StorageAlerts?
    private let textSize: TextSizeModel
    /// Where the open Note is kept between launches; `nil` keeps nothing.
    private let defaults: UserDefaults?
    static let openNoteKey = "OpenNote"
    static let latestMeansKey = "LatestMeans"

    private var autosaver: Autosaver?
    /// The notes, once they are open; `nil` while they are not.
    private(set) var store: NoteStore?
    private var swipe = SwipeAccumulator()
    /// The picture of the Note that was left, fading out over the new one.
    private var snapshotView: NSImageView?
    /// The open Note; `nil` for a Blank.
    private var noteID: UUID?
    /// One history per slot, a Note or the Blank; it lives for the session only.
    private var undoManagers: [UUID: UndoManager] = [:]
    private lazy var blankUndoManager = makeUndoManager()
    /// The toast after ⌘⌫, while there is one.
    private var trashUndo = TrashUndo()
    private var toastTimer: Cancellable?
    /// The mouse is on the toast.
    private var isToastHovered = false
    /// A scroll position still to be applied: it needs a laid-out view.
    private var pendingScroll: CGFloat?

    /// - Parameter openStore: Opens the notes; called by `load()` and again by Try Again.
    init(
        openStore: @escaping () throws -> (store: NoteStore, recovery: CorruptionRecovery?),
        scheduler: Scheduler, alerts: StorageAlerts? = nil, textSize: TextSizeModel, defaults: UserDefaults? = nil
    ) {
        self.openStore = openStore
        self.scheduler = scheduler
        self.alerts = alerts
        self.textSize = textSize
        self.defaults = defaults
        latestMeans = {
            defaults?.string(forKey: NoteScreen.latestMeansKey).flatMap(Latest.init(rawValue:)) ?? .newest
        }
        hud = SizeHUDView(scheduler: scheduler)
        footer = StackFooterView(scheduler: scheduler)
        let container = NoteScreenView()
        view = container
        super.init()
        container.onLayout = { [weak self] in self?.applyPendingScroll() }
        container.onScroll = { [weak self] in self?.scrolled($0) ?? false }
        container.onSwipe = { [weak self] in self?.swiped($0) }
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

        footer.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: StackFooterView.height)
        container.addSubview(footer)

        // On the place of the dots of the footer, which are hidden while it is up.
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.onUndo = { [weak self] in self?.undoMoveToTrash() }
        toast.onHover = { [weak self] inside in self?.toastHoverChanged(inside) }
        container.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -StackFooterView.bottom),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
        ])

        hud.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            hud.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
    }

    // MARK: Opening

    /// Opens the notes and shows the Note that was open, deleting the empty ones first. A failure puts up the alert and
    /// locks the editor until Try Again works.
    /// - Parameter start: Where to open instead of the remembered Note.
    func load(start: Stack.Position? = nil) {
        do {
            let (store, recovery) = try openStore()
            let autosaver = Autosaver(
                store: store, scheduler: scheduler,
                onNoteCreated: { [weak self] id in self?.noteWasCreated(id) },
                onSaveFailure: { [weak self] error in self?.alerts?.presentSaveFailureAlert(reason: error.localizedDescription) }
            )
            try store.deleteEmptyNotes()
            var stack = Stack(ids: try store.stack().map(\.id))
            switch start {
            case .blank?: stack = Stack(ids: stack.ids, position: .blank)
            case .note(let id)?: _ = stack.show(id)
            case nil:
                if let remembered = defaults?.string(forKey: Self.openNoteKey).flatMap(UUID.init(uuidString:)) { _ = stack.show(remembered) }
            }
            let note = try stack.position.noteID.flatMap { try store.note(id: $0) }
            self.store = store
            self.autosaver = autosaver
            self.store = store
            self.stack = stack
            show(note)
            refreshFooter(activate: false)
            editor.isEditable = true
            if let recovery { alerts?.presentCorruptionRecoveryAlert(movedFile: recovery.movedFile) }
        } catch {
            store = nil
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
        let undo = note.map { undoManagers[$0.id] ?? makeUndoManager() } ?? makeUndoManager()
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

    /// Saves the open Note and opens the one with `id`, as a page turn. With a `query` the cursor goes to its first match,
    /// selected and in view; without one the Note comes back with the cursor and scroll position it was left with.
    /// Does nothing when the Note is gone.
    func open(id: UUID, query: SearchQuery? = nil) {
        show(noteID: id)
        guard stack.position == .note(id), let query, let first = query.ranges(in: editor.string).first else { return }
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

    // MARK: Paging

    var isAvailable: Bool { store != nil && autosaver != nil }

    func nextNote() { turn { $0.next() } }
    func previousNote() { turn { $0.previous() } }
    func newNote() { turn { $0.newNote() } }

    /// Goes to the Latest Note, the newest or the last edited.
    func goToLatest() {
        turn { [self] stack in stack.latest(currentLatest(of: stack)) }
    }

    /// Goes to the Note `id`, as a page turn: the way back from Search and the Trash.
    func show(noteID id: UUID) { turn { $0.show(id) } }

    /// The one way from one Note to another. `operation` moves a copy of the Stack; the copy replaces the Stack when
    /// the Note it came to is on screen.
    private func turn(_ operation: (inout Stack) -> Stack.Move) {
        guard let store, isAvailable else { return }
        // Composition in progress would be cut by the new text.
        editor.unmarkText()
        // First: it can turn a Blank with text into a Note, which the Stack must know before it moves.
        flush()
        var candidate = stack
        switch operation(&candidate) {
        case .none:
            return
        case .edge:
            dismissToast()
            refreshFooter(activate: true)
        case .moved(let from, let to):
            let incoming: Note?
            switch to {
            case .blank: incoming = nil
            case .note(let id):
                guard let note = try? store.note(id: id) else {
                    refreshFooter(activate: true)
                    return
                }
                incoming = note
            }
            dismissToast()
            installSnapshot()
            if case .note(let old) = from, Note.isEmpty(text: editor.string) {
                // The autosaver moves on first, so that it cannot write the Note that is about to go.
                autosaver?.open(incoming?.id)
                // If the delete fails the Note is still in the store, so it stays in the Stack too.
                if (try? store.deletePermanently(id: old)) != nil {
                    candidate.remove(old)
                    undoManagers[old] = nil
                }
            }
            stack = candidate
            show(incoming)
            fadeSnapshot()
            refreshFooter(activate: true)
        }
    }

    /// Lights the footer for the Stack as it is; `pinned` keeps it lit, for screenshots.
    func activateFooter(pinned: Bool = false) {
        refreshFooter(activate: true, pinned: pinned)
    }

    private func refreshFooter(activate: Bool, pinned: Bool = false) {
        let latest = isAvailable ? currentLatest(of: stack) : nil
        let dots = StackDots.layout(ids: stack.ids, position: stack.position)
        let counter = StackDots.counter(ids: stack.ids, position: stack.position, latest: latest)
        let spoken = StackDots.spoken(ids: stack.ids, position: stack.position, latest: latest)
        if activate {
            footer.activate(dots: dots, counter: counter, spoken: spoken, pinned: pinned)
        } else {
            footer.update(dots: dots, counter: counter, spoken: spoken)
        }
    }

    /// The Latest Note of `stack` by the setting; the last edited one is asked of the store.
    private func currentLatest(of stack: Stack) -> UUID? {
        if latestMeans() == .newest { return stack.ids.last }
        return (try? store?.stack()).flatMap { Latest.lastEdited.id(in: $0) }
    }

    // MARK: Trash

    /// ⌘⌫: the open Note goes to the Trash, and the next one, else the previous, else a Blank takes its place. A Blank goes
    /// back to the previous Note, one whose text was erased is deleted for good: neither shows the toast.
    func moveToTrash() {
        guard let store, isAvailable else { return }
        // Composition in progress would be cut by the new text.
        editor.unmarkText()
        // First: it can turn a Blank with text into a Note, which the Stack must know.
        flush()
        guard let open = stack.position.noteID else {
            if !stack.ids.isEmpty { turn { $0.previous() } }
            return
        }
        if Note.isEmpty(text: editor.string) {
            do {
                try store.deletePermanently(id: open)
            } catch {
                alerts?.presentSaveFailureAlert(reason: error.localizedDescription)
                return
            }
            dismissToast()
            leave([open])
            refreshFooter(activate: true)
            return
        }
        moveToTrash(ids: [open])
    }

    /// Puts the Notes `ids` in the Trash with one toast, "N notes moved to Trash", and one Undo for them all. When the
    /// open Note is among them, the Stack moves to the next one that stays. Ids that are not in the Stack are skipped.
    func moveToTrash(ids: [UUID]) {
        guard let store, isAvailable else { return }
        editor.unmarkText()
        flush()
        let moving = ids.filter { stack.ids.contains($0) }
        guard !moving.isEmpty else { return }
        do {
            try store.moveToTrash(ids: moving)
        } catch {
            alerts?.presentSaveFailureAlert(reason: error.localizedDescription)
            return
        }
        // A toast of the deletion before is replaced; the new one starts after the Notes have left. The mouse that was on
        // the old one is on the new one, though it sends nothing.
        let held = isToastHovered && trashUndo.isShowing
        dismissToast()
        leave(moving)
        refreshFooter(activate: false)
        trashUndo.deleted(ids: moving, now: now())
        guard let text = trashUndo.text else { return }
        toast.show(text)
        footer.isHidden = true
        scheduleToastTimer()
        if held { toastHoverChanged(true) }
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    /// The Notes `gone` are not in the store's Stack any more: the Stack drops them, and if the open one is among them the
    /// next that stays is shown, as a page turn, without lighting the footer.
    private func leave(_ gone: [UUID]) {
        guard let store else { return }
        var candidate = stack
        candidate.remove(gone)
        for id in gone { undoManagers[id] = nil }
        guard let open = stack.position.noteID, gone.contains(open) else {
            stack = candidate
            return
        }
        var incoming: Note?
        if case .note(let id) = candidate.position {
            incoming = try? store.note(id: id)
            if incoming == nil { candidate = Stack(ids: candidate.ids, position: .blank) }
        }
        installSnapshot()
        autosaver?.open(incoming?.id)
        stack = candidate
        show(incoming)
        fadeSnapshot()
    }

    /// Undo of the toast: the Notes come back to their place in the Stack and the first of them opens, with the footer lit.
    /// `false` when there is no toast.
    @discardableResult
    func undoMoveToTrash() -> Bool {
        let ids = trashUndo.undo(now: now())
        endToast()
        guard let store, isAvailable, let ids else { return false }
        do {
            try store.restore(ids: ids)
            stack.reload(ids: try store.stack().map(\.id))
        } catch {
            alerts?.presentSaveFailureAlert(reason: error.localizedDescription)
            return true
        }
        if let first = stack.ids.first(where: ids.contains) { show(noteID: first) }
        return true
    }

    var isToastShowing: Bool { trashUndo.isShowing }
    var toastText: String? { trashUndo.text }

    /// The mouse is on the toast or left it; the term of the toast stands while it is on.
    func toastHoverChanged(_ inside: Bool) {
        guard trashUndo.isShowing else { return }
        isToastHovered = inside
        toastTimer?.cancel()
        toastTimer = nil
        if inside {
            trashUndo.pause()
        } else {
            trashUndo.resume(now: now())
            scheduleToastTimer()
        }
    }

    private func scheduleToastTimer() {
        toastTimer?.cancel()
        toastTimer = scheduler.schedule(after: TrashUndo.duration) { [weak self] in self?.dismissToast() }
    }

    /// The toast is over: the term ended, the text changed, the user turned a page or the Panel is going away.
    private func dismissToast() {
        guard trashUndo.isShowing else { return }
        trashUndo.dismiss()
        endToast()
    }

    private func endToast() {
        // A hidden toast gets no `mouseExited`; the next one starts free.
        isToastHovered = false
        toastTimer?.cancel()
        toastTimer = nil
        toast.hide()
        footer.isHidden = false
    }

    /// The history of a slot: while the toast is up, Undo is the toast's.
    private func makeUndoManager() -> UndoManager {
        let manager = NoteUndoManager()
        manager.isToastUp = { [weak self] in self?.trashUndo.isShowing ?? false }
        manager.undoToast = { [weak self] in self?.undoMoveToTrash() ?? false }
        return manager
    }

    /// Re-reads the Stack from the store, after Notes came back from the Trash. The open Note stays open.
    func reloadStack(activateFooter: Bool) {
        guard let store, isAvailable, let ids = try? store.stack().map(\.id) else { return }
        stack.reload(ids: ids)
        refreshFooter(activate: activateFooter)
    }

    // MARK: Snapshot

    /// Takes the picture of the Note on screen for the fade. A fade still running is part of what is on screen: the old
    /// picture goes into the new one at its current opacity.
    private func installSnapshot() {
        let fading = snapshotView.flatMap { picture in
            picture.image.map { ($0, picture.layer?.presentation()?.opacity ?? Float(picture.alphaValue)) }
        }
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        let bounds = scrollView.bounds
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, bounds.width > 0, bounds.height > 0,
              let rep = scrollView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        scrollView.cacheDisplay(in: bounds, to: rep)
        if let (old, opacity) = fading, opacity > 0, let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            old.draw(in: NSRect(origin: .zero, size: bounds.size), from: .zero, operation: .sourceOver, fraction: CGFloat(opacity))
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        let picture = PassiveImageView(image: image)
        picture.frame = scrollView.frame
        picture.autoresizingMask = [.width, .height]
        picture.imageScaling = .scaleAxesIndependently
        view.addSubview(picture, positioned: .above, relativeTo: scrollView)
        snapshotView = picture
    }

    /// `stack.fade`: the picture goes from opaque to clear over the new Note in 0.15 s.
    private func fadeSnapshot() {
        guard let picture = snapshotView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            picture.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                picture.removeFromSuperview()
                if self?.snapshotView === picture { self?.snapshotView = nil }
            }
        }
    }

    // MARK: Swipe

    /// Two-finger scroll events that the text's scroll view hands up. `true` when the screen took the event.
    private func scrolled(_ event: NSEvent) -> Bool {
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled, isAvailable else { return false }
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        guard let turn = swipe.feed(deltaX: fingers, deltaY: event.scrollingDeltaY, phase: event.phase, momentum: event.momentumPhase) else {
            return false
        }
        if turn == .next { nextNote() } else { previousNote() }
        return true
    }

    /// A three-finger swipe, when the system sends it: one turn.
    private func swiped(_ event: NSEvent) {
        if event.deltaX > 0 { previousNote() } else if event.deltaX < 0 { nextNote() }
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
        stack.noteCreated(id)
        refreshFooter(activate: false)
        // The history of the Blank goes with its text.
        undoManagers[id] = blankUndoManager
        blankUndoManager = makeUndoManager()
    }

    func textDidChange(_ notification: Notification) {
        dismissToast()
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

    // MARK: Context menu

    /// Builds the context menu of the editor: the Note's own commands, with the system's items left out.
    var contextMenu: () -> NSMenu = { NSMenu() }
    /// Looks for misspelled words under a right click; the system's by default.
    lazy var spellChecker: SpellChecking = SystemSpellChecker(documentTag: editor.spellCheckerDocumentTag)

    /// What a correction item replaces and with what.
    private final class Correction: NSObject {
        let range: NSRange
        let text: String
        init(range: NSRange, text: String) {
            self.range = range
            self.text = text
        }
    }

    /// A right click outside the selection puts the caret under the mouse; inside it the selection stays. The system's menu
    /// is dropped; for a misspelled word the corrections and Ignore Spelling come first.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let selection = editor.selectedRange()
        if selection.length == 0 || !NSLocationInRange(charIndex, selection) {
            editor.setSelectedRange(NSRange(location: charIndex, length: 0))
        }
        let result = contextMenu()
        guard editor.isContinuousSpellCheckingEnabled,
              let range = spellChecker.misspelledRange(at: charIndex, in: editor.string) else { return result }
        let text = editor.string
        var items: [NSMenuItem] = []
        let guesses = spellChecker.guesses(for: range, in: text)
        for guess in guesses {
            let item = NSMenuItem(title: guess, action: #selector(applyCorrection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Correction(range: range, text: guess)
            items.append(item)
        }
        if guesses.isEmpty {
            // No action: the item is off.
            items.append(NSMenuItem(title: "No Guesses Found", action: nil, keyEquivalent: ""))
        }
        let ignore = NSMenuItem(title: "Ignore Spelling", action: #selector(ignoreSpelling(_:)), keyEquivalent: "")
        ignore.target = self
        ignore.representedObject = Correction(range: range, text: (text as NSString).substring(with: range))
        items.append(ignore)
        items.append(.separator())
        for (offset, item) in items.enumerated() { result.insertItem(item, at: offset) }
        return result
    }

    /// One step of Undo: the word comes back.
    @objc private func applyCorrection(_ sender: NSMenuItem) {
        guard let correction = sender.representedObject as? Correction else { return }
        editor.insertText(correction.text, replacementRange: correction.range)
    }

    @objc private func ignoreSpelling(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? Correction else { return }
        spellChecker.ignore(word: word.text)
        editor.checkTextInDocument(nil)
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
        dismissToast()
        hud.dismiss()
        footer.reset()
        rememberOpenNote()
    }

    /// The id of the open Note goes to the defaults, so that the next launch opens it; a Blank leaves none.
    private func rememberOpenNote() {
        guard let defaults else { return }
        if let id = stack.position.noteID {
            defaults.set(id.uuidString, forKey: Self.openNoteKey)
        } else {
            defaults.removeObject(forKey: Self.openNoteKey)
        }
    }

    /// The app is quitting: writes what is dirty, deletes the Notes left empty and remembers the open Note, or the last
    /// one if the open one went.
    func willTerminate() {
        flush()
        guard let store else { return }
        let deleted = Set((try? store.deleteEmptyNotes()) ?? [])
        if let open = stack.position.noteID, deleted.contains(open) {
            stack = Stack(ids: stack.ids.filter { !deleted.contains($0) })
        } else {
            for id in deleted { stack.remove(id) }
        }
        rememberOpenNote()
    }

    func willCover() {
        dismissToast()
        flush()
    }

    /// The margins around the text and the space below its last line move the Panel.
    func isDragZone(atWindowPoint point: NSPoint) -> Bool {
        // The toast takes the press, though it lies on the drag area of the footer.
        if trashUndo.isShowing, !toast.isHidden, toast.frame.contains(view.convert(point, from: nil)) { return false }
        if footer.dragArea.contains(footer.convert(point, from: nil)) { return true }
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
    /// Takes a scroll event of the Stack's swipe; `false` passes it on.
    var onScroll: (NSEvent) -> Bool = { _ in false }
    var onSwipe: (NSEvent) -> Void = { _ in }

    // The scroll view hands up the horizontal scrolling it has no use for, which a swipe between pages is.
    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool { axis == .horizontal }

    override func scrollWheel(with event: NSEvent) {
        if !onScroll(event) { super.scrollWheel(with: event) }
    }

    override func swipe(with event: NSEvent) { onSwipe(event) }

    override func layout() {
        super.layout()
        onLayout()
    }
}

/// The picture of the Note that was left: it never takes a click.
private final class PassiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The history of the text in a slot. While the toast of the Trash is up, ⌘Z and Edit → Undo are the toast's Undo.
private final class NoteUndoManager: UndoManager {
    var isToastUp: () -> Bool = { false }
    var undoToast: () -> Bool = { false }

    override var canUndo: Bool { isToastUp() || super.canUndo }

    override func undo() {
        if isToastUp(), undoToast() { return }
        super.undo()
    }
}
