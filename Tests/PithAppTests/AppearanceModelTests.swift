import AppKit
import Foundation
import Testing
@testable import PithApp

struct AppearanceModelTests {
    private func makeDefaults() -> UserDefaults {
        let name = "pith-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToSystem() {
        let model = AppearanceModel(defaults: makeDefaults())
        #expect(model.appearance == .system)
        #expect(model.appearanceName == nil)
    }

    @Test func choiceSurvivesANewInstance() {
        let defaults = makeDefaults()
        AppearanceModel(defaults: defaults).appearance = .dark
        #expect(AppearanceModel(defaults: defaults).appearance == .dark)
        AppearanceModel(defaults: defaults).appearance = .light
        #expect(AppearanceModel(defaults: defaults).appearance == .light)
    }

    @Test func brokenStoredValueIsSystem() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: AppearanceModel.key)
        #expect(AppearanceModel(defaults: defaults).appearance == .system)
        defaults.set(3, forKey: AppearanceModel.key)
        #expect(AppearanceModel(defaults: defaults).appearance == .system)
    }

    @Test func appearanceNamesFollowTheChoice() {
        let model = AppearanceModel(defaults: makeDefaults())
        model.appearance = .light
        #expect(model.appearanceName == .aqua)
        model.appearance = .dark
        #expect(model.appearanceName == .darkAqua)
        model.appearance = .system
        #expect(model.appearanceName == nil)
    }

    @Test func aTemporaryValueReplacesTheStoredOneAndIsNotWritten() {
        let defaults = makeDefaults()
        defaults.set("light", forKey: AppearanceModel.key)
        let model = AppearanceModel(defaults: defaults, initial: .dark)
        #expect(model.appearance == .dark)
        #expect(defaults.string(forKey: AppearanceModel.key) == "light")
        model.appearance = .system
        #expect(defaults.string(forKey: AppearanceModel.key) == "light")
        #expect(AppearanceModel(defaults: defaults).appearance == .light)
    }

    @Test func changesAreAppliedToTheApp() {
        var applied: [NSAppearance.Name?] = []
        let model = AppearanceModel(defaults: makeDefaults(), apply: { applied.append($0) })
        model.appearance = .dark
        #expect(applied == [nil, .darkAqua])
    }

    @Test func launchArgumentNames() {
        #expect(Appearance(argument: "light") == .light)
        #expect(Appearance(argument: "dark") == .dark)
        #expect(Appearance(argument: "system") == nil)
        #expect(Appearance(argument: nil) == nil)
    }
}
