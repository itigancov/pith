import AppKit
import Testing
@testable import PithEditor

private let theme = Theme()

/// Attributes of the style that `spans` (outer first) give inside a Block of `block`.
private func attributes(_ spans: [SpanKind], in block: BlockKind = .paragraph) -> [NSAttributedString.Key: Any] {
    theme.attributes(for: theme.style(block: block, spans: spans))
}

private func font(_ attributes: [NSAttributedString.Key: Any]) -> NSFont? {
    attributes[.font] as? NSFont
}

private func traits(_ attributes: [NSAttributedString.Key: Any]) -> NSFontDescriptor.SymbolicTraits {
    font(attributes)?.fontDescriptor.symbolicTraits ?? []
}

private let markerKinds: [SpanKind] = [
    .headingMarker, .listMarker, .taskCheckbox, .quoteMarker, .fence, .fenceLanguage, .inlineMarker,
]

// AppKit font lookups race off the main thread: a parallel `NSFont.systemFont` may return Helvetica 12.
@MainActor
struct ThemeTests {
    // MARK: Base

    @Test func baseTextIsSystemFont14WithLabelColor() {
        let base = theme.baseAttributes
        #expect(font(base) == NSFont.systemFont(ofSize: 14))
        #expect(base[.foregroundColor] as? NSColor == NSColor.labelColor)
        #expect(base[.backgroundColor] == nil)
        #expect(base[.strikethroughStyle] == nil)
    }

    @Test func baseParagraphHasLineHeightMultipleAndNoSpacingOrIndent() throws {
        let paragraph = try #require(theme.baseAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(paragraph.lineHeightMultiple == 1.25)
        #expect(paragraph.paragraphSpacing == 0)
        #expect(paragraph.headIndent == 0)
        #expect(paragraph.firstLineHeadIndent == 0)
    }

    @Test func plainParagraphTextHasBaseFontAndColor() {
        let plain = attributes([])
        #expect(font(plain) == NSFont.systemFont(ofSize: 14))
        #expect(plain[.foregroundColor] as? NSColor == NSColor.labelColor)
    }

    // MARK: Inline kinds

    @Test func strongIsBold() {
        #expect(theme.style(block: .paragraph, spans: [.strong]) == TextStyle(bold: true, color: .label))
        let strong = attributes([.strong])
        #expect(traits(strong).contains(.bold))
        #expect(!traits(strong).contains(.italic))
        #expect(font(strong)?.pointSize == 14)
    }

    @Test func emphasisIsItalic() {
        let emphasis = attributes([.emphasis])
        #expect(traits(emphasis).contains(.italic))
        #expect(!traits(emphasis).contains(.bold))
        #expect(font(emphasis)?.pointSize == 14)
    }

    @Test func emphasisInsideStrongIsBoldItalic() {
        // `***x***` and the inner part of `**a *b***`.
        #expect(traits(attributes([.emphasis, .strong])).isSuperset(of: [.bold, .italic]))
        #expect(traits(attributes([.strong, .emphasis])).isSuperset(of: [.bold, .italic]))
    }

    @Test func strikethroughIsStruckThrough() {
        let struck = attributes([.strikethrough])
        #expect(struck[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(traits(struck).isDisjoint(with: [.bold, .italic]))
    }

    @Test func highlightHasHighlightBackground() {
        let highlight = attributes([.highlight])
        #expect(highlight[.backgroundColor] as? NSColor == theme.highlightColor)
        #expect(highlight[.foregroundColor] as? NSColor == NSColor.labelColor)
    }

    @Test func codeIsMono13OnCodeBackground() {
        for kind in [SpanKind.code, .codeContent] {
            let code = attributes([kind], in: kind == .code ? .paragraph : .codeBlock(language: nil))
            #expect(font(code) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
            #expect(code[.backgroundColor] as? NSColor == NSColor.quaternarySystemFill)
            #expect(code[.foregroundColor] as? NSColor == NSColor.labelColor)
        }
    }

    @Test func urlIsLinkColoredWithoutLinkAttribute() {
        let url = attributes([.url])
        #expect(url[.foregroundColor] as? NSColor == NSColor.linkColor)
        #expect(url[.link] == nil)
        #expect(attributes([.link, .url])[.foregroundColor] as? NSColor == NSColor.linkColor)
    }

    @Test func linkAndLinkTextKeepTheTextColor() {
        #expect(theme.style(block: .paragraph, spans: [.link, .linkText]) == theme.style(block: .paragraph, spans: []))
    }

    @Test func codeInsideStrongIsMonoBold() {
        #expect(font(attributes([.strong, .code])) == NSFont.monospacedSystemFont(ofSize: 13, weight: .bold))
    }

    @Test func codeInsideEmphasisIsMonoItalic() {
        let code = attributes([.emphasis, .code])
        #expect(traits(code).isSuperset(of: [.monoSpace, .italic]))
        #expect(font(code)?.pointSize == 13)
    }

    // MARK: Markers

    @Test(arguments: markerKinds)
    func markerIsSecondaryMono13Regular(kind: SpanKind) {
        let marker = attributes([kind])
        #expect(font(marker) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(marker[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        #expect(marker[.backgroundColor] == nil)
    }

    @Test func markerDropsTheBoldItalicAndStrikethroughOfItsElement() {
        for outer in [SpanKind.strong, .emphasis, .strikethrough] {
            let marker = attributes([outer, .inlineMarker])
            #expect(font(marker) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
            #expect(marker[.strikethroughStyle] == nil)
        }
        #expect(font(attributes([.headingMarker], in: .heading(level: 1))) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    @Test func markerKeepsTheBackgroundOfItsElement() {
        #expect(attributes([.highlight, .inlineMarker])[.backgroundColor] as? NSColor == theme.highlightColor)
        #expect(attributes([.code, .inlineMarker])[.backgroundColor] as? NSColor == NSColor.quaternarySystemFill)
        #expect(attributes([.highlight, .strong, .inlineMarker])[.backgroundColor] as? NSColor == theme.highlightColor)
    }

    // MARK: Block context

    @Test func headingContentIsBoldAtTextSize() {
        for level in 1...3 {
            let heading = attributes([], in: .heading(level: level))
            #expect(font(heading) == NSFont.systemFont(ofSize: 14, weight: .bold))
        }
    }

    @Test func checkedTaskContentIsSecondaryWithoutStrikethrough() {
        let done = attributes([], in: .task(level: 0, checked: true))
        #expect(done[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
        #expect(done[.strikethroughStyle] == nil)
        #expect(attributes([], in: .task(level: 0, checked: false))[.foregroundColor] as? NSColor == NSColor.labelColor)
        #expect(attributes([.url], in: .task(level: 0, checked: true))[.foregroundColor] as? NSColor == NSColor.linkColor)
    }

    @Test func otherBlocksAddNothing() {
        let blocks: [BlockKind] = [.blank, .bullet(level: 1), .ordered(level: 0, number: 2), .quote, .codeBlock(language: "swift")]
        for block in blocks {
            #expect(theme.style(block: block, spans: []) == theme.style(block: .paragraph, spans: []))
        }
    }

    // MARK: Appearance

    @Test func highlightIsDynamicAndStrongerInDark() {
        let light = alpha(theme.highlightColor, in: .aqua)
        let dark = alpha(theme.highlightColor, in: .darkAqua)
        #expect(abs(light - 0.25) < 0.01)
        #expect(abs(dark - 0.35) < 0.01)
    }

    @Test func colorsResolveDifferentlyInLightAndDark() {
        for color in [NSColor.labelColor, .secondaryLabelColor, .quaternarySystemFill] {
            #expect(rgba(color, in: .aqua) != rgba(color, in: .darkAqua))
        }
    }

    private func rgba(_ color: NSColor, in name: NSAppearance.Name) -> [CGFloat] {
        var result: [CGFloat] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            result = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        }
        return result
    }

    private func alpha(_ color: NSColor, in name: NSAppearance.Name) -> CGFloat { rgba(color, in: name)[3] }
}
