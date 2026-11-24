import Foundation
@testable import PithNotes

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

@MainActor func makeMemoryStore(clock: TestClock = TestClock()) throws -> NoteStore {
    try NoteStore.open(at: .memory, now: { clock.date }).store
}

/// A fresh empty directory, removed by the caller.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pith-tests-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let noSelection = NoteSelection(location: 0, length: 0)
