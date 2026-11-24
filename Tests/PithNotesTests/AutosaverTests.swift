import Foundation
import Testing
@testable import PithNotes

/// Time that moves only when the test says so.
@MainActor final class ManualScheduler: Scheduler {
    private final class Job: Cancellable {
        let due: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false

        init(due: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.due = due
            self.action = action
        }

        func cancel() { isCancelled = true }
    }

    private var now: TimeInterval = 0
    private var jobs: [Job] = []

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        let job = Job(due: now + delay, action: action)
        jobs.append(job)
        return job
    }

    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let job = jobs.filter({ !$0.isCancelled && $0.due <= target }).min(by: { $0.due < $1.due }) {
            now = job.due
            jobs.removeAll { $0 === job }
            job.action()
        }
        now = target
        jobs.removeAll { $0.isCancelled }
    }
}

/// A store that records writes and fails on demand.
@MainActor final class RecordingStore: NoteSaving {
    enum Write: Equatable {
        case insert(String, NoteSelection, Double)
        case text(UUID, String)
        case viewState(UUID, NoteSelection, Double)
    }

    struct Failure: Error {}

    var writes: [Write] = []
    var failing = false
    let insertedID = UUID()

    func insert(text: String, selection: NoteSelection, scrollOffset: Double) throws -> Note {
        if failing { throw Failure() }
        writes.append(.insert(text, selection, scrollOffset))
        let date = Date(timeIntervalSince1970: 0)
        return Note(id: insertedID, text: text, createdAt: date, updatedAt: date, deletedAt: nil, selection: selection, scrollOffset: scrollOffset)
    }

    func updateText(id: UUID, text: String) throws {
        if failing { throw Failure() }
        writes.append(.text(id, text))
    }

    func updateViewState(id: UUID, selection: NoteSelection, scrollOffset: Double) throws {
        if failing { throw Failure() }
        writes.append(.viewState(id, selection, scrollOffset))
    }
}

@MainActor @Suite struct AutosaverTests {
    let store = RecordingStore()
    let scheduler = ManualScheduler()
    let noteID = UUID()
    let created = CapturedValues<UUID>()
    let failures = CapturedValues<Error>()
    let autosaver: Autosaver

    init() {
        let created = created
        let failures = failures
        autosaver = Autosaver(
            store: store, scheduler: scheduler,
            onNoteCreated: { created.values.append($0) },
            onSaveFailure: { failures.values.append($0) }
        )
    }

    // MARK: Debounce

    @Test func aBurstOfEditsIsOneWriteHalfASecondAfterTheLast() {
        autosaver.open(noteID)
        autosaver.textDidChange("a")
        scheduler.advance(by: 0.3)
        autosaver.textDidChange("ab")
        scheduler.advance(by: 0.3)
        autosaver.textDidChange("abc")
        scheduler.advance(by: 0.4)
        #expect(store.writes.isEmpty)
        scheduler.advance(by: 0.1)
        #expect(store.writes == [.text(noteID, "abc")])
        scheduler.advance(by: 5)
        #expect(store.writes.count == 1)
    }

    @Test func flushWritesAtOnceAndCancelsTheTimer() {
        autosaver.open(noteID)
        autosaver.textDidChange("abc")
        #expect(autosaver.flush())
        #expect(store.writes == [.text(noteID, "abc")])
        scheduler.advance(by: 5)
        #expect(store.writes.count == 1)
    }

    @Test func flushWithNothingDirtyWritesNothing() {
        autosaver.open(noteID)
        #expect(autosaver.flush())
        #expect(store.writes.isEmpty)
    }

    // MARK: View state

    @Test func viewStateIsWrittenOnlyOnFlush() {
        autosaver.open(noteID)
        autosaver.viewStateDidChange(selection: NoteSelection(location: 4, length: 1), scrollOffset: 30)
        scheduler.advance(by: 5)
        #expect(store.writes.isEmpty)
        autosaver.flush()
        #expect(store.writes == [.viewState(noteID, NoteSelection(location: 4, length: 1), 30)])
    }

    @Test func debounceWritesTheTextButLeavesTheViewStateForFlush() {
        autosaver.open(noteID)
        autosaver.textDidChange("abc")
        autosaver.viewStateDidChange(selection: NoteSelection(location: 3, length: 0), scrollOffset: 0)
        scheduler.advance(by: 0.5)
        #expect(store.writes == [.text(noteID, "abc")])
        autosaver.flush()
        #expect(store.writes.last == .viewState(noteID, NoteSelection(location: 3, length: 0), 0))
        autosaver.flush()
        #expect(store.writes.count == 2)
    }

    // MARK: Blank

    @Test func blankIsInsertedOnceOnTheFirstText() {
        autosaver.open(nil)
        autosaver.viewStateDidChange(selection: NoteSelection(location: 1, length: 0), scrollOffset: 9)
        autosaver.textDidChange("a")
        scheduler.advance(by: 0.5)
        #expect(store.writes == [.insert("a", NoteSelection(location: 1, length: 0), 9)])
        #expect(created.values == [store.insertedID])
        autosaver.textDidChange("ab")
        scheduler.advance(by: 0.5)
        #expect(store.writes.last == .text(store.insertedID, "ab"))
        #expect(store.writes.count == 2)
        #expect(created.values.count == 1)
    }

    @Test func blankWithoutTextIsNeverWritten() {
        autosaver.open(nil)
        autosaver.viewStateDidChange(selection: NoteSelection(location: 0, length: 0), scrollOffset: 5)
        autosaver.textDidChange("")
        autosaver.flush()
        scheduler.advance(by: 5)
        #expect(store.writes.isEmpty)
        #expect(created.values.isEmpty)
    }

    @Test func viewStateOfAnInsertedNoteIsNotWrittenTwice() {
        autosaver.open(nil)
        autosaver.viewStateDidChange(selection: NoteSelection(location: 1, length: 0), scrollOffset: 9)
        autosaver.textDidChange("a")
        autosaver.flush()
        #expect(store.writes.count == 1)
    }

    // MARK: Failures

    @Test func aFailedWriteStaysDirtyAndIsRetried() {
        autosaver.open(noteID)
        store.failing = true
        autosaver.textDidChange("abc")
        scheduler.advance(by: 0.5)
        #expect(store.writes.isEmpty)
        #expect(failures.values.count == 1)
        store.failing = false
        scheduler.advance(by: 0.5)
        #expect(store.writes == [.text(noteID, "abc")])
    }

    @Test func aFailedFlushIsRetriedByTheNextFlush() {
        autosaver.open(noteID)
        store.failing = true
        autosaver.textDidChange("abc")
        #expect(!autosaver.flush())
        store.failing = false
        #expect(autosaver.flush())
        #expect(store.writes == [.text(noteID, "abc")])
    }

    @Test func onlyTheFirstFailureOfTheSessionIsReported() {
        autosaver.open(noteID)
        store.failing = true
        autosaver.textDidChange("a")
        scheduler.advance(by: 0.5)
        scheduler.advance(by: 0.5)
        autosaver.flush()
        #expect(failures.values.count == 1)
        // Still once after a recovery and a new failure.
        store.failing = false
        autosaver.flush()
        store.failing = true
        autosaver.textDidChange("ab")
        autosaver.flush()
        #expect(failures.values.count == 1)
    }

    @Test func aFailedInsertOfBlankIsRetried() {
        autosaver.open(nil)
        store.failing = true
        autosaver.textDidChange("a")
        scheduler.advance(by: 0.5)
        #expect(created.values.isEmpty)
        store.failing = false
        scheduler.advance(by: 0.5)
        #expect(store.writes == [.insert("a", NoteSelection(location: 0, length: 0), 0)])
        #expect(created.values == [store.insertedID])
    }
}

@MainActor final class CapturedValues<Value> {
    var values: [Value] = []
}
