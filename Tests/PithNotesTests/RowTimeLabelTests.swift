import Foundation
import Testing
@testable import PithNotes

@Suite struct RowTimeLabelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func label(_ date: String, now: String, locale: String = "en_GB") -> String {
        RowTimeLabel.string(for: self.date(date), now: self.date(now), locale: Locale(identifier: locale), calendar: calendar)
    }

    private let now = "2026-11-26T10:42:00Z"

    @Test func todayIsTheTime() {
        #expect(label("2026-11-26T09:15:00Z", now: now) == "09:15")
    }

    @Test func todayFollowsTheLocalesClock() {
        let american = label("2026-11-26T09:15:00Z", now: now, locale: "en_US")
        // Narrow no-break space or plain space before AM, depending on the system's data.
        #expect(american.replacingOccurrences(of: "\u{202F}", with: " ") == "9:15 AM")
    }

    @Test func yesterdayIsTheWord() {
        #expect(label("2026-11-25T18:00:00Z", now: now) == "Yesterday")
    }

    @Test func aMinuteEitherSideOfMidnight() {
        #expect(label("2026-11-26T00:00:00Z", now: "2026-11-26T00:00:30Z") == "00:00")
        #expect(label("2026-11-25T23:59:59Z", now: "2026-11-26T00:00:30Z") == "Yesterday")
    }

    @Test func thisYearIsMonthAndDay() {
        #expect(label("2026-11-17T12:00:00Z", now: now, locale: "en_US") == "Nov 17")
    }

    @Test func earlierIsMonthDayAndYear() {
        #expect(label("2025-11-17T12:00:00Z", now: now, locale: "en_US") == "Nov 17, 2025")
    }

    @Test func theDayBeforeYesterdayIsADate() {
        #expect(label("2026-11-24T12:00:00Z", now: now, locale: "en_US") == "Nov 24")
    }
}
