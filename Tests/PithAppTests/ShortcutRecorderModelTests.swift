import AppKit
import Carbon.HIToolbox
import Testing
@testable import PithApp

struct ShortcutRecorderModelTests {
    private let command = Shortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: .command)

    private func recording() -> ShortcutRecorderModel {
        var model = ShortcutRecorderModel()
        _ = model.handle(.begin)
        return model
    }

    @Test func beginStartsTheRecordingFromRest() {
        var model = ShortcutRecorderModel()
        #expect(model.handle(.begin) == .none)
        #expect(model.state == .recording(error: nil))
    }

    @Test func aKeyWithCommandIsCommittedAndAnAcceptedOneReturnsToRest() {
        var model = recording()
        #expect(model.handle(.key(command)) == .commit(command))
        model.resolve(nil)
        #expect(model.state == .idle)
    }

    @Test func aRejectedKeyKeepsRecordingWithTheReason() {
        var model = recording()
        _ = model.handle(.key(command))
        model.resolve(.usedBy("Bold"))
        #expect(model.state == .recording(error: "Used by Bold"))
        _ = model.handle(.key(command))
        model.resolve(nil)
        #expect(model.error == nil)
    }

    @Test func aKeyWithoutCommandOptionControlIsAnErrorAndRecordingGoesOn() {
        var model = recording()
        #expect(model.handle(.key(Shortcut(keyCode: 0, modifiers: .shift))) == .none)
        #expect(model.state == .recording(error: "Use ⌘, ⌥ or ⌃ in the shortcut"))
    }

    @Test func modifiersAloneChangeNothing() {
        var model = recording()
        #expect(model.handle(.modifiersOnly) == .none)
        #expect(model.state == .recording(error: nil))
    }

    @Test(arguments: [ShortcutRecorderModel.Input.escape, .lostFocus, .click])
    func cancellingInputsEndTheRecordingAndClearTheError(input: ShortcutRecorderModel.Input) {
        var model = recording()
        _ = model.handle(.key(Shortcut(keyCode: 0, modifiers: [])))
        #expect(model.error != nil)
        #expect(model.handle(input) == .none)
        #expect(model.state == .idle)
    }

    @Test func tabCancelsAndMovesFocus() {
        var model = recording()
        #expect(model.handle(.tab(reverse: false)) == .moveFocus(reverse: false))
        #expect(model.state == .idle)
        model = recording()
        #expect(model.handle(.tab(reverse: true)) == .moveFocus(reverse: true))
    }

    @Test func aClickAtRestStartsTheRecording() {
        var model = ShortcutRecorderModel()
        _ = model.handle(.click)
        #expect(model.isRecording)
    }

    @Test(arguments: [ShortcutRecorderModel.Input.escape, .lostFocus, .modifiersOnly, .tab(reverse: false)])
    func inputsAtRestDoNothing(input: ShortcutRecorderModel.Input) {
        var model = ShortcutRecorderModel()
        #expect(model.handle(input) == .none)
        #expect(model.state == .idle)
    }

    @Test func escapeAndTabWithoutModifiersAreTheRecordersOwnKeys() {
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Escape), modifiers: []) == .escape)
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Tab), modifiers: []) == .tab(reverse: false))
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Tab), modifiers: .shift) == .tab(reverse: true))
    }

    // MARK: Return in the large recorder

    private func large(_ state: ShortcutRecorderModel.State = .idle) -> ShortcutRecorderModel {
        ShortcutRecorderModel(state: state, returnPerformsDefault: true)
    }

    @Test func bareReturnIsItsOwnInput() {
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Return), modifiers: []) == .bareReturn)
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_ANSI_KeypadEnter), modifiers: .capsLock) == .bareReturn)
    }

    @Test func returnWithAModifierIsAnOrdinaryKey() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_Return), modifiers: .command)
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Return), modifiers: .command) == .key(shortcut))
        var model = large(.recording(error: nil))
        #expect(model.handle(.key(shortcut)) == .commit(shortcut))
    }

    @Test func bareReturnWhileRecordingCancelsAndPerformsTheDefault() {
        var model = large(.recording(error: "Used by Bold"))
        #expect(model.handle(.bareReturn) == .performDefault)
        #expect(model.state == .idle)
    }

    @Test func bareReturnAtRestPerformsTheDefault() {
        var model = large()
        #expect(model.handle(.bareReturn) == .performDefault)
        #expect(model.state == .idle)
    }

    @Test func theCompactRecorderKeepsItsReturn() {
        var model = ShortcutRecorderModel()
        #expect(model.handle(.bareReturn) == .none)
        #expect(model.state == .recording(error: nil))
        // Recording, a bare Return is a key with no modifier, as before.
        #expect(model.handle(.bareReturn) == .none)
        #expect(model.state == .recording(error: "Use ⌘, ⌥ or ⌃ in the shortcut"))
    }

    @Test func commandEscapeAndCommandTabAreOrdinaryKeys() {
        let escape = Shortcut(keyCode: UInt32(kVK_Escape), modifiers: .command)
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Escape), modifiers: .command) == .key(escape))
        let tab = Shortcut(keyCode: UInt32(kVK_Tab), modifiers: [.control, .shift])
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Tab), modifiers: [.control, .shift]) == .key(tab))
        // Caps Lock and Fn do not count as modifiers.
        #expect(ShortcutRecorderModel.Input(keyCode: UInt32(kVK_Escape), modifiers: .capsLock) == .escape)
    }
}
