import AppKit
import PithNotes

/// The Search screen: a field over the list of Notes that match it, most recently edited first.
///
/// The focus stays in the field; ↑↓ and ↩ are taken from it. Every change of the query searches at once.
final class SearchScreen: NSObject, PanelScreen, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, ToastHost {
    /// The height of a row's plate.
    static let rowHeight: CGFloat = 56
    /// The height of a row of the table: the plate and, half above and half below it, the 2 between rows (`search.row`).
    static let rowPitch: CGFloat = rowHeight + 2
    /// `search.list.bottomInset`: from the bottom of the Panel to the last row, while the pill or the toast is up.
    static let bottomInset: CGFloat = 12 + ToastView.height + 6
    private static let cellID = NSUserInterfaceItemIdentifier("SearchRow")

    let view: NSView
    private let header = SearchFieldView()
    private let scrollView = NSScrollView()
    let table = SearchTableView()
    private let pill = SelectionPillView()
    let toastView = ToastView()
    private let emptyContainer = NSView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyDetail = NSTextField(labelWithString: "")

    var field: NSTextField { header.field }
    var preferredFirstResponder: NSResponder? { header.field }

    private let store: NoteStore
    private let now: () -> Date
    private let locale: Locale
    private let calendar: Calendar

    /// Opens the selected Note. The screen has already reported its query through `onDismiss`.
    var onOpen: (_ id: UUID, _ query: SearchQuery) -> Void = { _, _ in }
    /// The screen is going away for any reason, with the query as typed.
    var onDismiss: (_ query: String) -> Void = { _ in }
    /// Takes the screen off the stack.
    var close: () -> Void = {}
    /// Puts the Notes in the Trash, without a toast, and returns those that went.
    var moveToTrash: (_ ids: [UUID]) -> [UUID] = { _ in [] }
    /// Notes came back from the Trash through Undo.
    var onRestored: () -> Void = {}
    /// A write failed; the reason goes to the user.
    var onFailure: (String) -> Void = { _ in }

    private let trashToast: TrashToast
    private var dismissed = false
    private(set) var results: [NoteSummary] = []
    private(set) var selection = RowSelection(count: 0)
    /// The history of the field's text: while the toast is up, ⌘Z is the toast's Undo.
    private let fieldHistory = ToastUndoManager()
    private var spokenCount = 0
    private var searchFailed = false
    private var parsed = SearchQuery("")
    private var searchedAt = Date()
    /// The text of the rows shown so far, for as long as the Note is as it was.
    private var texts: [UUID: (updatedAt: Date, text: String)] = [:]

    init(
        store: NoteStore, toast: TrashToast, now: @escaping () -> Date = Date.init, locale: Locale = .current,
        calendar: Calendar = .current
    ) {
        self.store = store
        trashToast = toast
        self.now = now
        self.locale = locale
        self.calendar = calendar
        view = SearchScreenRootView()
        super.init()
        layOut()
        header.field.delegate = self
        header.field.historyManager = fieldHistory
        fieldHistory.isToastUp = { [weak self] in self?.isToastShowing ?? false }
        fieldHistory.undoToast = { [weak self] in self?.undoMoveToTrash() ?? false }
        toastView.onUndo = { [weak self] in self?.undoMoveToTrash() }
        toastView.onHover = { [weak self] inside in self?.trashToast.hoverChanged(inside) }
        table.onClick = { [weak self] row, modifiers, count in self?.click(row: row, modifiers: modifiers, clickCount: count) }
        refresh()
    }

    // MARK: Layout

    private func layOut() {
        let margin = SearchFieldView.margin
        table.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        // The 2 between rows belong to the rows: a block of selected rows is painted through them.
        table.rowHeight = Self.rowPitch
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        // The selection is `RowSelection`'s; the table only shows it, and it is empty after ⌘-click took out the last row.
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = true
        table.allowsTypeSelect = false
        table.focusRingType = .none
        table.usesAutomaticRowHeights = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Notes")

        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()

        emptyTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        emptyTitle.textColor = .secondaryLabelColor
        emptyDetail.font = .systemFont(ofSize: 13)
        emptyDetail.textColor = .tertiaryLabelColor
        for label in [emptyTitle, emptyDetail] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
        }
        let emptyStack = NSStackView(views: [emptyTitle, emptyDetail])
        emptyStack.orientation = .vertical
        emptyStack.spacing = 6
        emptyStack.alignment = .centerX
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            emptyStack.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyContainer.leadingAnchor, constant: 24),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: emptyContainer.trailingAnchor, constant: -24),
        ])

        for subview in [header, scrollView, emptyContainer, pill, toastView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        // The pill and the toast take the same place, as the toast takes the footer's in the Note.
        for floating in [pill, toastView] {
            NSLayoutConstraint.activate([
                floating.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                floating.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -StackFooterView.bottom),
                floating.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
                floating.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            ])
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            header.heightAnchor.constraint(equalToConstant: SearchFieldView.height),
            // The first plate is one point down in its row.
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: margin - 1),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),
            // The message sits 25 above the middle of the room under the field: 50 of padding below it.
            emptyContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: margin),
            emptyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
        ])
    }

    // MARK: Query and results

    /// What is in the field.
    var query: String { header.field.stringValue }

    /// Replaces the text of the field and searches, as typing does.
    func setQuery(_ text: String) {
        header.field.stringValue = text
        refresh()
    }

    func controlTextDidChange(_ notification: Notification) {
        refresh()
    }

    /// The query changed: the toast goes, the list is searched again and the first row is selected.
    private func refresh() {
        trashToast.dismiss()
        search()
        selection.reset(count: results.count)
        selectionDidChange(scroll: true)
        updateChrome()
    }

    /// Searches for the field's text; what is selected stays to the caller.
    private func search() {
        let raw = query
        parsed = SearchQuery(raw)
        searchedAt = now()
        do {
            results = try store.search(raw)
            searchFailed = false
        } catch {
            NSLog("Pith: search failed: %@", String(describing: error))
            results = []
            searchFailed = true
        }
        table.reloadData()
    }

    /// The hint on the right of the field, the empty message, and the spoken count.
    private func updateChrome() {
        header.trailing.stringValue = trailingText
        let message = emptyMessage
        emptyContainer.isHidden = message == nil || searchFailed
        scrollView.isHidden = results.isEmpty
        if let message {
            emptyTitle.stringValue = message.title
            emptyDetail.stringValue = message.detail
        }
        if !parsed.isEmpty, !searchFailed {
            NSAccessibility.post(
                element: header.field, notification: .announcementRequested,
                userInfo: [
                    .announcement: results.isEmpty ? "No notes match \(query)" : Self.count(results.count),
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
    }

    private static func count(_ number: Int) -> String {
        number == 1 ? "1 note" : "\(number) notes"
    }

    /// "esc", or "N notes · esc" for a query that found something.
    var trailingText: String {
        parsed.isEmpty || results.isEmpty ? "esc" : "\(Self.count(results.count)) · esc"
    }

    /// The message that replaces the list: nothing matches, or there are no Notes at all. `nil` when there are rows.
    var emptyMessage: (title: String, detail: String)? {
        guard results.isEmpty else { return nil }
        if parsed.isEmpty { return ("No notes yet", "Notes you write show up here") }
        return ("No notes match “\(query)”", "Search looks through the text of every note")
    }

    // MARK: Rows

    /// What row `row` shows. The text of a Note is read when its row is first shown, and again once it was edited.
    func display(at row: Int) -> SearchRowDisplay {
        let summary = results[row]
        let text: String
        if let cached = texts[summary.id], cached.updatedAt == summary.updatedAt {
            text = cached.text
        } else {
            text = ((try? store.note(id: summary.id)) ?? nil)?.text ?? ""
            texts[summary.id] = (summary.updatedAt, text)
        }
        return SearchRowDisplay(
            content: NoteRowContent(text: text, query: parsed),
            time: RowTimeLabel.string(for: summary.updatedAt, now: searchedAt, locale: locale, calendar: calendar)
        )
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? SearchRowCell ?? SearchRowCell()
        cell.identifier = Self.cellID
        cell.configure(display(at: row))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = SearchRowView()
        rowView.pick = pick(row: row)
        return rowView
    }

    // MARK: Selection

    /// The active row: the one ↩ opens; `nil` when nothing is selected.
    var selectedRow: Int? { selection.active }

    /// The selected rows.
    var selectedRows: IndexSet { selection.selected }

    /// How `row` shows in the selection; `nil` when it is not selected.
    private func pick(row: Int) -> SearchRowView.Pick? {
        guard selection.selected.contains(row) else { return nil }
        return SearchRowView.Pick(
            joinsAbove: selection.selected.contains(row - 1), joinsBelow: selection.selected.contains(row + 1),
            isActive: selection.isMultiple && selection.active == row
        )
    }

    /// Shows `selection`: the table's selected rows, the shape of each row in its block, the pill and the spoken count.
    private func selectionDidChange(scroll: Bool) {
        let visible = table.rows(in: table.visibleRect)
        for row in visible.location..<NSMaxRange(visible) where results.indices.contains(row) {
            (table.rowView(atRow: row, makeIfNecessary: false) as? SearchRowView)?.pick = pick(row: row)
        }
        table.selectRowIndexes(selection.selected, byExtendingSelection: false)
        if scroll, let active = selection.active { table.scrollRowToVisible(active) }
        updatePill()
        let count = selection.selected.count
        if count != spokenCount, count >= 2 {
            NSAccessibility.post(
                element: table, notification: .announcementRequested,
                userInfo: [.announcement: "\(count) selected", .priority: NSAccessibilityPriorityLevel.low.rawValue]
            )
        }
        spokenCount = count
    }

    /// Moves the selection to one row, a step from the active one, stopping at the first and last row.
    func moveSelection(by step: Int) {
        selection.move(by: step)
        selectionDidChange(scroll: true)
    }

    /// ⇧↑↓: the active row goes a step, the rows from the anchor to it are selected.
    func extendSelection(by step: Int) {
        selection.extend(by: step)
        selectionDidChange(scroll: true)
    }

    /// ⌘A.
    func selectAllRows() {
        selection.selectAll()
        selectionDidChange(scroll: true)
    }

    /// Selects the rows `first` to `last`, the last one active, as ⇧↓ pressed from the first would.
    func selectRows(from first: Int, to last: Int) {
        selection.click(first)
        selection.shiftClick(last)
        selectionDidChange(scroll: true)
    }

    /// A press on a row: ⌘ toggles it, ⇧ extends from the anchor, a double click opens it.
    func click(row: Int, modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
        guard results.indices.contains(row) else { return }
        if modifiers.contains(.command) {
            selection.commandClick(row)
        } else if modifiers.contains(.shift) {
            selection.shiftClick(row)
        } else {
            selection.click(row)
        }
        selectionDidChange(scroll: false)
        if clickCount >= 2, modifiers.isDisjoint(with: [.command, .shift]) { openSelected() }
    }

    /// ⌘F with the screen open: the whole text of the field is selected.
    func selectQueryText() {
        header.field.selectText(nil)
    }

    /// ↩: opens the selected Note, with the cursor on the first match of a query. Does nothing with no rows.
    func openSelected() {
        guard let row = selectedRow, !dismissed else { return }
        let id = results[row].id
        let query = parsed
        dismiss()
        onOpen(id, query)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.moveUpAndModifySelection(_:)): extendSelection(by: -1)
        case #selector(NSResponder.moveDownAndModifySelection(_:)): extendSelection(by: 1)
        // ⌘A selects the rows; ⌘F still selects the text of the field.
        case #selector(NSResponder.selectAll(_:)): selectAllRows()
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        // The field would put the text back as it was; Esc here is the screen's.
        case #selector(NSResponder.cancelOperation(_:)): _ = handleCancel()
        default: return false
        }
        return true
    }

    // MARK: Trash

    /// ⌘⌫ has rows to take.
    var canMoveToTrash: Bool { !selection.selected.isEmpty }

    /// ⌘⌫: the selected Notes go to the Trash in one action, with no question. Search stays open on the same query, the
    /// row that took the place of the lowest one gone is selected, and the toast says what happened.
    func moveSelectionToTrash() {
        let rows = selection.selected.filteredIndexSet { results.indices.contains($0) }
        let moved = moveToTrash(rows.map { results[$0].id })
        guard !moved.isEmpty else { return }
        let gone = rows.filteredIndexSet { moved.contains(results[$0].id) }
        let before = results.count
        search()
        if results.count == before - gone.count {
            selection = selection.removing(gone, newCount: results.count)
        } else {
            selection.reset(count: results.count)
        }
        selectionDidChange(scroll: true)
        updateChrome()
        trashToast.show(ids: moved, on: self)
    }

    // MARK: Toast

    var isToastShowing: Bool { trashToast.isShowing(on: self) }
    var toastText: String? { isToastShowing ? trashToast.text : nil }

    /// The pill and the room under the list follow the toast.
    func toastDidChange() { updatePill() }

    /// Undo of the toast, by its button or ⌘Z: the Notes come back to their places in the Stack and in the list, selected,
    /// the lowest of them active. `false` when there is no toast.
    @discardableResult
    func undoMoveToTrash() -> Bool {
        guard isToastShowing, let ids = trashToast.undo() else { return false }
        do {
            try store.restore(ids: ids)
        } catch {
            onFailure(error.localizedDescription)
            return true
        }
        onRestored()
        search()
        let back = IndexSet(results.indices.filter { ids.contains(results[$0].id) })
        selection = back.isEmpty ? RowSelection(count: results.count) : RowSelection(selecting: back, count: results.count)
        selectionDidChange(scroll: true)
        updateChrome()
        return true
    }

    /// The pill "N selected" is up.
    var isSelectionPillShown: Bool { !pill.isHidden }
    var selectionPillText: String { pill.text }

    /// The pill is up for two rows or more while there is no toast; either one moves the end of the list up.
    private func updatePill() {
        let count = selection.selected.count
        let showsToast = isToastShowing
        pill.selectedCount = count
        pill.isHidden = count < 2 || showsToast || results.isEmpty
        let inset = (!pill.isHidden || showsToast) ? Self.bottomInset - SearchFieldView.margin : 0
        guard scrollView.contentInsets.bottom != inset else { return }
        // The list stays where it was; only the active row may have to move out from under the pill.
        let clip = scrollView.contentView
        let offset = clip.bounds.origin.y
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
        clip.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(clip)
        if let active = selection.active { table.scrollRowToVisible(active) }
    }

    // MARK: PanelScreen

    private func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        trashToast.dismiss()
        onDismiss(query)
    }

    /// Esc: with several rows selected the first one leaves only the active row; the next closes Search.
    func handleCancel() -> Bool {
        if selection.isMultiple {
            selection.collapse()
            selectionDidChange(scroll: true)
            return true
        }
        dismiss()
        close()
        return true
    }

    func willHide() {
        dismiss()
    }

    /// The field's strip and the gaps around the list move the Panel; the text of the field does not.
    func isDragZone(atWindowPoint point: NSPoint) -> Bool {
        let local = view.convert(point, from: nil)
        let margin = SearchFieldView.margin
        if local.x < margin || local.x > view.bounds.width - margin || local.y < margin { return true }
        let inHeader = local.y > view.bounds.height - margin - SearchFieldView.height - margin
        guard inHeader else { return false }
        return !header.field.convert(header.field.bounds, to: view).contains(local)
    }
}

/// The root view of the Search screen.
private final class SearchScreenRootView: NSView {}
