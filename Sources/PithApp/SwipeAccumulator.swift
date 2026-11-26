import AppKit

/// Turns the scroll events of a two-finger gesture into at most one page turn: the horizontal travel of the fingers is
/// summed from the start of the gesture, and the first time it passes the threshold the gesture turns the page.
struct SwipeAccumulator {
    enum Turn: Equatable {
        case next
        case previous
    }

    /// `swipe.threshold`: travel in points.
    static let threshold: CGFloat = 50

    private enum State {
        case idle
        /// The gesture began; the first event that moves decides whether it is a swipe.
        case undecided
        case armed
    }

    private var travel: CGFloat = 0
    private var state = State.idle

    /// - Parameters:
    ///   - deltaX: Horizontal travel of the fingers of this event, positive to the right.
    ///   - deltaY: Vertical travel; a gesture whose first movement is more vertical than horizontal is a scroll, not a swipe.
    /// - Returns: The turn, once per gesture; fingers to the left turn to the next Note.
    mutating func feed(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) -> Turn? {
        // The inertia after the fingers lift never turns a page.
        guard momentum.isEmpty else { return nil }
        if phase.contains(.began) {
            travel = 0
            state = .undecided
        }
        guard !phase.isEmpty else { return nil }
        if state == .undecided, deltaX != 0 || deltaY != 0 {
            state = abs(deltaX) > abs(deltaY) ? .armed : .idle
        }
        guard state == .armed else {
            if phase.contains(.ended) || phase.contains(.cancelled) { state = .idle }
            return nil
        }
        travel += deltaX
        if phase.contains(.ended) || phase.contains(.cancelled) { state = .idle }
        guard abs(travel) >= Self.threshold else { return nil }
        state = .idle
        return travel < 0 ? .next : .previous
    }
}
