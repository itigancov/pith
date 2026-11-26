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

    private var travel: CGFloat = 0
    private var isArmed = false

    /// - Parameters:
    ///   - deltaX: Horizontal travel of the fingers of this event, positive to the right.
    ///   - deltaY: Vertical travel; a gesture that starts more vertical than horizontal is a scroll, not a swipe.
    /// - Returns: The turn, once per gesture; fingers to the left turn to the next Note.
    mutating func feed(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) -> Turn? {
        // The inertia after the fingers lift never turns a page.
        guard momentum.isEmpty else { return nil }
        if phase.contains(.began) {
            travel = 0
            isArmed = abs(deltaX) > abs(deltaY)
        }
        guard isArmed, !phase.isEmpty else { return nil }
        travel += deltaX
        if phase.contains(.ended) || phase.contains(.cancelled) { isArmed = false }
        guard abs(travel) >= Self.threshold else { return nil }
        isArmed = false
        return travel < 0 ? .next : .previous
    }
}
