import Foundation
import Observation
import PithNotes

/// The onboarding of the first launch: whether it shows, its two steps, and what finishing it does. The window is a thin
/// layer over this.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Equatable { case hotkey, ready }

    static let doneKey = "OnboardingDone"

    private(set) var step = Step.hotkey
    /// What the user wants of Open at login. On by default; it is registered only by Open Pith, and only where it can work.
    var openAtLogin = true
    /// The onboarding finished (Open Pith or skipped) and its window is closing.
    private(set) var isFinished = false

    let loginItem: LoginItem
    let shortcuts: ShortcutStore
    /// The Hotkey as chips and as VoiceOver reads it; they follow every change of the Shortcuts.
    private(set) var hotkeyChips: [String]
    private(set) var hotkeySpoken: String

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: () -> NoteStore?
    @ObservationIgnored private let showPanel: () -> Void
    @ObservationIgnored private let openNote: (UUID) -> Void
    @ObservationIgnored private let closeWindow: () -> Void

    /// `store` is the notes, if they opened. `openNote` makes a Note just inserted the open one; `showPanel` shows the Panel.
    init(
        defaults: UserDefaults, loginItem: LoginItem, shortcuts: ShortcutStore, store: @escaping () -> NoteStore?,
        showPanel: @escaping () -> Void, openNote: @escaping (UUID) -> Void, closeWindow: @escaping () -> Void
    ) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.shortcuts = shortcuts
        self.store = store
        self.showPanel = showPanel
        self.openNote = openNote
        self.closeWindow = closeWindow
        hotkeyChips = shortcuts.chips(for: .hotkey)
        hotkeySpoken = shortcuts.spokenName(for: .hotkey)
        observer = NotificationCenter.default.addObserver(forName: .shortcutsDidChange, object: shortcuts, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHotkey() }
        }
    }

    private func refreshHotkey() {
        hotkeyChips = shortcuts.chips(for: .hotkey)
        hotkeySpoken = shortcuts.spokenName(for: .hotkey)
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Whether this launch shows the onboarding: not once it was finished, not at a login, not with a fixture or for a screenshot.
    func shouldShow(launchedAsLoginItem: Bool, fixture: Bool, surface: Bool) -> Bool {
        !defaults.bool(forKey: Self.doneKey) && !launchedAsLoginItem && !fixture && !surface
    }

    // MARK: Switch

    /// Where Pith sits decides whether it can be a login item at all.
    var switchIsAvailable: Bool { loginItem.row.isEnabled }

    /// What the switch shows: the wish, where it can be met.
    var switchIsOn: Bool { openAtLogin && switchIsAvailable }

    // MARK: Steps

    func `continue`() {
        step = .ready
        // The user may have changed the login item in System Settings meanwhile.
        loginItem.refresh()
    }

    func back() { step = .hotkey }

    /// Starts on `step`, for a screenshot of it.
    func show(step: Step) {
        self.step = step
        if step == .ready { loginItem.refresh() }
    }

    // MARK: Finishing

    /// Open Pith: the login item as the switch says, then the Panel on the welcome Note.
    func openPith() {
        if switchIsOn {
            loginItem.setEnabled(true)
        } else if switchIsAvailable, loginItem.status == .enabled {
            loginItem.setEnabled(false)
        }
        finish(showingPanel: true)
    }

    /// The red button or ⌘W: nothing is registered and no Panel shows.
    func skip() {
        finish(showingPanel: false)
    }

    private func finish(showingPanel: Bool) {
        isFinished = true
        defaults.set(true, forKey: Self.doneKey)
        if let id = insertWelcomeNote() { openNote(id) }
        closeWindow()
        if showingPanel { showPanel() }
    }

    /// The welcome Note goes in only when there is no Note in the Stack or in the Trash.
    private func insertWelcomeNote() -> UUID? {
        guard let store = store() else { return nil }
        do {
            guard try store.stack().isEmpty, try store.trashCount() == 0 else { return nil }
            let text = WelcomeNote.text { action in shortcuts.chips(for: action).joined() }
            let end = (text as NSString).length
            return try store.insert(text: text, selection: NoteSelection(location: end, length: 0), scrollOffset: 0).id
        } catch {
            NSLog("Pith: cannot put the welcome note in: %@", String(describing: error))
            return nil
        }
    }
}
