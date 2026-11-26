import Foundation

/// Which rows of a list are selected, as in Finder: a click, ⇧-click and ⌘-click, ⇧↑↓ from an anchor, ⌘A. No AppKit; the
/// list only shows it.
///
/// The selection is the range from the `anchor` to the moving end, the cursor, plus what ⌘-click added. The `active` row, the
/// moving end, is the one ↩ opens. The one case with nothing selected is after ⌘-click took out the last row.
nonisolated public struct RowSelection: Sendable, Equatable {
    public private(set) var count: Int
    public private(set) var selected: IndexSet
    private var anchor: Int
    /// The moving end of the range; a row ⌘-click took out is still where Shift and the arrows start from.
    private var cursor: Int

    /// The first row, or nothing for an empty list.
    public init(count: Int) {
        self.count = max(count, 0)
        selected = IndexSet()
        anchor = 0
        cursor = 0
        reset(count: count)
    }

    /// The rows `indices` (those inside the list): the lowest is the anchor and the highest the active one. Without any, as `reset`.
    public init(selecting indices: IndexSet, count: Int) {
        self.init(count: count)
        let inside = indices.filteredIndexSet { $0 >= 0 && $0 < self.count }
        guard let first = inside.first, let last = inside.last else { return }
        selected = inside
        anchor = first
        cursor = last
    }

    /// More than one row is selected, so that Esc has a step to take before it closes the list.
    public var isMultiple: Bool { selected.count >= 2 }

    /// The row the selection is moving with: the cursor, or the selected row nearest to it after ⌘-click took the cursor's out.
    /// `nil` with nothing selected.
    public var active: Int? {
        guard !selected.isEmpty else { return nil }
        if selected.contains(cursor) { return cursor }
        let below = selected.integerLessThan(cursor)
        let above = selected.integerGreaterThan(cursor)
        switch (below, above) {
        case let (below?, above?): return cursor - below <= above - cursor ? below : above
        case let (below?, nil): return below
        case let (nil, above?): return above
        case (nil, nil): return nil
        }
    }

    // MARK: Operations

    /// After the query changed: the first row, or nothing for an empty list.
    public mutating func reset(count: Int) {
        self.count = max(count, 0)
        anchor = 0
        cursor = 0
        selected = self.count > 0 ? IndexSet(integer: 0) : IndexSet()
    }

    /// A click: only that row.
    public mutating func click(_ row: Int) {
        guard contains(row) else { return }
        selected = IndexSet(integer: row)
        anchor = row
        cursor = row
    }

    /// ⇧-click: the rows from the anchor to `row`; what ⌘-click added outside them goes.
    public mutating func shiftClick(_ row: Int) {
        guard contains(row) else { return }
        cursor = row
        selected = range(from: anchor, to: row)
    }

    /// ⌘-click: `row` is added, or taken out when it was selected; the rest stays. It becomes the anchor.
    public mutating func commandClick(_ row: Int) {
        guard contains(row) else { return }
        if selected.contains(row) { selected.remove(row) } else { selected.insert(row) }
        anchor = row
        cursor = row
    }

    /// ⇧↑↓: the moving end goes one row, stopping at the first and the last. The selection is the range from the anchor.
    public mutating func extend(by step: Int) {
        guard count > 0 else { return }
        cursor = min(max(cursor + step, 0), count - 1)
        selected = range(from: anchor, to: cursor)
    }

    /// ↑↓: one row, a step from the active one, stopping at the first and the last.
    public mutating func move(by step: Int) {
        guard count > 0 else { return }
        let row = min(max((active ?? cursor) + step, 0), count - 1)
        click(row)
    }

    /// ⌘A: every row, with the anchor on the first and the active row the last.
    public mutating func selectAll() {
        guard count > 0 else { return }
        selected = IndexSet(integersIn: 0..<count)
        anchor = 0
        cursor = count - 1
    }

    /// The first Esc: only the active row stays.
    public mutating func collapse() {
        guard let active else { return }
        click(active)
    }

    /// The selection once the rows `removed` are gone from a list that now has `newCount` rows: the row that took the place
    /// of the bottom removed one, else the nearest above it, else nothing.
    public func removing(_ removed: IndexSet, newCount: Int) -> RowSelection {
        var result = RowSelection(count: newCount)
        // The rows below the removed ones keep their order, so the one after the bottom removed row is now this far down.
        if let bottom = removed.last { result.click(min(bottom - removed.count + 1, newCount - 1)) }
        return result
    }

    // MARK: Private

    private func contains(_ row: Int) -> Bool { row >= 0 && row < count }

    private func range(from first: Int, to second: Int) -> IndexSet {
        IndexSet(integersIn: min(first, second)...max(first, second))
    }
}
