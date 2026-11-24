import AppKit

public enum PithApp {
    /// Starts the application and never returns until it quits.
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // No Dock icon; the hidden main menu still handles key equivalents.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
