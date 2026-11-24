import CoreGraphics
import Testing
@testable import PithApp

struct PanelFrameTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func withoutStoredFrameThePanelIsDefaultSizeInTheCenter() {
        #expect(PanelFrame.frame(stored: nil, visibleFrame: screen) == CGRect(x: 450, y: 230, width: 540, height: 440))
    }

    @Test func aFrameIsStoredAsItsSizeAndFractionsOfTheFreeRoom() {
        let frame = CGRect(x: 210, y: 100, width: 600, height: 500)
        let stored = PanelFrame.stored(from: frame, visibleFrame: screen)
        #expect(stored == StoredPanelFrame(width: 600, height: 500, fx: 0.25, fy: 0.25))
        #expect(PanelFrame.frame(stored: stored, visibleFrame: screen) == frame)
    }

    @Test func aPanelPartlyOffTheScreenIsStoredAtTheEdge() {
        let frame = CGRect(x: -100, y: 600, width: 540, height: 440)
        #expect(PanelFrame.stored(from: frame, visibleFrame: screen) == StoredPanelFrame(width: 540, height: 440, fx: 0, fy: 1))
    }

    @Test func aStoredFractionOutsideTheRangeIsClamped() {
        let stored = StoredPanelFrame(width: 540, height: 440, fx: -2, fy: 7)
        #expect(PanelFrame.frame(stored: stored, visibleFrame: screen) == CGRect(x: 0, y: 460, width: 540, height: 440))
    }

    @Test func aStoredSizeLargerThanTheScreenShrinksToIt() {
        let small = CGRect(x: 0, y: 25, width: 1024, height: 743)
        let stored = StoredPanelFrame(width: 1200, height: 800, fx: 0.3, fy: 0.7)
        #expect(PanelFrame.frame(stored: stored, visibleFrame: small) == small)
    }

    @Test func aStoredSizeBelowTheMinimumGrowsToIt() {
        let stored = StoredPanelFrame(width: 100, height: 50, fx: 0.5, fy: 0.5)
        #expect(PanelFrame.frame(stored: stored, visibleFrame: screen) == CGRect(x: 520, y: 300, width: 400, height: 300))
    }

    @Test func thePositionCarriesOverToAnotherScreenByFractions() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
        let stored = StoredPanelFrame(width: 540, height: 440, fx: 0.25, fy: 0.75)
        let frame = PanelFrame.frame(stored: stored, visibleFrame: left)
        #expect(frame == CGRect(x: -1575, y: 261.25, width: 540, height: 440))
        #expect(PanelFrame.stored(from: frame, visibleFrame: left) == stored)
    }

    @Test func aPanelAsWideAsTheScreenIsStoredInTheMiddle() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(PanelFrame.stored(from: frame, visibleFrame: screen) == StoredPanelFrame(width: 1440, height: 900, fx: 0.5, fy: 0.5))
    }
}
