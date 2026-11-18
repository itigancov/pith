import Foundation

/// The result of a Command: minimal replacements in the original text's coordinates (UTF-16) and the selection after them.
public struct TextEdit: Sendable, Equatable {
    public struct Replacement: Sendable, Equatable {
        public var range: NSRange
        public var string: String

        public init(range: NSRange, string: String) {
            self.range = range
            self.string = string
        }

        /// Order of `replacements`: by location; an insertion before a replacement at the same location.
        static func precedes(_ a: Replacement, _ b: Replacement) -> Bool {
            (a.range.location, a.range.length) < (b.range.location, b.range.length)
        }
    }

    /// Never overlapping, ordered by location; an insertion comes before a replacement at the same location.
    /// Applied one by one from the last, each range is still valid in the original text.
    public var replacements: [Replacement]
    /// The selection in the text after all replacements.
    public var selection: NSRange

    public init(replacements: [Replacement], selection: NSRange) {
        self.replacements = replacements
        self.selection = selection
    }
}
