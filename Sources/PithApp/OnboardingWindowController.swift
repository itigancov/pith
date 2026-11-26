import AppKit
import SwiftUI

/// The onboarding window: 440 wide, as high as the step, centered, with only the red button. While it is open Pith has a
/// Dock icon and a place in ⌘Tab, as with Settings. Closing it by any way but Open Pith skips the onboarding.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    let model: OnboardingModel
    private var window: NSWindow?

    /// Whether another window of Pith (Settings) is open, so that closing this one keeps the Dock icon.
    var keepsRegularPolicy: () -> Bool = { false }

    init(model: OnboardingModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }
    var windowNumber: Int? { window?.windowNumber }

    /// Opens the window in front, in the middle of the screen, and makes Pith the active app.
    func show() {
        let window = window ?? makeWindow()
        updateTitle()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// The Hotkey pressed while the onboarding is open.
    func bringForward() { show() }

    /// Closes the window without asking: the model has finished.
    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: OnboardingView(model: model))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        observeStep()
        return window
    }

    /// The window is named for the step: "Welcome to Pith", then "Pith is ready"; the title itself is not drawn.
    private func updateTitle() {
        window?.title = model.step == .hotkey ? "Welcome to Pith" : "Pith is ready"
    }

    private func observeStep() {
        withObservationTracking {
            _ = model.step
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.updateTitle()
                    self?.observeStep()
                }
            }
        }
    }

    // MARK: NSWindowDelegate

    /// The red button and ⌘W: skip. The model closes the window itself.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.skip()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if !keepsRegularPolicy() { NSApp.setActivationPolicy(.accessory) }
    }
}
