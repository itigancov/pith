import AppKit
import Carbon.HIToolbox

/// Registers and frees the Hotkey; `HotkeyCenter` is the live one, tests substitute a fake.
protocol HotkeyRegistering: AnyObject {
    /// Registers `shortcut`, replacing an earlier registration; `false` if the system refused.
    func register(_ shortcut: Shortcut) -> Bool
    func unregister()
}

/// A menu item that has a key equivalent.
nonisolated struct MenuKey: Equatable, Sendable {
    var title: String
    /// Lowercase; an uppercase letter in a menu item's `keyEquivalent` is already folded into `modifiers` as ⇧.
    var key: String
    var modifiers: NSEvent.ModifierFlags

    /// The items of `menu` and its submenus that have a key equivalent, except those that belong to one of the seven rows
    /// (they carry the row's raw value as `identifier`; the rows are checked against each other instead).
    @MainActor
    static func items(in menu: NSMenu?) -> [MenuKey] {
        guard let menu else { return [] }
        let rows = Set(ShortcutAction.allCases.map(\.rawValue))
        var result: [MenuKey] = []
        for item in menu.items {
            if let submenu = item.submenu { result += items(in: submenu) }
            guard !item.keyEquivalent.isEmpty, !rows.contains(item.identifier?.rawValue ?? "") else { continue }
            var modifiers = item.keyEquivalentModifierMask.intersection(Shortcut.relevantModifiers)
            let lower = item.keyEquivalent.lowercased()
            if lower != item.keyEquivalent { modifiers.insert(.shift) }
            result.append(MenuKey(title: item.title, key: lower, modifiers: modifiers))
        }
        return result
    }

    /// The live main menu.
    @MainActor
    static func liveItems() -> [MenuKey] { items(in: NSApp.mainMenu) }
}

/// The system's own shortcuts that are turned on, from `CopySymbolicHotKeys`.
nonisolated enum SystemShortcuts {
    static func enabled() -> [Shortcut] {
        var table: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&table) == noErr, let table else { return [] }
        return shortcuts(in: table.takeRetainedValue() as? [[String: Any]] ?? [])
    }

    /// Each entry has `kHISymbolicHotKeyEnabled`, `kHISymbolicHotKeyCode` and `kHISymbolicHotKeyModifiers`.
    static func shortcuts(in entries: [[String: Any]]) -> [Shortcut] {
        entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int, code >= 0, code < 0xFFFF,
                  let carbon = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return nil }
            var modifiers: NSEvent.ModifierFlags = []
            if carbon & cmdKey != 0 { modifiers.insert(.command) }
            if carbon & optionKey != 0 { modifiers.insert(.option) }
            if carbon & controlKey != 0 { modifiers.insert(.control) }
            if carbon & shiftKey != 0 { modifiers.insert(.shift) }
            return Shortcut(keyCode: UInt32(code), modifiers: modifiers)
        }
    }
}

extension Notification.Name {
    /// Posted by a `ShortcutStore` after a Shortcut changed; `object` is the store.
    static let shortcutsDidChange = Notification.Name("PithShortcutsDidChange")
}

/// The seven Shortcuts, their checks and their storage: the one entry point for everything about them.
/// Only values that differ from the default are stored, as JSON under one `UserDefaults` key.
final class ShortcutStore {
    static let defaultsKey = "Shortcuts"

    private let defaults: UserDefaults
    private let menuKeys: @MainActor () -> [MenuKey]
    private let systemShortcuts: () -> [Shortcut]
    private let layout: KeyLayout
    private let registrar: HotkeyRegistering
    private var overrides: [ShortcutAction: Shortcut]
    private var isRecording = false

    init(
        defaults: UserDefaults = .standard,
        menuKeys: @escaping @MainActor () -> [MenuKey] = MenuKey.liveItems,
        systemShortcuts: @escaping () -> [Shortcut] = SystemShortcuts.enabled,
        layout: KeyLayout = LiveKeyLayout(),
        registrar: HotkeyRegistering
    ) {
        self.defaults = defaults
        self.menuKeys = menuKeys
        self.systemShortcuts = systemShortcuts
        self.layout = layout
        self.registrar = registrar
        self.overrides = Self.load(from: defaults)
    }

    /// The row's Shortcut; every row always has one.
    func shortcut(for action: ShortcutAction) -> Shortcut {
        overrides[action] ?? action.defaultShortcut
    }

    /// What a menu item of `action` gets as its key equivalent and mask; `nil` if the layout has no character for the key.
    func menuKey(for action: ShortcutAction) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let shortcut = shortcut(for: action)
        guard let key = shortcut.keyEquivalent(layout: layout) else { return nil }
        return (key, shortcut.modifiers)
    }

    /// The first rule `shortcut` breaks for `action`, or `nil` if it can be assigned.
    func rejection(of shortcut: Shortcut, for action: ShortcutAction) -> Rejection? {
        if let rejection = Self.staticRejection(of: shortcut, for: action) { return rejection }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && self.shortcut(for: $0) == shortcut }) {
            return .usedBy(other.title)
        }
        if let key = shortcut.keyEquivalent(layout: layout),
           let item = menuKeys().first(where: { $0.key == key && $0.modifiers == shortcut.modifiers }) {
            return .usedBy(item.title)
        }
        if Self.isTextEditing(shortcut) { return .textEditing }
        if systemShortcuts().contains(shortcut) { return .system }
        return nil
    }

    /// Assigns `shortcut` to `action`; returns why it cannot be, and then nothing changes.
    /// The Hotkey is also registered with the system, and the previous one stays registered if that fails.
    @discardableResult
    func assign(_ shortcut: Shortcut, to action: ShortcutAction) -> Rejection? {
        let old = self.shortcut(for: action)
        if shortcut == old { return nil }
        if let rejection = rejection(of: shortcut, for: action) { return rejection }
        if action == .hotkey, !registrar.register(shortcut) {
            // A paused Hotkey stays paused; the end of the recording registers the current one.
            if !isRecording { _ = registrar.register(old) }
            return .carbon
        }
        persist(shortcut, for: action)
        return nil
    }

    /// Makes all seven rows default again.
    func restoreDefaults() {
        let before = ShortcutAction.allCases.map(shortcut(for:))
        overrides = [:]
        defaults.removeObject(forKey: Self.defaultsKey)
        if !isRecording, !registrar.register(shortcut(for: .hotkey)) {
            NSLog("Pith: cannot register the default hotkey")
        }
        if before != ShortcutAction.allCases.map(shortcut(for:)) { notify() }
    }

    /// Registers the Hotkey from the store; `false` (and a log line) if the system refused it.
    @discardableResult
    func registerHotkey() -> Bool {
        let hotkey = shortcut(for: .hotkey)
        guard registrar.register(hotkey) else {
            NSLog("Pith: cannot register the hotkey (keyCode %u, modifiers %lu)", hotkey.keyCode, hotkey.modifiers.rawValue)
            return false
        }
        return true
    }

    /// The Hotkey pauses while any row records, so pressing it records it instead of showing the Panel.
    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        if recording {
            registrar.unregister()
        } else {
            registerHotkey()
        }
    }

    // MARK: Rules

    /// Rules that need no other state: the same for the same row anywhere.
    static func staticRejection(of shortcut: Shortcut, for action: ShortcutAction) -> Rejection? {
        guard shortcut.hasAnchorModifier else { return .needsModifier }
        // ⌥ and ⌥⇧ type characters, which a menu item would take from the editor.
        if action.isPanelOnly, shortcut.modifiers.isDisjoint(with: [.command, .control]) { return .needsCommandOrControl }
        return nil
    }

    /// What the text view does with the key. ⌘⌫ is not here: it deliberately replaces `deleteToBeginningOfLine:`.
    static func isTextEditing(_ shortcut: Shortcut) -> Bool {
        let navigates = shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.option)
        if shortcut.isNavigationKey { return navigates }
        let deletes = shortcut.keyCode == UInt32(kVK_Delete) || shortcut.keyCode == UInt32(kVK_ForwardDelete)
        return deletes && shortcut.modifiers.contains(.option)
    }

    // MARK: Storage

    private struct Lossy: Decodable {
        var value: Shortcut?
        init(from decoder: Decoder) { value = try? Shortcut(from: decoder) }
    }

    /// A damaged or no longer allowed value gives the row its default.
    private static func load(from defaults: UserDefaults) -> [ShortcutAction: Shortcut] {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([String: Lossy].self, from: data) else { return [:] }
        var result: [ShortcutAction: Shortcut] = [:]
        for (id, entry) in stored {
            guard let action = ShortcutAction(rawValue: id), let shortcut = entry.value,
                  staticRejection(of: shortcut, for: action) == nil, shortcut != action.defaultShortcut else { continue }
            result[action] = shortcut
        }
        return result
    }

    private func persist(_ shortcut: Shortcut, for action: ShortcutAction) {
        if shortcut == action.defaultShortcut {
            overrides[action] = nil
        } else {
            overrides[action] = shortcut
        }
        let encoded = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        if encoded.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: .shortcutsDidChange, object: self)
    }
}
