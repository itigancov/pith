import AppKit
import Carbon.HIToolbox

/// The states of a Shortcut recorder and what moves it between them, with no AppKit in it.
/// The view turns events into `Input` and acts on the `Output`.
nonisolated struct ShortcutRecorderModel: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        /// Waiting for keys; `error` is the text under the row, `nil` for none.
        case recording(error: String?)
    }

    enum Input: Equatable, Sendable {
        /// Space or Return on the focused recorder.
        case begin
        /// A click on the recorder: starts the recording, or cancels it.
        case click
        /// A key with the modifiers held.
        case key(Shortcut)
        /// Return or Enter with no modifiers: the large recorder hands it to the window's default action, the compact one takes it as a key.
        case bareReturn
        /// Only modifiers changed.
        case modifiersOnly
        /// Esc with no modifiers.
        case escape
        /// Tab (or ⇧Tab with `reverse`) with no modifiers.
        case tab(reverse: Bool)
        /// A click elsewhere, or the window or the recorder lost focus.
        case lostFocus

        /// What a key press means while recording: Esc and Tab with no modifiers (⇧ allowed for Tab) are the recorder's own
        /// keys; every other key, ⌘Esc included, is a candidate.
        init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
            let held = modifiers.intersection(Shortcut.relevantModifiers)
            if held.isEmpty, keyCode == UInt32(kVK_Escape) {
                self = .escape
            } else if held.isEmpty, keyCode == UInt32(kVK_Return) || keyCode == UInt32(kVK_ANSI_KeypadEnter) {
                self = .bareReturn
            } else if keyCode == UInt32(kVK_Tab), held.isEmpty || held == .shift {
                self = .tab(reverse: held == .shift)
            } else {
                self = .key(Shortcut(keyCode: keyCode, modifiers: held))
            }
        }
    }

    enum Output: Equatable, Sendable {
        case none
        /// The host should try to assign the Shortcut and answer with `resolve`.
        case commit(Shortcut)
        /// The recording ended and focus should move on.
        case moveFocus(reverse: Bool)
        /// The recording (if any) ended and the window's default action (Continue) should run.
        case performDefault
    }

    private(set) var state: State
    /// Whether a bare Return is the window's default action rather than a key to record or a way to begin: the large recorder.
    let returnPerformsDefault: Bool

    init(state: State = .idle, returnPerformsDefault: Bool = false) {
        self.state = state
        self.returnPerformsDefault = returnPerformsDefault
    }

    var isRecording: Bool { if case .recording = state { true } else { false } }

    var error: String? { if case .recording(let error) = state { error } else { nil } }

    mutating func handle(_ input: Input) -> Output {
        var input = input
        if input == .bareReturn {
            if returnPerformsDefault {
                state = .idle
                return .performDefault
            }
            // As before: Return begins at rest and is a key with no modifier while recording.
            input = isRecording ? .key(Shortcut(keyCode: UInt32(kVK_Return), modifiers: [])) : .begin
        }
        switch (state, input) {
        case (.idle, .begin), (.idle, .click):
            state = .recording(error: nil)
        case (.recording, .click), (.recording, .escape), (.recording, .lostFocus):
            state = .idle
        case (.recording, .tab(let reverse)):
            state = .idle
            return .moveFocus(reverse: reverse)
        case (.recording, .key(let shortcut)):
            guard shortcut.hasAnchorModifier else {
                state = .recording(error: Rejection.needsModifier.message)
                return .none
            }
            return .commit(shortcut)
        default:
            break
        }
        return .none
    }

    /// The host's answer to `commit`: the Shortcut is assigned, or the recording goes on with the reason under the row.
    mutating func resolve(_ rejection: Rejection?) {
        guard isRecording else { return }
        state = rejection.map { .recording(error: $0.message) } ?? .idle
    }
}
