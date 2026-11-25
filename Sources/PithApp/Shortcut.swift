import AppKit
import Carbon.HIToolbox

/// A key combination. The key code is the physical key, the same on any keyboard layout.
nonisolated struct Shortcut: Equatable, Hashable, Sendable, Codable {
    /// The modifiers a Shortcut can hold; Caps Lock, Fn and numeric pad are dropped.
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    /// The modifiers of which at least one must be held.
    static let anchorModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt32.self, forKey: .keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: try container.decode(UInt.self, forKey: .modifiers))
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    var hasAnchorModifier: Bool { !modifiers.isDisjoint(with: Self.anchorModifiers) }

    /// `flags` as the modifier bits `RegisterEventHotKey` takes; flags other than ⌘ ⌥ ⌃ ⇧ are dropped.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    var carbonModifiers: UInt32 { Self.carbonModifiers(modifiers) }
}

/// The seven commands whose Shortcut the user can change.
nonisolated enum ShortcutAction: String, CaseIterable, Sendable {
    case hotkey, newNote, goToLatest, searchNotes, previousNote, nextNote, moveToTrash

    /// The row's label, also the name in "Used by …".
    var title: String {
        switch self {
        case .hotkey: "Open and hide Pith"
        case .newNote: "New note"
        case .goToLatest: "Go to latest note"
        case .searchNotes: "Search notes"
        case .previousNote: "Previous note"
        case .nextNote: "Next note"
        case .moveToTrash: "Move to Trash"
        }
    }

    /// Everything but the Hotkey works only inside the Panel, next to the text editor.
    var isPanelOnly: Bool { self != .hotkey }

    var defaultShortcut: Shortcut {
        switch self {
        case .hotkey: Shortcut(keyCode: UInt32(kVK_Space), modifiers: .option)
        case .newNote: Shortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: .command)
        case .goToLatest: Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: .command)
        case .searchNotes: Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: .command)
        case .previousNote: Shortcut(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: [.command, .shift])
        case .nextNote: Shortcut(keyCode: UInt32(kVK_ANSI_RightBracket), modifiers: [.command, .shift])
        case .moveToTrash: Shortcut(keyCode: UInt32(kVK_Delete), modifiers: .command)
        }
    }
}

/// Why a Shortcut cannot be assigned; `message` is the text under the row.
nonisolated enum Rejection: Equatable, Sendable {
    case needsModifier
    case needsCommandOrControl
    case usedBy(String)
    case textEditing
    case system
    case carbon

    var message: String {
        switch self {
        case .needsModifier: "Use ⌘, ⌥ or ⌃ in the shortcut"
        case .needsCommandOrControl: "Add ⌘ or ⌃: ⌥ alone types characters"
        case .usedBy(let title): "Used by \(title)"
        case .textEditing: "Used by text editing"
        case .system: "Used by macOS"
        case .carbon: "Can't use this shortcut, another app may own it"
        }
    }
}

// MARK: - Keys and their labels

/// Which character a physical key types. The live one asks an ASCII-capable layout, so labels and menu key equivalents
/// are the same whatever layout is active; tests substitute their own.
nonisolated protocol KeyLayout: Sendable {
    /// The character the key types with no modifiers, lowercase, or `nil` for a key that types none.
    func character(forKeyCode keyCode: UInt32) -> String?
}

nonisolated struct LiveKeyLayout: KeyLayout {
    func character(forKeyCode keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).lowercased()
        }
    }
}

nonisolated extension Shortcut {
    private struct Named {
        var glyph: String
        var spoken: String
        /// The `keyEquivalent` a menu item uses for the key.
        var equivalent: String
    }

    private static func fn(_ index: Int) -> UnicodeScalar {
        UnicodeScalar(UInt32(NSF1FunctionKey) + UInt32(index - 1))!
    }

    private static let named: [UInt32: Named] = {
        var table: [UInt32: Named] = [
            UInt32(kVK_Space): Named(glyph: "Space", spoken: "Space", equivalent: " "),
            UInt32(kVK_Delete): Named(glyph: "⌫", spoken: "Delete", equivalent: "\u{8}"),
            UInt32(kVK_ForwardDelete): Named(glyph: "⌦", spoken: "Forward Delete", equivalent: "\u{7F}"),
            UInt32(kVK_Return): Named(glyph: "↩", spoken: "Return", equivalent: "\r"),
            UInt32(kVK_ANSI_KeypadEnter): Named(glyph: "↩", spoken: "Return", equivalent: "\u{3}"),
            UInt32(kVK_Tab): Named(glyph: "⇥", spoken: "Tab", equivalent: "\t"),
            UInt32(kVK_Escape): Named(glyph: "⎋", spoken: "Escape", equivalent: "\u{1B}"),
            UInt32(kVK_LeftArrow): Named(glyph: "←", spoken: "Left Arrow", equivalent: String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)),
            UInt32(kVK_RightArrow): Named(glyph: "→", spoken: "Right Arrow", equivalent: String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)),
            UInt32(kVK_UpArrow): Named(glyph: "↑", spoken: "Up Arrow", equivalent: String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)),
            UInt32(kVK_DownArrow): Named(glyph: "↓", spoken: "Down Arrow", equivalent: String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)),
            UInt32(kVK_PageUp): Named(glyph: "⇞", spoken: "Page Up", equivalent: String(UnicodeScalar(UInt32(NSPageUpFunctionKey))!)),
            UInt32(kVK_PageDown): Named(glyph: "⇟", spoken: "Page Down", equivalent: String(UnicodeScalar(UInt32(NSPageDownFunctionKey))!)),
            UInt32(kVK_Home): Named(glyph: "↖", spoken: "Home", equivalent: String(UnicodeScalar(UInt32(NSHomeFunctionKey))!)),
            UInt32(kVK_End): Named(glyph: "↘", spoken: "End", equivalent: String(UnicodeScalar(UInt32(NSEndFunctionKey))!)),
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functionKeys.enumerated() {
            table[UInt32(code)] = Named(glyph: "F\(index + 1)", spoken: "F\(index + 1)", equivalent: String(fn(index + 1)))
        }
        return table
    }()

    private static let punctuationNames: [String: String] = [
        "[": "left bracket", "]": "right bracket", ",": "comma", ".": "period", "/": "slash", "\\": "backslash",
        ";": "semicolon", "'": "apostrophe", "`": "grave accent", "-": "minus", "=": "equals",
    ]

    /// Whether the key is one of the navigation and deletion keys a text view acts on.
    var isNavigationKey: Bool {
        [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown]
            .contains { UInt32($0) == keyCode }
    }

    /// The chips of the Shortcut: modifiers in the standard order ⌃ ⌥ ⇧ ⌘, then the key.
    func chips(layout: KeyLayout) -> [String] {
        var result: [String] = []
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        if let key = Self.named[keyCode] {
            result.append(key.glyph)
        } else if let character = layout.character(forKeyCode: keyCode) {
            result.append(character.uppercased())
        } else {
            result.append("Key \(keyCode)")
        }
        return result
    }

    /// What VoiceOver reads, such as "Shift Command left bracket".
    func spokenName(layout: KeyLayout) -> String {
        var words: [String] = []
        if modifiers.contains(.control) { words.append("Control") }
        if modifiers.contains(.option) { words.append("Option") }
        if modifiers.contains(.shift) { words.append("Shift") }
        if modifiers.contains(.command) { words.append("Command") }
        if let key = Self.named[keyCode] {
            words.append(key.spoken)
        } else if let character = layout.character(forKeyCode: keyCode) {
            words.append(Self.punctuationNames[character] ?? character.uppercased())
        } else {
            words.append("key \(keyCode)")
        }
        return words.joined(separator: " ")
    }

    /// The key equivalent a menu item would use for the key, lowercase for letters; `nil` if the layout has none.
    func keyEquivalent(layout: KeyLayout) -> String? {
        Self.named[keyCode]?.equivalent ?? layout.character(forKeyCode: keyCode)
    }
}
