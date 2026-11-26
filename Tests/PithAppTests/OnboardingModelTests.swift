import AppKit
import Carbon.HIToolbox
import Foundation
import PithNotes
import Testing
@testable import PithApp

/// The onboarding with only the edges of the system replaced: the login item service, a defaults suite, an in-memory
/// store, a Shortcut store with a fake registrar, and a log of what the model asked the window and the Panel to do.
@MainActor private final class Fixture {
    enum Call: Equatable { case closeWindow, openNote(UUID), showPanel }

    let suite = "PithOnboardingTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let service: FakeLoginService
    let loginItem: LoginItem
    let registrar = FakeRegistrar()
    let shortcuts: ShortcutStore
    let store: NoteStore?
    private(set) var calls: [Call] = []
    private(set) var model: OnboardingModel!

    init(
        status: LoginItemStatus = .notRegistered, location: InstallLocation = .applications, storeAvailable: Bool = true,
        configure: (FakeLoginService) -> Void = { _ in }
    ) throws {
        defaults = UserDefaults(suiteName: suite)!
        service = FakeLoginService(status: status)
        configure(service)
        loginItem = LoginItem(service: service, location: location, defaults: defaults)
        shortcuts = ShortcutStore(defaults: defaults, menuKeys: { [] }, systemShortcuts: { [] }, layout: StubLayout(), registrar: registrar)
        store = storeAvailable ? try NoteStore.open(at: .memory).store : nil
        model = OnboardingModel(
            defaults: defaults, loginItem: loginItem, shortcuts: shortcuts, store: { [store] in store },
            showPanel: { [unowned self] in calls.append(.showPanel) },
            openNote: { [unowned self] in calls.append(.openNote($0)) },
            closeWindow: { [unowned self] in calls.append(.closeWindow) }
        )
    }

    isolated deinit { defaults.removePersistentDomain(forName: suite) }

    var notes: [NoteSummary] { (try? store?.stack()) ?? [] }

    func welcomeNote() throws -> Note? {
        guard let id = notes.first?.id else { return nil }
        return try store?.note(id: id)
    }

    var done: Bool { defaults.bool(forKey: "OnboardingDone") }
}

private let defaultWelcome = """
# Welcome to Pith
A scratchpad over any app. Paste, tidy up, copy, get back to work.

- [ ] Press ⌥Space from any app to open Pith, Esc to hide it
- [ ] Press ⌘N for a new note, ⇧⌘[ and ⇧⌘] to page through
- [x] Read this note

## Markup stays visible
Type **bold** with ⌘B, ==highlight== with ⇧⌘U, `code` with ⇧⌘J.
- ⌘1 jumps to the latest note, ⌘F searches them all
- ⌘⌫ moves a note to the Trash, ⌘Z brings it back

> Change any shortcut in Settings, ⌘,

```text
Done with this note? ⌘⌫
```
"""

@MainActor struct OnboardingModelTests {
    // MARK: Whether it shows

    @Test func itShowsAtTheFirstLaunch() throws {
        let fixture = try Fixture()
        #expect(fixture.model.shouldShow(launchedAsLoginItem: false, fixture: false, surface: false))
    }

    @Test func itDoesNotShowOnceDone() throws {
        let fixture = try Fixture()
        fixture.defaults.set(true, forKey: "OnboardingDone")
        #expect(!fixture.model.shouldShow(launchedAsLoginItem: false, fixture: false, surface: false))
    }

    @Test(arguments: [(true, false, false), (false, true, false), (false, false, true)])
    func itDoesNotShowAtALoginLaunchWithAFixtureOrForASurface(login: Bool, fixture: Bool, surface: Bool) throws {
        let setup = try Fixture()
        #expect(!setup.model.shouldShow(launchedAsLoginItem: login, fixture: fixture, surface: surface))
    }

    // MARK: Steps

    @Test func itStartsOnTheHotkeyStepAndContinueAndBackMoveBetweenTheSteps() throws {
        let fixture = try Fixture()
        #expect(fixture.model.step == .hotkey)
        fixture.model.continue()
        #expect(fixture.model.step == .ready)
        fixture.model.back()
        #expect(fixture.model.step == .hotkey)
    }

    @Test func theSwitchIsOnByDefaultAndKeepsItsPlaceThroughBackAndContinue() throws {
        let fixture = try Fixture()
        #expect(fixture.model.openAtLogin)
        fixture.model.continue()
        fixture.model.openAtLogin = false
        fixture.model.back()
        fixture.model.continue()
        #expect(!fixture.model.openAtLogin)
        #expect(!fixture.model.switchIsOn)
    }

    @Test func theReadyStepReadsTheLoginItemStatusAgain() throws {
        let fixture = try Fixture()
        fixture.service.status = .requiresApproval
        #expect(fixture.loginItem.status == .notRegistered)
        fixture.model.continue()
        #expect(fixture.loginItem.status == .requiresApproval)
    }

    // MARK: Open Pith

    @Test func openPithWithTheSwitchOnRegistersTheLoginItemAndShowsThePanelOnTheWelcomeNote() throws {
        let fixture = try Fixture()
        fixture.model.continue()
        fixture.model.openPith()
        #expect(fixture.service.registerCalls == 1)
        #expect(fixture.done)
        #expect(fixture.notes.count == 1)
        let id = try #require(fixture.notes.first?.id)
        #expect(fixture.calls == [.openNote(id), .closeWindow, .showPanel])
    }

    @Test func openPithWithTheSwitchOffRegistersNothingAndFinishesTheSame() throws {
        let fixture = try Fixture()
        fixture.model.continue()
        fixture.model.openAtLogin = false
        fixture.model.openPith()
        #expect(fixture.service.registerCalls == 0)
        #expect(fixture.service.unregisterCalls == 0)
        #expect(fixture.done)
        #expect(fixture.notes.count == 1)
        #expect(fixture.calls.last == .showPanel)
    }

    @Test func openPithWithTheSwitchOffTakesAnEnabledLoginItemBack() throws {
        let fixture = try Fixture(status: .enabled)
        fixture.model.continue()
        fixture.model.openAtLogin = false
        fixture.model.openPith()
        #expect(fixture.service.unregisterCalls == 1)
        #expect(fixture.service.registerCalls == 0)
    }

    @Test func outsideApplicationsTheSwitchIsOffAndUnavailableAndNothingIsRegistered() throws {
        let downloads = InstallLocation.elsewhere(original: URL(fileURLWithPath: "/Users/someone/Downloads/Pith.app"))
        let fixture = try Fixture(location: downloads)
        fixture.model.continue()
        #expect(!fixture.model.switchIsAvailable)
        #expect(!fixture.model.switchIsOn)
        fixture.model.openPith()
        #expect(fixture.service.registerCalls == 0)
        #expect(fixture.service.unregisterCalls == 0)
        #expect(fixture.done)
        #expect(fixture.calls.last == .showPanel)
    }

    @Test func aFailedRegistrationDoesNotHoldTheOnboarding() throws {
        let fixture = try Fixture { $0.registerError = FakeLoginService.Refusal() }
        fixture.model.continue()
        fixture.model.openPith()
        #expect(fixture.service.registerCalls == 1)
        #expect(fixture.done)
        #expect(fixture.calls.last == .showPanel)
    }

    // MARK: Skipping

    @Test func skippingMarksItDonePutsTheNoteInAndShowsNoPanelAndRegistersNothing() throws {
        let fixture = try Fixture()
        fixture.model.skip()
        #expect(fixture.done)
        #expect(fixture.notes.count == 1)
        #expect(fixture.service.registerCalls == 0)
        #expect(!fixture.calls.contains(.showPanel))
        // The Note is the open one, so the Hotkey's first Panel shows it.
        let id = try #require(fixture.notes.first?.id)
        #expect(fixture.calls.contains(.openNote(id)))
        #expect(fixture.calls.contains(.closeWindow))
    }

    @Test func withoutAFinishTheFlagIsNotSet() throws {
        let fixture = try Fixture()
        fixture.model.continue()
        fixture.model.back()
        #expect(!fixture.done)
        #expect(fixture.notes.isEmpty)
        #expect(fixture.calls.isEmpty)
    }

    // MARK: The welcome Note

    @Test func theWelcomeNoteOnTheDefaultsIsTheArtboardsTextWithTheCursorAtTheEnd() throws {
        let fixture = try Fixture()
        fixture.model.skip()
        let note = try #require(try fixture.welcomeNote())
        #expect(note.text == defaultWelcome)
        let length = (defaultWelcome as NSString).length
        #expect(note.selection == NoteSelection(location: length, length: 0))
        #expect(note.scrollOffset == 0)
    }

    @Test func theWelcomeNoteShowsTheCurrentShortcutsAndKeepsTheFixedOnes() throws {
        let fixture = try Fixture()
        #expect(fixture.shortcuts.assign(Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.control, .option]), to: .hotkey) == nil)
        #expect(fixture.shortcuts.assign(Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: .command), to: .moveToTrash) == nil)
        fixture.model.skip()
        let text = try #require(try fixture.welcomeNote()).text
        #expect(text.contains("- [ ] Press ⌃⌥Space from any app to open Pith"))
        #expect(text.contains("- ⌘K moves a note to the Trash, ⌘Z brings it back"))
        #expect(text.contains("Done with this note? ⌘K\n```"))
        #expect(!text.contains("⌘⌫"))
        for fixed in ["**bold** with ⌘B", "==highlight== with ⇧⌘U", "`code` with ⇧⌘J", "⌘Z brings it back", "Settings, ⌘,"] {
            #expect(text.contains(fixed))
        }
        #expect(!text.contains("{"))
    }

    @Test(arguments: [false, true])
    func aStackOrTrashWithANoteGetsNoWelcomeNote(inTrash: Bool) throws {
        let fixture = try Fixture()
        let store = try #require(fixture.store)
        let mine = try store.insert(text: "Mine", selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)
        if inTrash { _ = try store.moveToTrash(ids: [mine.id]) }
        fixture.model.skip()
        #expect(try store.stack().count == (inTrash ? 0 : 1))
        #expect(try store.trashCount() == (inTrash ? 1 : 0))
        #expect(fixture.done)
    }

    @Test func finishingAgainDoesNotAddASecondWelcomeNote() throws {
        let fixture = try Fixture()
        fixture.model.skip()
        fixture.model.skip()
        fixture.model.openPith()
        #expect(fixture.notes.count == 1)
    }

    @Test func withoutAnOpenStoreFinishingWorksAndMakesNoNote() throws {
        let fixture = try Fixture(storeAvailable: false)
        fixture.model.continue()
        fixture.model.openPith()
        #expect(fixture.done)
        #expect(fixture.calls == [.closeWindow, .showPanel])
    }
}
