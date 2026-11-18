/// How a stretch of a Note's text looks, before the Theme turns it into attributes.
public struct TextStyle: Sendable, Hashable {
    public enum Color: Sendable, Hashable {
        case label
        case secondary
        case link
    }

    public enum Background: Sendable, Hashable {
        case highlight
        case code
    }

    public var bold = false
    public var italic = false
    public var monospaced = false
    public var strikethrough = false
    /// `nil` leaves the color of the enclosing style.
    public var color: Color?
    /// `nil` leaves the background of the enclosing style.
    public var background: Background?

    public init(
        bold: Bool = false,
        italic: Bool = false,
        monospaced: Bool = false,
        strikethrough: Bool = false,
        color: Color? = nil,
        background: Background? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.monospaced = monospaced
        self.strikethrough = strikethrough
        self.color = color
        self.background = background
    }
}

extension TextStyle {
    /// `inner` applied on top: flags add up, colors and backgrounds of `inner` win where it sets them.
    func merging(_ inner: TextStyle) -> TextStyle {
        TextStyle(
            bold: bold || inner.bold,
            italic: italic || inner.italic,
            monospaced: monospaced || inner.monospaced,
            strikethrough: strikethrough || inner.strikethrough,
            color: inner.color ?? color,
            background: inner.background ?? background
        )
    }
}
