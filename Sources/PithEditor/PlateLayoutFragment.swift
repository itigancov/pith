import AppKit

/// A rounded plate behind text, as `PlateLayoutFragment` draws it.
struct Plate: Equatable {
    var kind: PlateKind
    var frame: CGRect
    var roundsTop: Bool
    var roundsBottom: Bool

    /// An inline plate reaches this far past its first and last glyphs.
    static let inlineOutset: CGFloat = 2
    /// A code block plate reaches this far past the left and right edges of the text.
    static let codeBlockOutset: CGFloat = 6

    var cornerRadius: CGFloat {
        min(kind == .codeBlock ? 5 : 4, frame.height / 2, frame.width / 2)
    }

    func offsetBy(_ offset: CGPoint) -> Plate {
        var plate = self
        plate.frame = frame.offsetBy(dx: offset.x, dy: offset.y)
        return plate
    }

    /// The outline in flipped coordinates: `minY` is the top.
    var path: CGPath {
        let r = frame
        let top = roundsTop ? cornerRadius : 0
        let bottom = roundsBottom ? cornerRadius : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX + top, y: r.minY))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: top)
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: top)
        path.closeSubpath()
        return path
    }
}

/// Hands out a `PlateLayoutFragment` for each paragraph with plates, and the standard fragment for the rest.
final class PlateLayout: NSObject, NSTextLayoutManagerDelegate {
    let theme: Theme

    init(theme: Theme) {
        self.theme = theme
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.hasPlates else {
            return NSTextLayoutFragment(textElement: textElement, range: range)
        }
        return PlateLayoutFragment(textElement: paragraph, range: range, theme: theme)
    }
}

/// The layout of a paragraph whose text lies on plates: draws them, then the text over them.
///
/// An inline plate is as tall as the font of its text and reaches `Plate.inlineOutset` past its glyphs, one per line
/// it wraps onto. A code block plate covers the whole paragraph and reaches `Plate.codeBlockOutset` past the text on
/// both sides; the paragraphs of a block join into one plate, rounded at its top and bottom.
final class PlateLayoutFragment: NSTextLayoutFragment {
    let theme: Theme

    init(textElement: NSTextParagraph, range: NSTextRange?, theme: Theme) {
        self.theme = theme
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        self.theme = Theme()
        super.init(coder: coder)
    }

    /// The plates to draw, in this fragment's coordinates, outer before inner.
    var plates: [Plate] {
        guard let paragraph = textElement as? NSTextParagraph, state == .layoutAvailable else { return [] }
        // Drawing asks for the plates and for the rendering surface; computed once per layout.
        let key = PlatesKey(frame: layoutFragmentFrame, containerWidth: textLayoutManager?.textContainer?.size.width ?? 0)
        if let cached, cached.key == key { return cached.plates }
        let string = paragraph.attributedString
        let plates = (codeBlockPlate(string).map { [$0] } ?? []) + inlinePlates(string)
        cached = (key, plates)
        return plates
    }

    private struct PlatesKey: Equatable {
        var frame: CGRect
        var containerWidth: CGFloat
    }

    private var cached: (key: PlatesKey, plates: [Plate])?

    override func invalidateLayout() {
        cached = nil
        super.invalidateLayout()
    }

    override var renderingSurfaceBounds: CGRect {
        plates.reduce(super.renderingSurfaceBounds) { $0.union($1.frame) }
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let plates = self.plates
        if !plates.isEmpty {
            context.saveGState()
            for plate in plates {
                // Resolved in the current drawing appearance, which AppKit sets to the view's while it draws.
                context.setFillColor(theme.color(for: plate.kind).cgColor)
                context.addPath(plate.offsetBy(point).path)
                context.fillPath()
            }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }

    // MARK: Code block

    /// The paragraph's piece of a code block plate, if it is in one: the whole paragraph, padding included,
    /// across the text's width. Rounded on top where the character before the paragraph is off the plate,
    /// at the bottom where its last character is, or at the end of the Note.
    private func codeBlockPlate(_ string: NSAttributedString) -> Plate? {
        guard string.length > 0, string.plateKinds(at: 0).contains(.codeBlock),
              let container = textLayoutManager?.textContainer else { return nil }
        let left = container.lineFragmentPadding - Plate.codeBlockOutset
        let right = container.size.width - container.lineFragmentPadding + Plate.codeBlockOutset
        let endsOnPlate = string.plateKinds(at: string.length - 1).contains(.codeBlock)
        // The top padding is spacing before the paragraph, which layout drops at the start of the Note:
        // there the plate reaches up into the inset instead.
        let spacingBefore = (string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacingBefore ?? 0
        let top = min(0, (textLineFragments.first?.typographicBounds.minY ?? 0) - spacingBefore)
        // The last paragraph of a Note that ends with a line break also holds the empty line after it;
        // the plate covers that line only if the block runs on through the line break.
        var bottom = layoutFragmentFrame.height
        if !endsOnPlate, textLineFragments.count > 1, let last = textLineFragments.last, last.characterRange.length == 0 {
            bottom = last.typographicBounds.minY
        }
        let frame = CGRect(x: left - layoutFragmentFrame.minX, y: top, width: right - left, height: bottom - top)
        let (before, after) = neighbors()
        return Plate(
            kind: .codeBlock,
            frame: frame,
            roundsTop: !(before?.contains(.codeBlock) ?? false),
            roundsBottom: !endsOnPlate || after == nil
        )
    }

    /// The plates of the characters just before and just after the paragraph; `nil` at the start or end of the Note.
    private func neighbors() -> (before: [PlateKind]?, after: [PlateKind]?) {
        guard let storage = textLayoutManager?.textContentManager as? NSTextContentStorage,
              let note = storage.attributedString else { return (nil, nil) }
        let start = storage.offset(from: storage.documentRange.location, to: rangeInElement.location)
        let end = storage.offset(from: storage.documentRange.location, to: rangeInElement.endLocation)
        return (
            start > 0 ? note.plateKinds(at: start - 1) : nil,
            end < note.length ? note.plateKinds(at: end) : nil
        )
    }

    // MARK: Inline

    /// For each line, a plate per stretch of an inline kind on it, outer kinds first.
    private func inlinePlates(_ string: NSAttributedString) -> [Plate] {
        var plates: [(depth: Int, plate: Plate)] = []
        for line in textLineFragments {
            let lineRange = line.characterRange
            // Stretches still open on this line: kind -> (start, depth).
            var open: [PlateKind: (start: Int, depth: Int)] = [:]
            func close(_ kind: PlateKind, at end: Int) {
                guard let stretch = open.removeValue(forKey: kind),
                      let plate = inlinePlate(kind, NSRange(location: stretch.start, length: end - stretch.start), on: line, in: string)
                else { return }
                plates.append((stretch.depth, plate))
            }
            string.enumerateAttribute(.pithBackground, in: lineRange) { value, range, _ in
                let kinds = (value as? PlateStack)?.kinds.filter { $0 != .codeBlock } ?? []
                for kind in open.keys where !kinds.contains(kind) { close(kind, at: range.location) }
                for (depth, kind) in kinds.enumerated() where open[kind] == nil { open[kind] = (range.location, depth) }
            }
            for kind in open.keys { close(kind, at: lineRange.upperBound) }
        }
        return plates.sorted { $0.depth < $1.depth }.map(\.plate)
    }

    /// The plate of `range` on `line`, without the spaces and line break where the line wraps or ends;
    /// `nil` if nothing is left.
    private func inlinePlate(_ kind: PlateKind, _ range: NSRange, on line: NSTextLineFragment, in string: NSAttributedString) -> Plate? {
        let text = string.string as NSString
        var end = range.upperBound
        if end == line.characterRange.upperBound {
            while end > range.location, let scalar = UnicodeScalar(text.character(at: end - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) { end -= 1 }
        }
        guard end > range.location else { return nil }

        var ascender: CGFloat = 0
        var descender: CGFloat = 0
        string.enumerateAttribute(.font, in: NSRange(location: range.location, length: end - range.location)) { value, _, _ in
            guard let font = value as? NSFont else { return }
            ascender = max(ascender, font.ascender)
            descender = min(descender, font.descender)
        }
        let origin = line.typographicBounds.origin
        let baseline = origin.y + line.glyphOrigin.y
        let left = origin.x + line.locationForCharacter(at: range.location).x - Plate.inlineOutset
        let right = origin.x + line.locationForCharacter(at: end).x + Plate.inlineOutset
        // Half a point of air above the ascender and below the descender.
        let top = baseline - ascender - 0.5
        let bottom = baseline - descender + 0.5
        return Plate(kind: kind, frame: CGRect(x: left, y: top, width: right - left, height: bottom - top), roundsTop: true, roundsBottom: true)
    }
}

extension NSAttributedString {
    /// Whether any character lies on a plate.
    var hasPlates: Bool {
        var found = false
        enumerateAttribute(.pithBackground, in: NSRange(location: 0, length: length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }

    func plateKinds(at index: Int) -> [PlateKind] {
        (attribute(.pithBackground, at: index, effectiveRange: nil) as? PlateStack)?.kinds ?? []
    }
}
