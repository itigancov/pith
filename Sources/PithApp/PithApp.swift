import AppKit

public enum PithApp {
    /// Starts the application and never returns until it quits.
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
