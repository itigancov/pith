import AppKit
import PithNotes

/// The Trash screen: the deleted Notes, the most recent deletion first, with Restore, Delete permanently and Empty Trash.
///
/// The focus is in the list: ↑↓ move, ↩ restores, ⌘⌫ deletes for good, Esc goes back to the Note.
final class TrashScreen: NSObject, PanelScreen, NSTableViewDataSource, NSTableViewDelegate {
    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 44
    private static let cellID = NSUserInterfaceItemIdentifier("TrashRow")

    let view: NSView
    private let header = TrashHeaderView()
    private let scrollView = NSScrollView()
    let table = TrashTableView()
    private let emptyContainer = NSView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyDetail = NSTextField(labelWithString: "")

    var preferredFirstResponder: NSResponder? { table }

    private let store: NoteStore
    private let now: () -> Date
    private let locale: Locale
    private let calendar: Calendar
    private var openedAt = Date()

    /// Puts an alert on the Panel and calls the handler with the answer.
    var presentAlert: (NSAlert, @escaping (NSApplication.ModalResponse) -> Void) -> Void = { _, _ in }
    /// A write failed; the reason goes to the user.
    var onFailure: (String) -> Void = { _ in }
    /// The screen is leaving through Esc or "‹ Notes", with whether anything was restored.
    var onClose: (_ restoredAny: Bool) -> Void = { _ in }
    /// Takes the screen off the stack.
    var close: () -> Void = {}

    private(set) var rows: [NoteSummary] = []
    private(set) var restoredAny = false
    private var titles: [UUID: String] = [:]

    init(store: NoteStore, now: @escaping () -> Date = Date.init, locale: Locale = .current, calendar: Calendar = .current) {
        self.store = store
        self.now = now
        self.locale = locale
        self.calendar = calendar
        view = TrashScreenRootView()
        super.init()
        layOut()
        header.onBack = { [weak self] in _ = self?.handleCancel() }
        header.onEmpty = { [weak self] in self?.emptyTrash() }
        refresh()
        if !rows.isEmpty { select(0) }
    }

    // MARK: Layout

    private func layOut() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
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
        table.onReturn = { [weak self] in self?.restoreSelected() }
        table.onDelete = { [weak self] in self?.deleteSelectedPermanently() }
        table.setAccessibilityLabel("Deleted notes")

        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

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
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            emptyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
        ])
    }

    // MARK: Rows

    /// Reads the Trash. On a failure the list is empty and the log says why.
    private func refresh() {
        openedAt = now()
        do {
            rows = try store.trash()
        } catch {
            NSLog("Pith: reading the Trash failed: %@", String(describing: error))
            rows = []
        }
        table.reloadData()
        updateChrome()
    }

    private func updateChrome() {
        header.set(count: rows.count)
        let isEmpty = rows.isEmpty
        emptyContainer.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
        emptyTitle.stringValue = "Trash is empty"
        emptyDetail.stringValue = "Deleted notes stay here until you delete them"
    }

    /// "Trash · 3", "Trash" when it is empty.
    var titleText: String { rows.isEmpty ? "Trash" : "Trash · \(rows.count)" }

    var isEmptyTrashEnabled: Bool { !rows.isEmpty }

    /// The message that replaces the list; `nil` when there are rows.
    var emptyMessage: (title: String, detail: String)? {
        rows.isEmpty ? ("Trash is empty", "Deleted notes stay here until you delete them") : nil
    }

    /// What row `row` shows. The title is read when the row is first shown.
    func display(at row: Int) -> TrashRowDisplay {
        let summary = rows[row]
        let title: String
        if let cached = titles[summary.id] {
            title = cached
        } else {
            title = ((try? store.note(id: summary.id)) ?? nil)?.title ?? ""
            titles[summary.id] = title
        }
        let deletedAt = summary.deletedAt ?? summary.updatedAt
        return TrashRowDisplay(
            title: title.isEmpty ? "Empty note" : title,
            time: RowTimeLabel.deleted(for: deletedAt, now: openedAt, locale: locale, calendar: calendar)
        )
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? TrashRowCell ?? TrashRowCell()
        cell.identifier = Self.cellID
        cell.configure(display(at: row))
        cell.onRestore = { [weak self] cell in self?.act(on: cell, self?.restoreSelected) }
        cell.onDelete = { [weak self] cell in self?.act(on: cell, self?.deleteSelectedPermanently) }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TrashRowView()
    }

    /// A button of a row: the row is selected, then the action works on it.
    private func act(on cell: NSView, _ action: (() -> Void)?) {
        let row = table.row(for: cell)
        guard row >= 0 else { return }
        select(row)
        action?()
    }

    // MARK: Selection

    var selectedRow: Int? { table.selectedRow >= 0 ? table.selectedRow : nil }

    private func select(_ row: Int) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    /// Moves the selection, stopping at the first and last row.
    func moveSelection(by step: Int) {
        guard !rows.isEmpty else { return }
        select(min(max((selectedRow ?? 0) + step, 0), rows.count - 1))
    }

    // MARK: Actions

    /// ↩: the Note goes back to its place in the Stack; the Trash stays open and the selection moves on.
    func restoreSelected() {
        guard let row = selectedRow, rows.indices.contains(row) else { return }
        do {
            try store.restore(ids: [rows[row].id])
        } catch {
            onFailure(error.localizedDescription)
            return
        }
        restoredAny = true
        remove(row: row)
    }

    /// ⌘⌫ and the button of the row: asks, then deletes the Note for good.
    func deleteSelectedPermanently() {
        guard let row = selectedRow, rows.indices.contains(row) else { return }
        let id = rows[row].id
        let alert = NSAlert()
        alert.messageText = "Delete note permanently?"
        alert.informativeText = "You can’t undo this."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        presentAlert(alert) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self, let row = self.rows.firstIndex(where: { $0.id == id }) else { return }
            do {
                try self.store.deletePermanently(id: id)
            } catch {
                self.onFailure(error.localizedDescription)
                return
            }
            self.remove(row: row)
        }
    }

    /// Empty Trash: asks with the number, then deletes every Note of the Trash for good.
    func emptyTrash() {
        let count = rows.count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = "\(count == 1 ? "1 note will" : "\(count) notes will") be deleted for good. You can’t undo this."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Empty Trash").hasDestructiveAction = true
        presentAlert(alert) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            do {
                try self.store.emptyTrash()
            } catch {
                self.onFailure(error.localizedDescription)
                return
            }
            self.refresh()
        }
    }

    /// Takes `row` out of the list; the selection goes to the row that took its place, else the one before.
    private func remove(row: Int) {
        rows.remove(at: row)
        table.removeRows(at: IndexSet(integer: row), withAnimation: [])
        updateChrome()
        if !rows.isEmpty { select(min(row, rows.count - 1)) }
        NSAccessibility.post(element: table, notification: .selectedRowsChanged)
    }

    // MARK: PanelScreen

    func handleCancel() -> Bool {
        onClose(restoredAny)
        close()
        return true
    }

    func willHide() {}

    /// The header outside its buttons and the gaps around the list move the Panel.
    func isDragZone(atWindowPoint point: NSPoint) -> Bool {
        let local = view.convert(point, from: nil)
        if local.y > view.bounds.height - Self.headerHeight { return header.isDragZone(at: header.convert(point, from: nil)) }
        // Outside the list's rows: the margins of the list and the room under the last row.
        let inTable = table.convert(point, from: nil)
        if local.x < 6 || local.x > view.bounds.width - 6 { return true }
        return table.row(at: inTable) < 0
    }
}

/// The root view of the Trash screen.
private final class TrashScreenRootView: NSView {}

/// The header: "‹ Notes", "Trash · N" and Empty Trash, with a line under it.
final class TrashHeaderView: NSView {
    private let back = NSButton()
    private let title = NSTextField(labelWithString: "Trash")
    private let empty = NSButton()
    private let count = NSTextField(labelWithString: "")

    var onBack: () -> Void = {}
    var onEmpty: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure(back, title: "Notes", color: .secondaryLabelColor, symbol: "chevron.left")
        back.target = self
        back.action = #selector(backPressed)
        back.setAccessibilityLabel("Back to notes")
        back.toolTip = "Esc"
        configure(empty, title: "Empty Trash", color: TrashStyle.red, symbol: nil)
        empty.target = self
        empty.action = #selector(emptyPressed)
        empty.setAccessibilityLabel("Empty Trash")

        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        count.font = .systemFont(ofSize: 13)
        count.textColor = .tertiaryLabelColor
        title.setAccessibilityElement(false)
        count.setAccessibilityElement(false)
        let center = NSStackView(views: [title, count])
        center.orientation = .horizontal
        center.spacing = 0
        center.setAccessibilityElement(true)
        center.setAccessibilityRole(.staticText)

        for subview in [back, center, empty] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            back.centerYAnchor.constraint(equalTo: centerYAnchor),
            back.heightAnchor.constraint(equalToConstant: 28),
            center.centerXAnchor.constraint(equalTo: centerXAnchor),
            center.centerYAnchor.constraint(equalTo: centerYAnchor),
            empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
            empty.heightAnchor.constraint(equalToConstant: 26),
        ])
        centerView = center
    }

    private var centerView: NSView?

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure(_ button: NSButton, title: String, color: NSColor, symbol: String?) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.focusRingType = .default
        button.imagePosition = symbol == nil ? .noImage : .imageLeading
        button.imageHugsTitle = true
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            button.contentTintColor = color
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
        button.setButtonType(.momentaryChange)
    }

    func set(count number: Int) {
        title.stringValue = "Trash"
        count.stringValue = number == 0 ? "" : " · \(number)"
        centerView?.setAccessibilityLabel(number == 0 ? "Trash" : "Trash, \(number)")
        empty.isEnabled = number > 0
        let color = number > 0 ? TrashStyle.red : NSColor.disabledControlTextColor
        empty.attributedTitle = NSAttributedString(string: "Empty Trash", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
    }

    /// Whether a press at `point` (this view's coordinates) lands outside both buttons.
    func isDragZone(at point: NSPoint) -> Bool {
        !back.frame.contains(point) && !empty.frame.contains(point)
    }

    @objc private func backPressed(_ sender: Any?) { onBack() }
    @objc private func emptyPressed(_ sender: Any?) { onEmpty() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
    }
}
