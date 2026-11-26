import AppKit

/// The alert "Move Pith to Applications?" at a launch from elsewhere, and what follows its buttons.
struct MoveOffer {
    static let suppressedKey = "MoveAlertSuppressed"

    var defaults: UserDefaults = .standard
    var mover = ApplicationMover(instances: RunningCopies())

    /// Whether the alert shows at this launch: not from Applications, not once "Don't ask again" was ticked with Not Now,
    /// not in a Debug build (`make run` runs from the build folder).
    static func shouldAsk(location: InstallLocation, suppressed: Bool, isDebug: Bool) -> Bool {
        !location.isApplications && !suppressed && !isDebug
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move Pith to Applications?"
        alert.informativeText = "Pith can open at login only from the Applications folder."
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Not Now").keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"
        return alert
    }

    static func makeFailureAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t move Pith"
        alert.informativeText = "Drag Pith to Applications yourself."
        alert.addButton(withTitle: "OK")
        return alert
    }

    /// Asks, and moves on Move: Pith restarts from its new place and this call does not return then. On Not Now, or when the
    /// move fails, it returns and the launch goes on.
    func run(location: InstallLocation) {
        NSApp.activate()
        let alert = Self.makeAlert()
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            if alert.suppressionButton?.state == .on { defaults.set(true, forKey: Self.suppressedKey) }
            return
        }
        guard let original = location.originalURL else {
            // Translocated and the system did not say from where.
            Self.makeFailureAlert().runModal()
            return
        }
        do {
            let target = try mover.move(from: original)
            ApplicationMover.relaunch(target)
            NSApp.terminate(nil)
        } catch {
            NSLog("Pith: cannot move to Applications: %@", String(describing: error))
            Self.makeFailureAlert().runModal()
        }
    }
}
