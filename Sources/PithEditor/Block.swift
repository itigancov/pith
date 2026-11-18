import Foundation

/// Markup kind of a `Span` produced by the block scanner or the inline parser.
public enum SpanKind: Sendable, Equatable {
    // Block markup.
    case headingMarker
    case listMarker
    case taskCheckbox
    case quoteMarker
    case fence
    case fenceLanguage
    case codeContent

    // Inline elements: each covers its Markers too.
    case strong
    case emphasis
    case strikethrough
    case highlight
    case code
    case link
    /// Parts of a link between its Markers; `url` also marks a bare URL.
    case linkText
    case url
    /// Any Marker of an Inline: `**`, `` ` `` runs, `[`, `](`, `)`, an escaping `\`.
    case inlineMarker
}

/// A range of a Note's text (UTF-16) together with its markup kind.
public struct Span: Sendable, Equatable {
    public var range: NSRange
    public var kind: SpanKind

    public init(range: NSRange, kind: SpanKind) {
        self.range = range
        self.kind = kind
    }
}

public enum BlockKind: Sendable, Equatable {
    case paragraph
    case blank
    case heading(level: Int)
    case bullet(level: Int)
    case ordered(level: Int, number: Int)
    case task(level: Int, checked: Bool)
    case quote
    case codeBlock(language: String?)
}

/// A line-level unit of a Note; a code block is the only multi-line exception.
public struct Block: Sendable, Equatable {
    public var kind: BlockKind
    /// The block's line(s) without the trailing line break.
    public var range: NSRange
    /// Text after the Marker: the input for inline parsing. For a code block, the body between the fences.
    public var content: NSRange
    public var markers: [Span]

    public init(kind: BlockKind, range: NSRange, content: NSRange, markers: [Span] = []) {
        self.kind = kind
        self.range = range
        self.content = content
        self.markers = markers
    }
}

extension Block {
    /// The same Block moved by `delta` UTF-16 units, Markers included.
    func shifted(by delta: Int) -> Block {
        func move(_ range: NSRange) -> NSRange { NSRange(location: range.location + delta, length: range.length) }
        return Block(
            kind: kind,
            range: move(range),
            content: move(content),
            markers: markers.map { Span(range: move($0.range), kind: $0.kind) }
        )
    }
}
