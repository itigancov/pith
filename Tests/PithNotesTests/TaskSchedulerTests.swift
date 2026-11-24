import Foundation
import Testing
@testable import PithNotes

@MainActor @Suite struct TaskSchedulerTests {
    @Test func runsTheActionAfterTheDelay() async throws {
        let fired = CapturedValues<Int>()
        _ = TaskScheduler().schedule(after: 0.01) { fired.values.append(1) }
        #expect(fired.values.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fired.values == [1])
    }

    @Test func cancelledActionNeverRuns() async throws {
        let fired = CapturedValues<Int>()
        let job = TaskScheduler().schedule(after: 0.01) { fired.values.append(1) }
        job.cancel()
        try await Task.sleep(for: .milliseconds(300))
        #expect(fired.values.isEmpty)
    }
}
