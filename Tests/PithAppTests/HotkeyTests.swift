import AppKit
import Testing
@testable import PithApp

struct HotkeyTests {
    // Carbon's modifier bits from Events.h: cmdKey 1 << 8, shiftKey 1 << 9, optionKey 1 << 11, controlKey 1 << 12.

    @Test(arguments: [
        (NSEvent.ModifierFlags.command, UInt32(0x100)),
        (.shift, 0x200),
        (.option, 0x800),
        (.control, 0x1000),
    ])
    func eachModifierMapsToItsCarbonBit(flags: NSEvent.ModifierFlags, carbon: UInt32) {
        #expect(Hotkey.carbonModifiers(flags) == carbon)
    }

    @Test func combinedModifiersMapToTheUnionOfTheirBits() {
        #expect(Hotkey.carbonModifiers([.control, .option]) == 0x1800)
        #expect(Hotkey.carbonModifiers([.command, .shift, .option, .control]) == 0x1B00)
    }

    @Test func flagsThatAreNotModifiersAreIgnored() {
        #expect(Hotkey.carbonModifiers([.option, .capsLock, .function, .numericPad]) == 0x800)
        #expect(Hotkey.carbonModifiers([]) == 0)
    }

    @Test func theDefaultIsOptionSpace() {
        #expect(Hotkey.default == Hotkey(keyCode: 49, modifiers: .option))
    }
}
