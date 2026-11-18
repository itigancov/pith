import Foundation

/// Generates a big Note that mixes every supported Block and Inline kind, the same for the same seed.
/// Every code block in it is closed.
public enum NoteGenerator {
    /// A Note of exactly `lines` lines.
    public static func note(lines: Int, seed: UInt64) -> String {
        var generator = Generator(random: SplitMix64(seed: seed))
        var result: [String] = []
        while result.count < lines {
            // A section and the blank line after it; a section that does not fit gives way to paragraph lines.
            let section = generator.section() + [""]
            result += section.count <= lines - result.count ? section : [generator.sentence()]
        }
        return result.joined(separator: "\n")
    }
}

private struct Generator {
    var random: SplitMix64

    /// One of the templates, in rough proportions of a real Note.
    mutating func section() -> [String] {
        let templates: [(weight: Int, make: (inout Generator) -> [String])] = [
            (2, { $0.heading() }),
            (6, { $0.paragraph() }),
            (3, { $0.bulletList() }),
            (2, { $0.orderedList() }),
            (2, { $0.tasks() }),
            (1, { $0.quote() }),
            (1, { $0.codeBlock() }),
        ]
        var pick = int(templates.reduce(0) { $0 + $1.weight })
        for template in templates {
            if pick < template.weight { return template.make(&self) }
            pick -= template.weight
        }
        preconditionFailure("weights cover every pick")
    }

    mutating func heading() -> [String] {
        [String(repeating: "#", count: 1 + int(3)) + " " + sentence(words: 2...5)]
    }

    mutating func paragraph() -> [String] {
        (0...int(3)).map { _ in sentence() }
    }

    mutating func bulletList() -> [String] {
        list { generator, _ in ["-", "*", "+"][generator.int(3)] + " " }
    }

    mutating func orderedList() -> [String] {
        list { _, number in "\(number). " }
    }

    mutating func tasks() -> [String] {
        list { generator, _ in generator.int(2) == 0 ? "- [ ] " : "- [x] " }
    }

    /// 2–6 items, some of them one or two levels deeper than the item above; each level numbers from 1.
    private mutating func list(marker: (inout Generator, Int) -> String) -> [String] {
        var numbers = [0]
        return (0..<2 + int(5)).map { index in
            let level = numbers.count - 1
            if index > 0, level < 2, int(4) == 0 {
                numbers.append(0)
            } else if level > 0, int(3) == 0 {
                numbers.removeLast()
            }
            numbers[numbers.count - 1] += 1
            let indent = String(repeating: "  ", count: numbers.count - 1)
            return indent + marker(&self, numbers[numbers.count - 1]) + sentence()
        }
    }

    mutating func quote() -> [String] {
        (0...int(2)).map { _ in "> " + sentence() }
    }

    /// About 10 lines with its fences.
    mutating func codeBlock() -> [String] {
        let language = ["", "swift", "python", "sh"][int(4)]
        let body = (0..<6 + int(4)).map { index in
            ["let value\(index) = compute(**raw**, `x`)", "    return items.map { $0 * 2 }", "", "// https://example.com/\(index)"][int(4)]
        }
        return ["```" + language] + body + ["```"]
    }

    private static let words = [
        "note", "editor", "markdown", "quick", "line", "text", "idea", "draft", "list", "plan", "zettel",
        "заметка", "текст", "идея", "план", "строка", "быстро",
    ]

    private static let inlines = [
        "**bold**", "__bold__", "*italic*", "_italic_", "***bold italic***", "~~struck~~", "==highlight==",
        "`code`", "**bold `code`**", "**a *b* c**", "==mark **bold**==", "[link](https://example.com/page)",
        "[**bold** link](example.com)", "https://example.org/path?q=1", "snake_case_name", "a * b",
    ]

    /// Words with an Inline among every few of them.
    mutating func sentence(words count: ClosedRange<Int> = 6...18) -> String {
        let length = count.lowerBound + int(count.count)
        let parts = (0..<length).map { _ in
            int(5) == 0 ? Self.inlines[int(Self.inlines.count)] : Self.words[int(Self.words.count)]
        }
        return parts.joined(separator: " ")
    }

    /// A number in `0..<bound`.
    mutating func int(_ bound: Int) -> Int {
        Int(random.next() % UInt64(bound))
    }
}

/// A small, fast pseudo-random generator with a fixed sequence for a seed (Vigna's SplitMix64).
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
