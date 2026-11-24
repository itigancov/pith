import Foundation
import os

public protocol Cancellable: AnyObject {
    func cancel()
}

/// Runs an action later, on the main actor. The tests move time by hand.
public protocol Scheduler {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable
}

/// The writes the `Autosaver` needs of a store.
public protocol NoteSaving {
    func insert(text: String, selection: NoteSelection, scrollOffset: Double) throws -> Note
    func updateText(id: UUID, text: String) throws
    func updateViewState(id: UUID, selection: NoteSelection, scrollOffset: Double) throws
}

extension NoteStore: NoteSaving {}

/// The `Scheduler` of the app, on `Task.sleep`.
public struct TaskScheduler: Scheduler {
    private final class Job: Cancellable {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    public init() {}

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        let job = Job()
        job.task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
        return job
    }
}

/// Writes the open Note after the user stops typing, and when the app asks for it with `flush()`.
///
/// Wiring: call `flush()` when leaving a Note, hiding the Panel and in `applicationWillTerminate`.
public final class Autosaver {
    private let store: NoteSaving
    private let scheduler: Scheduler
    private let debounce: TimeInterval
    private let onNoteCreated: (UUID) -> Void
    private let onSaveFailure: (Error) -> Void
    private let log = Logger(subsystem: "io.github.itigancov.pith", category: "autosave")

    private var noteID: UUID?
    private var dirtyText: String?
    private var dirtyViewState = false
    private var selection = NoteSelection(location: 0, length: 0)
    private var scrollOffset = 0.0
    private var timer: Cancellable?
    private var hasReportedFailure = false

    /// - Parameters:
    ///   - onNoteCreated: A Blank got its first text and became a Note with this id.
    ///   - onSaveFailure: The first failed write of the session; the next ones go to the log only.
    public init(
        store: NoteSaving, scheduler: Scheduler, debounce: TimeInterval = 0.5,
        onNoteCreated: @escaping (UUID) -> Void, onSaveFailure: @escaping (Error) -> Void
    ) {
        self.store = store
        self.scheduler = scheduler
        self.debounce = debounce
        self.onNoteCreated = onNoteCreated
        self.onSaveFailure = onSaveFailure
    }

    /// Makes `id` the open Note, or a Blank for `nil`. Whatever is still dirty is dropped: `flush()` first.
    public func open(_ id: UUID?) {
        cancelTimer()
        noteID = id
        dirtyText = nil
        dirtyViewState = false
        selection = NoteSelection(location: 0, length: 0)
        scrollOffset = 0
    }

    public func textDidChange(_ text: String) {
        dirtyText = text
        scheduleDebounce()
    }

    /// Remembers the cursor and the scroll position; they are written by the next `flush()`, not by the timer.
    public func viewStateDidChange(selection: NoteSelection, scrollOffset: Double) {
        self.selection = selection
        self.scrollOffset = scrollOffset
        dirtyViewState = noteID != nil
    }

    /// Writes everything dirty now. Returns false when a write failed: the state stays dirty.
    @discardableResult
    public func flush() -> Bool {
        cancelTimer()
        return write(includingViewState: true)
    }

    private func scheduleDebounce() {
        cancelTimer()
        timer = scheduler.schedule(after: debounce) { [weak self] in self?.debounceFired() }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func debounceFired() {
        timer = nil
        write(includingViewState: false)
    }

    @discardableResult
    private func write(includingViewState: Bool) -> Bool {
        do {
            try writeText()
            if includingViewState { try writeViewState() }
            return true
        } catch {
            report(error)
            // Retry on the next debounce, unless the user's next edit or a flush comes first.
            if timer == nil { scheduleDebounce() }
            return false
        }
    }

    private func writeText() throws {
        guard let text = dirtyText else { return }
        if let noteID {
            try store.updateText(id: noteID, text: text)
        } else if !text.isEmpty {
            let note = try store.insert(text: text, selection: selection, scrollOffset: scrollOffset)
            noteID = note.id
            dirtyViewState = false
            onNoteCreated(note.id)
        }
        dirtyText = nil
    }

    private func writeViewState() throws {
        guard dirtyViewState, let noteID else { return }
        try store.updateViewState(id: noteID, selection: selection, scrollOffset: scrollOffset)
        dirtyViewState = false
    }

    private func report(_ error: Error) {
        log.error("Autosave failed: \(String(describing: error), privacy: .public)")
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        onSaveFailure(error)
    }
}
