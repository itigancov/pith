import AppKit
import Testing
@testable import PithApp

struct SwipeAccumulatorTests {
    private var swipe = SwipeAccumulator()

    private mutating func feed(_ dx: CGFloat, dy: CGFloat = 0, _ phase: NSEvent.Phase, momentum: NSEvent.Phase = []) -> SwipeAccumulator.Turn? {
        swipe.feed(deltaX: dx, deltaY: dy, phase: phase, momentum: momentum)
    }

    @Test mutating func fingersToTheLeftTurnToTheNextNote() {
        #expect(feed(-20, .began) == nil)
        #expect(feed(-20, .changed) == nil)
        #expect(feed(-15, .changed) == .next)
    }

    @Test mutating func fingersToTheRightTurnBack() {
        #expect(feed(30, .began) == nil)
        #expect(feed(25, .changed) == .previous)
    }

    @Test mutating func oneGestureTurnsOnce() {
        _ = feed(-30, .began)
        #expect(feed(-30, .changed) == .next)
        #expect(feed(-80, .changed) == nil)
        #expect(feed(-80, .changed) == nil)
        #expect(feed(0, .ended) == nil)
    }

    @Test mutating func aShortGestureTurnsNothing() {
        _ = feed(-20, .began)
        #expect(feed(-20, .changed) == nil)
        #expect(feed(0, .ended) == nil)
    }

    @Test mutating func aNewGestureStartsFromZero() {
        _ = feed(-30, .began)
        _ = feed(-10, .changed)
        _ = feed(0, .ended)
        _ = feed(-30, .began)
        #expect(feed(-10, .changed) == nil)
        #expect(feed(-15, .changed) == .next)
    }

    @Test mutating func theInertiaAfterTheFingersLiftIsIgnored() {
        _ = feed(-20, .began)
        _ = feed(-20, .changed)
        _ = feed(0, .ended)
        #expect(feed(-60, [], momentum: .changed) == nil)
    }

    @Test mutating func aMostlyVerticalGestureIsAScroll() {
        #expect(feed(-5, dy: -30, .began) == nil)
        #expect(feed(-60, .changed) == nil)
    }

    @Test mutating func eventsWithoutAPhaseAreIgnored() {
        // A mouse wheel has no gesture.
        #expect(feed(-80, []) == nil)
    }
}
