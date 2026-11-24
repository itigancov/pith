import AppKit

/// The menu bar icon: the Logo-Phi ring and caret in one color, drawn in code so it is sharp at any scale.
/// A template image, so the system tints it for the menu bar's appearance.
enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()

            let ring = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 8, height: 8))
            ring.lineWidth = 1.6
            ring.stroke()

            let caret = NSRect(x: 7.1, y: 1.75, width: 1.8, height: 12.5)
            NSBezierPath(roundedRect: caret, xRadius: 0.9, yRadius: 0.9).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pith"
        return image
    }()
}
