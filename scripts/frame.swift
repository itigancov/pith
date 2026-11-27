// Puts a window PNG from `make shots` on a soft gradient with a macOS-style shadow, for the README.
// Usage: swift scripts/frame.swift <window.png> <out.png> <light|dark>
import AppKit

guard CommandLine.arguments.count == 4, let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: frame.swift <window.png> <out.png> <light|dark>\n".utf8))
    exit(2)
}
let dark = CommandLine.arguments[3] == "dark"
let pad: CGFloat = 150
let rep = image.representations[0]
let window = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
let size = CGSize(width: window.width + 2 * pad, height: window.height + 2 * pad)

let out = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
out.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)

let colors: [NSColor] = dark
    ? [NSColor(srgbRed: 0.16, green: 0.17, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.07, green: 0.07, blue: 0.11, alpha: 1)]
    : [NSColor(srgbRed: 0.84, green: 0.86, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.98, green: 0.88, blue: 0.86, alpha: 1)]
NSGradient(colors: colors)!.draw(in: NSRect(origin: .zero, size: size), angle: dark ? 300 : 320)

let target = NSRect(x: pad, y: pad, width: window.width, height: window.height)
let shadows: [(blur: CGFloat, dy: CGFloat, alpha: CGFloat)] = [(90, -40, dark ? 0.6 : 0.30), (10, -4, dark ? 0.5 : 0.22)]
for s in shadows {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = s.blur
    shadow.shadowOffset = NSSize(width: 0, height: s.dy)
    shadow.shadowColor = NSColor.black.withAlphaComponent(s.alpha)
    shadow.set()
    image.draw(in: target)
    NSGraphicsContext.restoreGraphicsState()
}
image.draw(in: target)
NSGraphicsContext.restoreGraphicsState()

try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
