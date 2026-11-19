/// How a stretch of a Note's text looks, before the Theme turns it into attributes.
public struct TextStyle: Sendable, Hashable {
    public enum Color: Sendable, Hashable {
        case label
        case secondary
        case link
    }

    public var bold = false
    public var italic = false
    public var monospaced = false
    public var strikethrough = false
    /// `nil` leaves the color of the enclosing style.
    public var color: Color?
    /// The plates behind the text, outer first.
    public var plates: [PlateKind]

    public init(
        bold: Bool = false,
        italic: Bool = false,
        monospaced: Bool = false,
        strikethrough: Bool = false,
        color: Color? = nil,
        plates: [PlateKind] = []
    ) {
        self.bold = bold
        self.italic = italic
        self.monospaced = monospaced
        self.strikethrough = strikethrough
        self.color = color
        self.plates = plates
    }
}

extension TextStyle {
    /// `inner` applied on top: flags add up, the color of `inner` wins where it sets one, and its plates lie on top.
    func merging(_ inner: TextStyle) -> TextStyle {
        TextStyle(
            bold: bold || inner.bold,
            italic: italic || inner.italic,
            monospaced: monospaced || inner.monospaced,
            strikethrough: strikethrough || inner.strikethrough,
            color: inner.color ?? color,
            plates: plates + inner.plates.filter { !plates.contains($0) }
        )
    }
}
