import AppKit
import PithNotes

/// The Search screen: a field over the list of Notes that match it, most recently edited first.
///
/// The focus stays in the field; ↑↓ and ↩ are taken from it. Every change of the query searches at once.
final class SearchScreen: NSObject, PanelScreen, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let rowHeight: CGFloat = 56
    private static let cellID = NSUserInterfaceItemIdentifier("SearchRow")

    let view: NSView
    private let header = SearchFieldView()
    private let scrollView = NSScrollView()
    let table = SearchTableView()
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

    private var dismissed = false
    private(set) var results: [NoteSummary] = []
    private var searchFailed = false
    private var parsed = SearchQuery("")
    private var searchedAt = Date()
    /// The text of the rows shown so far, for as long as the Note is as it was.
    private var texts: [UUID: (updatedAt: Date, text: String)] = [:]

    init(store: NoteStore, now: @escaping () -> Date = Date.init, locale: Locale = .current, calendar: Calendar = .current) {
        self.store = store
        self.now = now
        self.locale = locale
        self.calendar = calendar
        view = SearchScreenRootView()
        super.init()
        layOut()
        header.field.delegate = self
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
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.allowsTypeSelect = false
        table.focusRingType = .none
        table.usesAutomaticRowHeights = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowWasDoubleClicked)
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

        for subview in [header, scrollView, emptyContainer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            header.heightAnchor.constraint(equalToConstant: SearchFieldView.height),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: margin),
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

    /// Searches for the field's text and selects the first row.
    private func refresh() {
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
        if !results.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
        updateChrome()
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
        SearchRowView()
    }

    // MARK: Selection

    /// The selected row; `nil` when there are none.
    var selectedRow: Int? { table.selectedRow >= 0 ? table.selectedRow : nil }

    /// Moves the selection, stopping at the first and last row.
    func moveSelection(by step: Int) {
        guard !results.isEmpty else { return }
        let target = min(max((selectedRow ?? 0) + step, 0), results.count - 1)
        table.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        table.scrollRowToVisible(target)
    }

    /// ⌘F with the screen open: the whole text of the field is selected.
    func selectQueryText() {
        header.field.selectText(nil)
    }

    @objc private func rowWasDoubleClicked(_ sender: Any?) {
        guard table.clickedRow >= 0 else { return }
        openSelected()
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
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        // The field would put the text back as it was; Esc here is the screen's.
        case #selector(NSResponder.cancelOperation(_:)): _ = handleCancel()
        default: return false
        }
        return true
    }

    // MARK: PanelScreen

    private func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        onDismiss(query)
    }

    func handleCancel() -> Bool {
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
