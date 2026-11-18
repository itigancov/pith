import Foundation
@testable import PithEditor

/// Text with its selection marked inline: `|` is the caret, `«…»` a selection (`[` is taken by task checkboxes).
struct Marked: Equatable, CustomStringConvertible {
    let text: String
    let selection: NSRange

    init(_ marked: String) {
        var text = ""
        var start: Int?
        var end: Int?
        for character in marked {
            let here = text.utf16.count
            switch character {
            case "|": start = here; end = here
            case "«": start = here
            case "»": end = here
            default: text.append(character)
            }
        }
        self.text = text
        let location = start ?? text.utf16.count
        self.selection = NSRange(location: location, length: (end ?? location) - location)
    }

    init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }

    var description: String {
        let ns = text as NSString
        let before = ns.substring(to: selection.location)
        let inside = ns.substring(with: selection)
        let after = ns.substring(from: selection.upperBound)
        let shown = selection.length == 0 ? "\(before)|\(after)" : "\(before)«\(inside)»\(after)"
        return shown.debugDescription
    }
}

typealias Command = (String, NSRange) -> TextEdit?

/// Runs `command` on `before` and returns the marked result, or `nil` when the Command declines.
func run(_ command: Command, _ before: String) -> Marked? {
    let input = Marked(before)
    guard let edit = command(input.text, input.selection) else { return nil }
    return Marked(text: apply(edit, to: input.text), selection: edit.selection)
}

/// Applies the replacements from the last, so earlier ranges stay valid.
func apply(_ edit: TextEdit, to text: String) -> String {
    let result = NSMutableString(string: text)
    for replacement in edit.replacements.reversed() {
        result.replaceCharacters(in: replacement.range, with: replacement.string)
    }
    return result as String
}
