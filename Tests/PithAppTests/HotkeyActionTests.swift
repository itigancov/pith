import Testing
@testable import PithApp

struct HotkeyActionTests {
    @Test func hiddenPanelShows() {
        #expect(HotkeyAction.decide(isShown: false, isKey: false) == .show)
    }

    @Test func shownAndKeyPanelHides() {
        #expect(HotkeyAction.decide(isShown: true, isKey: true) == .hide)
    }

    @Test func shownPanelWithoutKeyIsRevealedNotHidden() {
        #expect(HotkeyAction.decide(isShown: true, isKey: false) == .reveal)
    }
}
