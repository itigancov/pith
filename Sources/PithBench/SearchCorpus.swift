import Foundation

/// A deterministic corpus for the search timings: Russian and English prose with ё and diacritics,
/// a few words that are rare and a few that are common.
enum SearchCorpus {
    static let rare = "quokka"
    static let frequent = "region"

    private static let english = [
        "region", "north", "winter", "garden", "morning", "coffee", "project", "meeting", "notes", "market",
        "river", "window", "story", "island", "letter", "season", "bridge", "engine", "pattern", "thought",
        "café", "naïve", "résumé", "crème", "jalapeño", "the", "and", "of", "with", "about", "from", "into",
    ]
    private static let russian = [
        "регион", "север", "зима", "сад", "утро", "кофе", "проект", "встреча", "заметки", "рынок",
        "река", "окно", "история", "остров", "письмо", "сезон", "мост", "двигатель", "узор", "мысль",
        "ёлка", "жёлтый", "всё", "ещё", "мой", "мои", "что", "как", "для", "про", "над", "под",
    ]

    /// `count` Notes of about 3.3 KB each, the same for every run.
    static func notes(count: Int) -> [String] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            // SplitMix64.
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((z ^ (z >> 31)) % UInt64(bound))
        }
        return (0..<count).map { index in
            var paragraphs: [String] = ["# " + english[next(english.count)].capitalized + " " + russian[next(russian.count)]]
            var length = 0
            while length < 3300 {
                let words = (0..<(8 + next(14))).map { _ in
                    next(2) == 0 ? english[next(english.count)] : russian[next(russian.count)]
                }
                var sentence = words.joined(separator: " ")
                sentence = sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
                if next(8) == 0 { sentence = "- " + sentence }
                if next(12) == 0 { sentence = "**" + sentence + "**" }
                paragraphs.append(sentence)
                length += sentence.utf8.count
            }
            // The rare word is in one Note of 400.
            if index % 400 == 7 { paragraphs.append(rare) }
            return paragraphs.joined(separator: "\n\n")
        }
    }
}
