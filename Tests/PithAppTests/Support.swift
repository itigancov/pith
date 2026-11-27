import AppKit
import Foundation
@testable import PithApp
import PithNotes

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

/// A clock the test moves by hand.
@MainActor final class TestClock {
    var date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.date = date
    }

    func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

/// What VoiceOver is told while `body` runs.
@MainActor
func announcements(during body: () throws -> Void) rethrows -> [Announcer.Announcement] {
    final class Box { var heard: [Announcer.Announcement] = [] }
    let box = Box()
    let previous = Announcer.post
    Announcer.post = { text, priority, _ in box.heard.append(Announcer.Announcement(text: text, priority: priority)) }
    defer { Announcer.post = previous }
    try body()
    return box.heard
}
