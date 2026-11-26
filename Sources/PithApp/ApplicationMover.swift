import AppKit
import Foundation

/// The system's part of a move, for tests to replace.
struct MoverFiles {
    /// Whether the folder takes new items.
    var isWritable: (URL) -> Bool = { FileManager.default.isWritableFile(atPath: $0.path) }
    /// Puts an item in the Trash.
    var trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
}

/// Ends the running copies of an app at a path.
protocol RunningInstances {
    func terminateInstances(at url: URL) throws
}

/// Moving Pith to Applications, as LetsMove does: copies it, takes off the quarantine, replaces an old copy, puts the original in the Trash.
struct ApplicationMover {
    /// A step of the move failed; the half-done copy is gone.
    struct Failure: Error {
        let step: String
        let underlying: Error?
    }

    static let quarantine = "com.apple.quarantine"

    var files = MoverFiles()
    var instances: RunningInstances
    var applications = URL(fileURLWithPath: "/Applications")
    var home = FileManager.default.homeDirectoryForCurrentUser

    /// `/Applications/<name>` if that folder takes new items, else `~/Applications/<name>`.
    static func target(name: String, applicationsWritable: Bool, applications: URL, home: URL) -> URL {
        (applicationsWritable ? applications : home.appending(path: "Applications")).appending(path: name)
    }

    /// Copies the app at `original` to Applications and returns the new path. An app already there is ended and goes to the
    /// Trash first. The original goes to the Trash if it can; that it cannot (a read-only disk image) is no failure.
    func move(from original: URL) throws -> URL {
        let manager = FileManager.default
        let target = Self.target(
            name: original.lastPathComponent, applicationsWritable: files.isWritable(applications), applications: applications, home: home
        )
        let folder = target.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw Failure(step: "creating \(folder.path)", underlying: error)
        }

        // A copy that breaks off does not look like Pith: it has no `.app`, and it is renamed only when whole.
        let partial = folder.appending(path: "\(target.lastPathComponent).moving-\(UUID().uuidString)")
        do {
            do {
                try manager.copyItem(at: original, to: partial)
            } catch {
                throw Failure(step: "copying", underlying: error)
            }
            do {
                try Self.removeQuarantine(in: partial)
            } catch {
                throw Failure(step: "removing the quarantine", underlying: error)
            }
            if manager.fileExists(atPath: target.path) {
                do {
                    try instances.terminateInstances(at: target)
                    try files.trash(target)
                } catch {
                    throw Failure(step: "replacing the old copy", underlying: error)
                }
            }
            do {
                try manager.moveItem(at: partial, to: target)
            } catch {
                throw Failure(step: "installing", underlying: error)
            }
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }

        do {
            try files.trash(original)
        } catch {
            NSLog("Pith: cannot put the original in the Trash: %@", String(describing: error))
        }
        return target
    }

    /// Takes `com.apple.quarantine` off `url` and everything in it; without it the copy would be translocated again.
    static func removeQuarantine(in url: URL) throws {
        var paths = [url.path]
        if let found = FileManager.default.enumerator(atPath: url.path) {
            for case let relative as String in found { paths.append(url.appending(path: relative).path) }
        }
        for path in paths where removexattr(path, quarantine, XATTR_NOFOLLOW) != 0 && errno != ENOATTR {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Starts `target` once this process is gone, so that two Hotkeys never live together; the caller quits right after.
    static func relaunch(_ target: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$1\"",
            String(ProcessInfo.processInfo.processIdentifier), target.path,
        ]
        do {
            try process.run()
        } catch {
            NSLog("Pith: cannot start the moved copy: %@", String(describing: error))
        }
    }
}

/// The running copies of this app, found by bundle identifier and path.
struct RunningCopies: RunningInstances {
    struct StillRunning: Error {}

    var bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
    var patience: TimeInterval = 5

    func terminateInstances(at url: URL) throws {
        let path = url.standardizedFileURL.path
        let mine = NSRunningApplication.current
        let copies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0 != mine && $0.bundleURL?.standardizedFileURL.path == path }
        guard !copies.isEmpty else { return }
        copies.forEach { $0.terminate() }
        if !Self.wait(for: copies, seconds: patience) {
            copies.forEach { $0.forceTerminate() }
            guard Self.wait(for: copies, seconds: 1) else { throw StillRunning() }
        }
    }

    private static func wait(for copies: [NSRunningApplication], seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while copies.contains(where: { !$0.isTerminated }) {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return true
    }
}
