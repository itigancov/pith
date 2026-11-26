import AppKit
import SwiftUI

/// The tab view controller of Settings: reports the tab chosen and, with Reduce Motion on, switches tabs without animation.
private final class SettingsTabViewController: NSTabViewController {
    var onSelect: (SettingsTab) -> Void = { _ in }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        transitionOptions = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? [] : [.allowUserInteraction]
        super.tabView(tabView, willSelect: tabViewItem)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let raw = tabViewItem?.identifier as? String, let tab = SettingsTab(rawValue: raw) { onSelect(tab) }
    }
}

/// The Settings window: toolbar tabs General and Shortcuts, SwiftUI inside. While it is open Pith has a Dock icon and a
/// place in ⌘Tab; closing it takes them away. There is one window for the whole app, made at the first opening.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let context: SettingsContext
    private let defaults: UserDefaults
    private var window: NSWindow?
    private var tabs: SettingsTabViewController?
    /// Whether choosing a tab is remembered: not for the tab a screenshot asks for.
    private var remembersTab = true

    /// Hides the Panel when Settings opens.
    var hidePanel: () -> Void = {}
    /// Empty Trash emptied the Trash.
    var onTrashEmptied: () -> Void = {}

    init(context: SettingsContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
        super.init()
        context.emptyTrash = { [weak self] in self?.confirmEmptyTrash() }
    }

    /// The window is on screen.
    var isVisible: Bool { window?.isVisible ?? false }
    var windowNumber: Int? { window?.windowNumber }
    var selectedTab: SettingsTab? {
        guard let tabs else { return nil }
        let raw = tabs.tabViewItems[tabs.selectedTabViewItemIndex].identifier as? String
        return raw.flatMap(SettingsTab.init(rawValue:))
    }

    /// Opens Settings on `tab`, or on the tab of last time; brings it forward if it is open.
    func show(tab: SettingsTab? = nil, remembering: Bool = true) {
        let window = window ?? makeWindow()
        remembersTab = remembering
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) { tabs?.selectedTabViewItemIndex = index }
        remembersTab = true
        hidePanel()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        context.trash.refresh()
        window.makeKeyAndOrderFront(nil)
        // No recorder starts with the keyboard focus ring; Tab (with Full Keyboard Access) reaches them.
        window.makeFirstResponder(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = SettingsTabViewController()
        controller.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host: NSHostingController<AnyView>
            switch tab {
            case .general: host = NSHostingController(rootView: AnyView(GeneralSettingsView(context: context)))
            case .shortcuts: host = NSHostingController(rootView: AnyView(ShortcutsSettingsView(context: context)))
            }
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.identifier = tab.rawValue
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            controller.addTabViewItem(item)
        }
        controller.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: SettingsTab.stored(in: defaults)) ?? 0
        controller.onSelect = { [weak self] tab in
            guard let self else { return }
            // The tab view controller sets the title only once the window is up.
            window?.title = tab.title
            if remembersTab { defaults.set(tab.rawValue, forKey: SettingsTab.defaultsKey) }
        }
        tabs = controller

        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        // The tab sets the title; the first one is there before the first selection.
        window.title = SettingsTab.stored(in: defaults).title
        if !window.setFrameUsingName("Settings") { window.center() }
        window.setFrameAutosaveName("Settings")
        self.window = window
        return window
    }

    // MARK: Empty Trash

    private func confirmEmptyTrash() {
        let count = context.trash.count
        guard count > 0, let window else { return }
        TrashAlerts.confirmEmpty(count: count, in: window) { [weak self] confirmed in
            guard confirmed, let self else { return }
            self.emptyTrash(in: window)
        }
    }

    private func emptyTrash(in window: NSWindow) {
        do {
            try context.trash.empty()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Can’t empty the Trash"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
        }
        onTrashEmptied()
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        context.trash.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
