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

private func plates(_ attributes: [NSAttributedString.Key: Any]) -> [PlateKind] {
    (attributes[.pithBackground] as? PlateStack)?.kinds ?? []
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
        #expect(base[.pithBackground] == nil)
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

    // MARK: Text size

    @Test func defaultSizeIs14AndMonoIsOneLess() {
        #expect(Theme().textSize == 14)
        #expect(Theme().monoSize == 13)
    }

    @Test func sizeSetsTheTextFontAndMonoIsOneLess() {
        let big = Theme(textSize: 17)
        let plain = big.attributes(for: big.style(block: .paragraph, spans: []))
        let code = big.attributes(for: big.style(block: .paragraph, spans: [.code]))
        #expect(font(plain) == NSFont.systemFont(ofSize: 17))
        #expect(font(code) == NSFont.monospacedSystemFont(ofSize: 16, weight: .regular))
        #expect(font(big.baseAttributes) == NSFont.systemFont(ofSize: 17))
    }

    @Test func sizeStaysBetween10And48() {
        #expect(Theme(textSize: 10).textSize == 10)
        #expect(Theme(textSize: 48).textSize == 48)
        #expect(Theme(textSize: 9).textSize == 10)
        #expect(Theme(textSize: 100).textSize == 48)
    }

    @Test func lineHeightMultipleDoesNotDependOnSize() throws {
        let paragraph = try #require(Theme(textSize: 30).baseAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(paragraph.lineHeightMultiple == 1.25)
    }

    @Test func inkIsTheBlueOfTheArtboardInBothAppearances() throws {
        func rgb(_ name: NSAppearance.Name) throws -> [Int] {
            var color: NSColor?
            try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance { color = Theme.ink.usingColorSpace(.sRGB) }
            let resolved = try #require(color)
            return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        #expect(try rgb(.aqua) == [0x3B, 0x5B, 0xDB])
        #expect(try rgb(.darkAqua) == [0x8D, 0xA2, 0xF5])
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

    @Test func highlightIsOnAHighlightPlate() {
        let highlight = attributes([.highlight])
        #expect(plates(highlight) == [.highlight])
        #expect(highlight[.foregroundColor] as? NSColor == NSColor.labelColor)
    }

    @Test func inlineCodeIsMono13OnAnInlineCodePlate() {
        let code = attributes([.code])
        #expect(font(code) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(plates(code) == [.inlineCode])
        #expect(code[.foregroundColor] as? NSColor == NSColor.labelColor)
    }

    @Test func codeContentIsMono13OnACodeBlockPlate() {
        let code = attributes([.codeContent], in: .codeBlock(language: nil))
        #expect(font(code) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(plates(code) == [.codeBlock])
        #expect(code[.foregroundColor] as? NSColor == NSColor.labelColor)
    }

    @Test func everythingInACodeBlockIsOnItsPlate() {
        let block = BlockKind.codeBlock(language: "swift")
        for spans in [[], [SpanKind.fence], [.fenceLanguage], [.codeContent]] {
            #expect(plates(attributes(spans, in: block)) == [.codeBlock], "\(spans)")
        }
    }

    @Test func codeInsideAHighlightIsOnAPlateOnTopOfTheHighlight() {
        #expect(plates(attributes([.highlight, .code])) == [.highlight, .inlineCode])
        #expect(plates(attributes([.highlight, .strong, .code, .inlineMarker])) == [.highlight, .inlineCode])
    }

    @Test func nothingGivesABackgroundColor() {
        let kinds: [SpanKind] = markerKinds + [.codeContent, .strong, .emphasis, .strikethrough, .highlight, .code, .link, .linkText, .url]
        for kind in kinds {
            #expect(attributes([kind])[.backgroundColor] == nil, "\(kind)")
            #expect(attributes([.highlight, kind])[.backgroundColor] == nil, "\(kind)")
            #expect(attributes([kind], in: .codeBlock(language: nil))[.backgroundColor] == nil, "\(kind)")
        }
    }

    @Test func platesKeepTheColorsOfTicket04() {
        #expect(theme.color(for: .highlight) == theme.highlightColor)
        #expect(theme.color(for: .inlineCode) == NSColor.quaternarySystemFill)
        #expect(theme.color(for: .codeBlock) == NSColor.quaternarySystemFill)
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
        #expect(plates(marker) == [])
    }

    @Test func markerDropsTheBoldItalicAndStrikethroughOfItsElement() {
        for outer in [SpanKind.strong, .emphasis, .strikethrough] {
            let marker = attributes([outer, .inlineMarker])
            #expect(font(marker) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
            #expect(marker[.strikethroughStyle] == nil)
        }
        #expect(font(attributes([.headingMarker], in: .heading(level: 1))) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    @Test func markerKeepsThePlateOfItsElement() {
        #expect(plates(attributes([.highlight, .inlineMarker])) == [.highlight])
        #expect(plates(attributes([.code, .inlineMarker])) == [.inlineCode])
        #expect(plates(attributes([.highlight, .strong, .inlineMarker])) == [.highlight])
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
        let blocks: [BlockKind] = [.blank, .bullet(level: 1), .ordered(level: 0, number: 2), .quote]
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
