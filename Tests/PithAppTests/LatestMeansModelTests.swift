import Foundation
import PithNotes
import Testing
@testable import PithApp

struct LatestMeansModelTests {
    private func makeDefaults() -> UserDefaults {
        let name = "pith-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToNewest() {
        #expect(LatestMeansModel(defaults: makeDefaults()).mode == .newest)
    }

    @Test func choiceSurvivesANewInstanceUnderTheKeyOfTheNoteScreen() {
        let defaults = makeDefaults()
        LatestMeansModel(defaults: defaults).mode = .lastEdited
        #expect(defaults.string(forKey: NoteScreen.latestMeansKey) == "last-edited")
        #expect(LatestMeansModel(defaults: defaults).mode == .lastEdited)
    }

    @Test func brokenStoredValueIsNewest() {
        let defaults = makeDefaults()
        defaults.set("oldest", forKey: NoteScreen.latestMeansKey)
        #expect(LatestMeansModel(defaults: defaults).mode == .newest)
    }

    @Test func aTemporaryValueIsNotWritten() {
        let defaults = makeDefaults()
        let model = LatestMeansModel(defaults: defaults, initial: .lastEdited)
        #expect(model.mode == .lastEdited)
        model.mode = .newest
        #expect(defaults.string(forKey: NoteScreen.latestMeansKey) == nil)
    }

    @Test func restoreDefaultsOfTheShortcutsLeavesLatestMeans() {
        let defaults = makeDefaults()
        let model = LatestMeansModel(defaults: defaults)
        model.mode = .lastEdited
        let store = ShortcutStore(defaults: defaults, menuKeys: { [] }, systemShortcuts: { [] }, layout: StubLayout(), registrar: FakeRegistrar())
        store.restoreDefaults()
        #expect(LatestMeansModel(defaults: defaults).mode == .lastEdited)
    }
}
