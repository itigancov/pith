import Foundation

/// Markup kind of a `Span` produced by the block scanner.
public enum SpanKind: Sendable, Equatable {
    case headingMarker
    case listMarker
    case taskCheckbox
    case quoteMarker
    case fence
    case fenceLanguage
    case codeContent
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
