import AppKit
import Carbon.HIToolbox

/// The global shortcut that shows and hides the Panel. The key code is the physical key, the same on any keyboard layout.
nonisolated struct Hotkey: Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    /// ⌥Space.
    static let `default` = Hotkey(keyCode: UInt32(kVK_Space), modifiers: .option)

    /// `flags` as the modifier bits `RegisterEventHotKey` takes; flags other than ⌘ ⌥ ⌃ ⇧ are dropped.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}
