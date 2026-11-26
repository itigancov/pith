import Foundation
import Testing
@testable import PithApp

@MainActor final class FakeInstances: RunningInstances {
    var terminated: [URL] = []
    var failure: Error?

    func terminateInstances(at url: URL) throws {
        if let failure { throw failure }
        terminated.append(url)
    }
}

/// A scratch folder with a place for "Applications", a home, a Trash and the original.
@MainActor final class MoveSandbox {
    let root = FileManager.default.temporaryDirectory.appending(path: "pith-tests-" + UUID().uuidString)
    var applications: URL { root.appending(path: "Applications") }
    var home: URL { root.appending(path: "home") }
    var trashFolder: URL { root.appending(path: "Trash") }
    var original: URL { root.appending(path: "Downloads/Pith.app") }
    var applicationsWritable = true
    var trashRefuses = false

    init() throws {
        let manager = FileManager.default
        for folder in [applications, home, trashFolder, original.appending(path: "Contents/MacOS")] {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("binary".utf8).write(to: original.appending(path: "Contents/MacOS/Pith"))
        try Data("plist".utf8).write(to: original.appending(path: "Contents/Info.plist"))
        for path in [original, original.appending(path: "Contents"), original.appending(path: "Contents/MacOS/Pith")] {
            try Self.quarantine(path)
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    static func quarantine(_ url: URL) throws {
        let value = Array("0083;00000000;Safari;".utf8)
        guard setxattr(url.path, ApplicationMover.quarantine, value, value.count, 0, 0) == 0 else { throw POSIXError(.EIO) }
    }

    static func hasQuarantine(_ url: URL) -> Bool {
        getxattr(url.path, ApplicationMover.quarantine, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    func mover(instances: RunningInstances) -> ApplicationMover {
        var files = MoverFiles()
        files.isWritable = { [self] _ in applicationsWritable }
        files.trash = { [self] url in
            if trashRefuses { throw POSIXError(.EROFS) }
            try FileManager.default.moveItem(at: url, to: trashFolder.appending(path: UUID().uuidString + "-" + url.lastPathComponent))
        }
        return ApplicationMover(files: files, instances: instances, applications: applications, home: home)
    }

    var trashed: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: trashFolder.path)) ?? []).sorted()
    }
}

struct ApplicationMoverTests {
    @Test func targetIsApplicationsWhenItTakesNewItems() {
        let applications = URL(fileURLWithPath: "/Applications")
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(ApplicationMover.target(name: "Pith.app", applicationsWritable: true, applications: applications, home: home).path == "/Applications/Pith.app")
        #expect(ApplicationMover.target(name: "Pith.app", applicationsWritable: false, applications: applications, home: home).path == "/Users/someone/Applications/Pith.app")
    }

    @Test func theCopyIsWholeAndWithoutQuarantine() throws {
        let sandbox = try MoveSandbox()
        let target = try sandbox.mover(instances: FakeInstances()).move(from: sandbox.original)
        #expect(target == sandbox.applications.appending(path: "Pith.app"))
        #expect(try String(contentsOf: target.appending(path: "Contents/MacOS/Pith"), encoding: .utf8) == "binary")
        #expect(try String(contentsOf: target.appending(path: "Contents/Info.plist"), encoding: .utf8) == "plist")
        for path in ["", "Contents", "Contents/MacOS", "Contents/MacOS/Pith", "Contents/Info.plist"] {
            #expect(!MoveSandbox.hasQuarantine(target.appending(path: path)), "\(path) is still quarantined")
        }
    }

    @Test func theOriginalGoesToTheTrash() throws {
        let sandbox = try MoveSandbox()
        _ = try sandbox.mover(instances: FakeInstances()).move(from: sandbox.original)
        #expect(!FileManager.default.fileExists(atPath: sandbox.original.path))
        #expect(sandbox.trashed.count == 1 && sandbox.trashed[0].hasSuffix("Pith.app"))
    }

    @Test func anOriginalThatCannotBeTrashedStaysAndIsNoFailure() throws {
        let sandbox = try MoveSandbox()
        sandbox.trashRefuses = true
        let target = try sandbox.mover(instances: FakeInstances()).move(from: sandbox.original)
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: sandbox.original.path))
    }

    @Test func withoutRightsToApplicationsItGoesToTheHomeOne() throws {
        let sandbox = try MoveSandbox()
        sandbox.applicationsWritable = false
        let target = try sandbox.mover(instances: FakeInstances()).move(from: sandbox.original)
        #expect(target == sandbox.home.appending(path: "Applications/Pith.app"))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "Contents/Info.plist").path))
        #expect(!FileManager.default.fileExists(atPath: sandbox.applications.appending(path: "Pith.app").path))
    }

    @Test func anOldCopyIsEndedAndReplaced() throws {
        let sandbox = try MoveSandbox()
        let old = sandbox.applications.appending(path: "Pith.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: old.appending(path: "marker"))
        let instances = FakeInstances()
        let target = try sandbox.mover(instances: instances).move(from: sandbox.original)
        #expect(instances.terminated == [old])
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "marker").path))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "Contents/Info.plist").path))
        // The old copy and the original are in the Trash.
        #expect(sandbox.trashed.count == 2)
    }

    @Test func anOldCopyThatWillNotEndFailsTheMoveAndLeavesItBe() throws {
        let sandbox = try MoveSandbox()
        let old = sandbox.applications.appending(path: "Pith.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let instances = FakeInstances()
        instances.failure = RunningCopies.StillRunning()
        #expect(throws: ApplicationMover.Failure.self) { try sandbox.mover(instances: instances).move(from: sandbox.original) }
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: sandbox.original.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.applications.path) == ["Pith.app"])
    }

    @Test func aFailedCopyLeavesNothingBehind() throws {
        let sandbox = try MoveSandbox()
        let missing = sandbox.root.appending(path: "Downloads/Gone.app")
        #expect(throws: ApplicationMover.Failure.self) { try sandbox.mover(instances: FakeInstances()).move(from: missing) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.applications.path).isEmpty)
        #expect(sandbox.trashed.isEmpty)
    }

    @Test func quarantineGoesFromEveryFileOfATree() throws {
        let sandbox = try MoveSandbox()
        try ApplicationMover.removeQuarantine(in: sandbox.original)
        for path in ["", "Contents", "Contents/MacOS/Pith"] {
            #expect(!MoveSandbox.hasQuarantine(sandbox.original.appending(path: path)))
        }
    }
}
