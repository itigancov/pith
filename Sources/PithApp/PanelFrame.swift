import CoreGraphics

/// Where the Panel stands on a screen: pure functions over rects, no AppKit state.
enum PanelFrame {
    static let defaultSize = CGSize(width: 540, height: 440)
    static let minimumSize = CGSize(width: 400, height: 300)

    /// `size` within `[minimumSize, visibleFrame.size]`; the screen wins when it is smaller than the minimum.
    static func clampedSize(_ size: CGSize, visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumSize.width), visibleFrame.width),
            height: min(max(size.height, minimumSize.height), visibleFrame.height)
        )
    }

    /// The Panel's frame on a screen with `visibleFrame`, from the stored frame or, without one, the default in the center.
    static func frame(stored: StoredPanelFrame?, visibleFrame: CGRect) -> CGRect {
        let stored = stored ?? StoredPanelFrame(width: defaultSize.width, height: defaultSize.height, fx: 0.5, fy: 0.5)
        let size = clampedSize(CGSize(width: stored.width, height: stored.height), visibleFrame: visibleFrame)
        return CGRect(
            x: visibleFrame.minX + clamped(stored.fx) * (visibleFrame.width - size.width),
            y: visibleFrame.minY + clamped(stored.fy) * (visibleFrame.height - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// The stored form of `frame` on a screen with `visibleFrame`; `frame(stored:visibleFrame:)` turns it back.
    static func stored(from frame: CGRect, visibleFrame: CGRect) -> StoredPanelFrame {
        StoredPanelFrame(
            width: frame.width,
            height: frame.height,
            fx: fraction(offset: frame.minX - visibleFrame.minX, room: visibleFrame.width - frame.width),
            fy: fraction(offset: frame.minY - visibleFrame.minY, room: visibleFrame.height - frame.height)
        )
    }

    /// How far along the free `room` an `offset` is, in `[0, 1]`; the middle when there is no room.
    private static func fraction(offset: CGFloat, room: CGFloat) -> Double {
        room > 0 ? clamped(offset / room) : 0.5
    }

    private static func clamped(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}

/// The Panel's size and its position as fractions of the free room on a screen, so it lands in the same place on any screen.
struct StoredPanelFrame: Codable, Equatable {
    var width: Double
    var height: Double
    var fx: Double
    var fy: Double
}
