import AppKit

/// Turns markup kinds into a `TextStyle`, and a `TextStyle` into text attributes.
public struct Theme: Sendable {
    /// The sizes the user can pick, in points.
    public static let sizeRange: ClosedRange<CGFloat> = 10...48
    public static let defaultTextSize: CGFloat = 14

    /// The size of the text; code is one point less.
    public let textSize: CGFloat
    public var monoSize: CGFloat { textSize - 1 }

    /// `textSize` is clamped to `sizeRange`.
    public init(textSize: CGFloat = Theme.defaultTextSize) {
        self.textSize = min(max(textSize, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
    }

    public static let lineHeightMultiple: CGFloat = 1.25
    /// Space between a code block's fences and the top and bottom edges of its plate.
    public static let codeBlockPadding: CGFloat = 4

    public var baseAttributes: [NSAttributedString.Key: Any] {
        var attributes = attributes(for: TextStyle())
        attributes[.paragraphStyle] = paragraphStyle(headIndent: 0)
        return attributes
    }

    /// The style of a stretch of text in a Block of `block`, covered by `spans` listed outer first.
    ///
    /// Flags add up, the innermost color wins and inner plates lie on outer ones. A Marker comes last:
    /// it keeps the plates around it but drops bold, italic and strikethrough.
    public func style(block: BlockKind, spans: [SpanKind]) -> TextStyle {
        let base = TextStyle(color: .label).merging(style(of: block))
        let element = spans.filter { !$0.isMarker }.reduce(base) { $0.merging(style(of: $1)) }
        guard spans.contains(where: \.isMarker) else { return element }
        return TextStyle(monospaced: true, color: .secondary, plates: element.plates)
    }

    private func style(of block: BlockKind) -> TextStyle {
        switch block {
        case .heading: TextStyle(bold: true)
        case .task(_, checked: true): TextStyle(color: .secondary)
        // The whole block is on one plate: fences, body, empty lines and the line breaks between them.
        case .codeBlock: TextStyle(plates: [.codeBlock])
        default: TextStyle()
        }
    }

    private func style(of kind: SpanKind) -> TextStyle {
        switch kind {
        case .strong: TextStyle(bold: true)
        case .emphasis: TextStyle(italic: true)
        case .strikethrough: TextStyle(strikethrough: true)
        case .highlight: TextStyle(plates: [.highlight])
        case .code: TextStyle(monospaced: true, plates: [.inlineCode])
        case .codeContent: TextStyle(monospaced: true, plates: [.codeBlock])
        case .url: TextStyle(color: .link)
        default: TextStyle()
        }
    }

    /// Font, colors, strikethrough and plates; the paragraph style comes from `paragraphStyle(headIndent:)`.
    public func attributes(for style: TextStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style),
            .foregroundColor: color(for: style.color ?? .label),
        ]
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        // The one place backgrounds turn into attributes: a plate drawn by `PlateLayoutFragment`, never `.backgroundColor`.
        if !style.plates.isEmpty { attributes[.pithBackground] = PlateStack(style.plates) }
        return attributes
    }

    /// The accent of the editor: caret, selection and the size slider. One dynamic color, declared here only.
    public static let ink = NSColor(name: "PithInk") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x8D / 255, green: 0xA2 / 255, blue: 0xF5 / 255, alpha: 1)
            : NSColor(srgbRed: 0x3B / 255, green: 0x5B / 255, blue: 0xDB / 255, alpha: 1)
    }

    /// The fill behind selected text: Ink at 22 % in light, 30 % in dark. The text keeps its color.
    public static let selection = NSColor(name: "PithSelection") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return Theme.ink.withAlphaComponent(dark ? 0.30 : 0.22)
    }

    /// Pale yellow, a bit stronger in the dark appearance.
    public var highlightColor: NSColor { Self.highlight }

    // One shared instance: a dynamic color only equals itself.
    private static let highlight = NSColor(name: "PithHighlight") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.systemYellow.withAlphaComponent(dark ? 0.35 : 0.25)
    }

    private func color(for color: TextStyle.Color) -> NSColor {
        switch color {
        case .label: .labelColor
        case .secondary: .secondaryLabelColor
        case .link: .linkColor
        }
    }

    /// The fill of a plate of `kind`.
    public func color(for kind: PlateKind) -> NSColor {
        switch kind {
        case .highlight: highlightColor
        case .inlineCode, .codeBlock: .quaternarySystemFill
        }
    }

    private func font(for style: TextStyle) -> NSFont {
        let weight: NSFont.Weight = style.bold ? .bold : .regular
        let font = style.monospaced
            ? NSFont.monospacedSystemFont(ofSize: monoSize, weight: weight)
            : NSFont.systemFont(ofSize: textSize, weight: weight)
        guard style.italic else { return font }
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    public func paragraphStyle(headIndent: CGFloat, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Self.lineHeightMultiple
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.paragraphSpacing = spacingAfter
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = headIndent
        return paragraph
    }
}

extension SpanKind {
    /// Markup characters rather than a marked-up element.
    var isMarker: Bool {
        switch self {
        case .headingMarker, .listMarker, .taskCheckbox, .quoteMarker, .fence, .fenceLanguage, .inlineMarker: true
        case .codeContent, .strong, .emphasis, .strikethrough, .highlight, .code, .link, .linkText, .url: false
        }
    }
}
