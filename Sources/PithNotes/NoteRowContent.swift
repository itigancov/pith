import Foundation

/// What a row of Search shows for a Note: its title and a second line, with where the query is in each.
/// Hits are UTF-16 ranges of `title` and `detail` themselves.
nonisolated public struct NoteRowContent: Sendable, Equatable {
    public var title: String
    public var titleHits: [Range<Int>]
    /// The preview of the next lines, or the snippet around the first match below the title.
    public var detail: String
    public var detailHits: [Range<Int>]

    /// Characters kept before the first match of a snippet.
    static let leadingContext = 20
    /// The longest second line made; the row cuts it at its width, this only bounds the work on a huge line.
    static let detailLimit = 240

    public init(text: String, query: SearchQuery) {
        // The same lines and the same title as `Note.title`.
        var lines: [String] = []
        var titleIndex: Int?
        for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                lines.append("")
                continue
            }
            if titleIndex == nil { titleIndex = index }
            lines.append(Note.withoutMarker(trimmed).trimmingCharacters(in: .whitespaces))
        }
        guard let titleIndex else {
            title = ""
            titleHits = []
            detail = ""
            detailHits = []
            return
        }
        title = lines[titleIndex]
        titleHits = query.ranges(in: title)

        let body = lines[(titleIndex + 1)...].filter { !$0.isEmpty }
        if let line = body.first(where: { !query.ranges(in: $0).isEmpty }) {
            let (snippet, hits) = Self.snippet(of: line, query: query)
            detail = snippet
            detailHits = hits
        } else {
            detail = Self.preview(of: body)
            detailHits = []
        }
    }

    private static func preview(of lines: [String]) -> String {
        var result = ""
        for line in lines {
            if !result.isEmpty { result += " · " }
            result += line
            if result.utf16.count >= detailLimit { break }
        }
        return result
    }

    /// The line from a word boundary near the first match; `…` replaces the start that was cut.
    private static func snippet(of line: String, query: SearchQuery) -> (String, [Range<Int>]) {
        let units = Array(line.utf16)
        let ranges = query.ranges(in: line)
        let first = ranges[0].lowerBound
        var start = 0
        if first > leadingContext {
            start = first
            var candidate = first - leadingContext
            // From `candidate` to the first word start: after a space, or the match itself.
            while candidate < first {
                if isSpace(units[candidate - 1]) {
                    start = candidate
                    break
                }
                candidate += 1
            }
        }
        var end = min(units.count, start + detailLimit)
        // Not in the middle of a surrogate pair.
        if end < units.count, UTF16.isTrailSurrogate(units[end]) { end -= 1 }
        let prefix = start > 0 ? "…" : ""
        let shift = prefix.utf16.count - start
        let text = prefix + String(decoding: units[start..<end], as: UTF16.self)
        let hits = ranges.compactMap { range -> Range<Int>? in
            guard range.upperBound <= end else { return nil }
            return range.lowerBound + shift..<range.upperBound + shift
        }
        return (text, hits)
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0
    }
}

/// The time of a row: the clock for today, "Yesterday", the date for this year, the date with the year for earlier ones.
nonisolated public enum RowTimeLabel {
    public static func string(for date: Date, now: Date, locale: Locale, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return format(date, locale: locale, calendar: calendar) { $0.timeStyle = .short; $0.dateStyle = .none }
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return yesterdayWord(locale: locale, calendar: calendar)
        }
        let template = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMd" : "yMMMd"
        return format(date, locale: locale, calendar: calendar) { $0.setLocalizedDateFormatFromTemplate(template) }
    }

    /// The time of a row of the Trash: "Deleted today, 10:42", "Deleted yesterday", "Deleted Nov 14", "Deleted Nov 14, 2025".
    public static func deleted(for date: Date, now: Date, locale: Locale, calendar: Calendar) -> String {
        let label = string(for: date, now: now, locale: locale, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return "Deleted today, \(label)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Deleted \(label.lowercased(with: locale))"
        }
        return "Deleted \(label)"
    }

    private static func format(_ date: Date, locale: Locale, calendar: Calendar, configure: (DateFormatter) -> Void) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        configure(formatter)
        return formatter.string(from: date)
    }

    /// "Yesterday" in the locale: the system's relative formatting, which counts from the real now, so it is asked
    /// about the real yesterday.
    private static func yesterdayWord(locale: Locale, calendar: Calendar) -> String {
        let real = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86_400)
        return format(real, locale: locale, calendar: calendar) { $0.dateStyle = .medium; $0.timeStyle = .none; $0.doesRelativeDateFormatting = true }
    }
}
