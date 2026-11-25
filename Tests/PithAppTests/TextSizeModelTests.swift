import Foundation
import Testing
@testable import PithApp

struct TextSizeModelTests {
    private func makeDefaults() -> UserDefaults {
        let name = "pith-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsAt14() {
        #expect(TextSizeModel(defaults: makeDefaults()).size == 14)
    }

    @Test func biggerAndSmallerStepByOne() {
        let model = TextSizeModel(defaults: makeDefaults())
        model.bigger()
        model.bigger()
        #expect(model.size == 16)
        model.smaller()
        #expect(model.size == 15)
    }

    @Test func resetGoesBackTo14() {
        let model = TextSizeModel(defaults: makeDefaults())
        for _ in 0..<5 { model.bigger() }
        model.reset()
        #expect(model.size == 14)
    }

    @Test func sizeStopsAt10And48() {
        let model = TextSizeModel(defaults: makeDefaults())
        for _ in 0..<100 { model.smaller() }
        #expect(model.size == 10)
        for _ in 0..<100 { model.bigger() }
        #expect(model.size == 48)
    }

    @Test func sizeSurvivesARestart() {
        let defaults = makeDefaults()
        let model = TextSizeModel(defaults: defaults)
        model.bigger()
        model.bigger()
        model.bigger()
        #expect(TextSizeModel(defaults: defaults).size == 17)
    }

    @Test func aStoredSizeOutOfRangeIsClamped() {
        let defaults = makeDefaults()
        defaults.set(200, forKey: TextSizeModel.key)
        #expect(TextSizeModel(defaults: defaults).size == 48)
        defaults.set(1, forKey: TextSizeModel.key)
        #expect(TextSizeModel(defaults: defaults).size == 10)
    }

    @Test func aGivenInitialSizeWinsAndIsNotStored() {
        let defaults = makeDefaults()
        let model = TextSizeModel(defaults: defaults, initial: 17)
        #expect(model.size == 17)
        #expect(defaults.object(forKey: TextSizeModel.key) == nil)
    }

    @Test func observersHearEveryChange() async {
        let model = TextSizeModel(defaults: makeDefaults())
        var seen: [Int] = []
        let heard = AsyncStream<Int>.makeStream()
        observeChanges({ model.size }) { size in
            seen.append(size)
            heard.continuation.yield(size)
        }
        model.bigger()
        var iterator = heard.stream.makeAsyncIterator()
        _ = await iterator.next()
        model.bigger()
        _ = await iterator.next()
        #expect(seen == [15, 16])
    }
}
