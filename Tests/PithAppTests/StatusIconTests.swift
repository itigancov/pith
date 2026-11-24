import AppKit
import Testing
@testable import PithApp

/// Alpha of `image` at the point (`x`, `y`) in points from the top left, rendered at 1 pixel per point.
@MainActor
private func alpha(of image: NSImage, x: Int, y: Int) -> CGFloat {
    let size = Int(image.size.width)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
}

@MainActor
@Suite struct StatusIconTests {
    @Test func isSixteenPointTemplate() {
        #expect(StatusIcon.image.size == NSSize(width: 16, height: 16))
        #expect(StatusIcon.image.isTemplate)
        #expect(StatusIcon.image.accessibilityDescription == "Pith")
    }

    @Test func drawsCaretThroughTheCenter() {
        #expect(alpha(of: StatusIcon.image, x: 8, y: 8) > 0.9)
        #expect(alpha(of: StatusIcon.image, x: 8, y: 3) > 0.9)
    }

    @Test func drawsRingAroundAnEmptyHole() {
        // Ring: center (8, 8), r 4, stroke 1.6 — on y 8 it covers x 11.2 to 12.8.
        #expect(alpha(of: StatusIcon.image, x: 11, y: 8) > 0.5)
        #expect(alpha(of: StatusIcon.image, x: 10, y: 8) < 0.1)
    }

    @Test func leavesTheCornersEmpty() {
        #expect(alpha(of: StatusIcon.image, x: 1, y: 1) < 0.1)
        #expect(alpha(of: StatusIcon.image, x: 14, y: 14) < 0.1)
    }
}
