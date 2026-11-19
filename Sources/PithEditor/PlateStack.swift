import AppKit

/// What a plate behind text is for; each kind has its own shape and color.
public enum PlateKind: Sendable, Hashable {
    /// A rounded plate as tall as the font, around the text and its `==`.
    case highlight
    /// A rounded plate as tall as the font, around the code and its backticks.
    case inlineCode
    /// One plate across the whole width of the text, from the opening fence to the closing one.
    case codeBlock
}

extension NSAttributedString.Key {
    /// The plates behind a character, as a `PlateStack`. `PlateLayoutFragment` draws them.
    public static let pithBackground = NSAttributedString.Key("PithBackground")
}

/// The value of `.pithBackground`: the kinds of the plates behind a character, outer first.
/// An object, so that equal stacks compare equal and neighbors coalesce into one attribute run.
public final class PlateStack: NSObject, Sendable {
    public let kinds: [PlateKind]

    public init(_ kinds: [PlateKind]) {
        self.kinds = kinds
    }

    public override func isEqual(_ object: Any?) -> Bool {
        (object as? PlateStack)?.kinds == kinds
    }

    public override var hash: Int { kinds.hashValue }
}
