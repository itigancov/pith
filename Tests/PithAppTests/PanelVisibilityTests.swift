import Testing
@testable import PithApp

struct PanelVisibilityTests {
    final class Window {}
    let panel = Window()
    let sheet = Window()

    @Test func keyLeavingForAnotherAppHidesThePanel() {
        #expect(PanelVisibility.shouldHide(panel: panel, attachedSheet: nil, newKey: nil))
    }

    @Test func keyLeavingForAnotherWindowOfPithHidesThePanel() {
        #expect(PanelVisibility.shouldHide(panel: panel, attachedSheet: nil, newKey: Window()))
        #expect(PanelVisibility.shouldHide(panel: panel, attachedSheet: sheet, newKey: Window()))
    }

    @Test func keyMovingToThePanelsOwnSheetKeepsItShown() {
        #expect(!PanelVisibility.shouldHide(panel: panel, attachedSheet: sheet, newKey: sheet))
    }

    @Test func keyComingBackFromTheSheetToThePanelKeepsItShown() {
        #expect(!PanelVisibility.shouldHide(panel: panel, attachedSheet: sheet, newKey: panel))
    }

    @Test func keyLeavingTheSheetForAnotherAppHidesThePanel() {
        #expect(PanelVisibility.shouldHide(panel: panel, attachedSheet: sheet, newKey: nil))
    }
}
