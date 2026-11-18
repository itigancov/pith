import Foundation

/// Clickable urls: the `url` Spans of links and bare URLs.
public enum Links {
    /// The `url` Span that holds the character at `index`, with the address it opens.
    /// `nil` outside a url, in code, or when the text makes no `URL`.
    public static func url(in text: String, at index: Int) -> (range: NSRange, url: URL)? {
        url(in: text, at: index, blocks: BlockScanner.scan(text))
    }

    /// `url(in:at:)` over the Blocks of `text`, already scanned.
    static func url(in text: String, at index: Int, blocks: [Block]) -> (range: NSRange, url: URL)? {
        guard let block = blocks.first(where: { NSLocationInRange(index, $0.content) }), !block.isCodeBlock else { return nil }
        guard let span = InlineParser.parse(text, in: block.content)
            .first(where: { $0.kind == .url && NSLocationInRange(index, $0.range) }),
            let url = address((text as NSString).substring(with: span.range))
        else { return nil }
        return (span.range, url)
    }

    /// What a plain press on a url does when the button goes up.
    public enum Gesture: Sendable, Equatable {
        case open
        /// Selects the whole url, to edit it.
        case select
        /// A standard drag selection.
        case drag
    }

    /// The shortest press that selects instead of opening.
    public static let longPress: TimeInterval = 0.35
    /// The farthest the pointer may move, in points, before the press becomes a drag.
    public static let dragDistance: CGFloat = 3

    /// A move past `dragDistance` drags, however long the press; a still press opens, or selects if it is long.
    public static func gesture(duration: TimeInterval, distance: CGFloat) -> Gesture {
        if distance > dragDistance { return .drag }
        return duration < longPress ? .open : .select
    }

    /// A url that starts with a scheme (RFC 3986: `[A-Za-z][A-Za-z0-9+.-]*:`) as is, any other over `https://`.
    private static func address(_ url: String) -> URL? {
        URL(string: url.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:/) == nil ? "https://" + url : url)
    }
}
