import AppKit
import PithEditor
import PithNotes

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var noteScreen: NoteScreen?
    private var searchController: SearchController?
    private var trashController: TrashController?
    private var menus: AppMenus?
    private var statusItem: NSStatusItem?
    private let textSize = TextSizeModel(initial: AppDelegate.textSizeArgument())
    private let hotkeys = HotkeyCenter()
    private lazy var shortcuts = ShortcutStore(registrar: hotkeys)
    private var recorderWindow: RecorderTestWindow?
    private var settings: SettingsWindowController?
    private var appearance: AppearanceModel?
    private var loginItem: LoginItem?
    private var onboarding: OnboardingWindowController?
    private var onboardingModel: OnboardingModel?
    /// The system started Pith as a login item: it comes up quietly, without the Panel.
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The event that started the app is there only while the launch runs.
        launchedAsLoginItem = LaunchEvent.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `-PithAppearance light|dark` forces an appearance without storing it; without it the choice of Settings, else the system's.
        let appearance = AppearanceModel(
            initial: Appearance(argument: UserDefaults.standard.string(forKey: "PithAppearance")), apply: AppearanceModel.applyToApp
        )
        self.appearance = appearance

        // Where Pith is decides whether it can be a login item; after a new signature the system's record can be stale.
        let location = InstallLocation.current()
        let loginItem = LoginItemShot.requested?.makeLoginItem() ?? {
            let item = LoginItem(service: MainAppLoginItemService(), location: location)
            item.restoreAtLaunch()
            return item
        }()
        self.loginItem = loginItem

        // A fixture lives in memory; the open Note of the real defaults is not its to change.
        let screen = NoteScreen(
            openStore: makeStoreOpener(), scheduler: TaskScheduler(), textSize: textSize,
            defaults: UserDefaults.standard.string(forKey: "PithFixture") == nil ? .standard : nil
        )
        self.noteScreen = screen
        // `-PithLatest newest|last-edited` sets what ⌘1 jumps to, without storing it; Settings changes it either way.
        let latestMeans = LatestMeansModel(initial: UserDefaults.standard.string(forKey: "PithLatest").flatMap(Latest.init(rawValue:)))
        screen.latestMeans = { latestMeans.mode }

        let panel = PanelController(note: screen, fixedSize: windowSizeArgument())
        self.panelController = panel
        screen.alerts = panel
        let search = SearchController(stack: panel.screens, note: screen)
        search.isBlocked = { [weak panel] in panel?.panel.attachedSheet != nil }
        if let now = nowArgument() { search.now = { now } }
        self.searchController = search
        let trash = TrashController(stack: panel.screens, note: screen)
        trash.isBlocked = { [weak panel] in panel?.panel.attachedSheet != nil }
        trash.presentAlert = { [weak panel] alert, answer in panel?.enqueue(alert, handler: answer) }
        trash.presentFailure = { [weak panel] reason in panel?.presentSaveFailureAlert(reason: reason) }
        if let now = nowArgument() {
            trash.now = { now }
            screen.now = { now }
        }
        self.trashController = trash
        panel.onWillHide = { [weak screen] in screen?.flush() }
        let menus = AppMenus(shortcuts: shortcuts, panel: panel, note: screen, search: search, trash: trash, textSize: textSize)
        self.menus = menus
        panel.panel.onKeyEquivalent = { [weak menus] event in menus?.performKeyEquivalent(event) ?? false }
        let context = SettingsContext(
            shortcuts: shortcuts, textSize: textSize, appearance: appearance, latestMeans: latestMeans,
            trash: SettingsTrash(store: { [weak screen] in screen?.store }), loginItem: loginItem
        )
        let settings = SettingsWindowController(context: context)
        settings.hidePanel = { [weak panel] in panel?.hide() }
        settings.onTrashEmptied = { [weak panel] in (panel?.topScreen as? TrashScreen)?.refresh() }
        // A surface for a screenshot writes nothing to the real defaults: the onboarding's flag goes to a throwaway domain.
        let onboardingDefaults = Surface.requested == .window ? UserDefaults.standard : Self.throwawayDefaults()
        let onboardingModel = OnboardingModel(
            defaults: onboardingDefaults, loginItem: loginItem, shortcuts: shortcuts,
            store: { [weak screen] in screen?.store },
            showPanel: { [weak panel] in panel?.show() },
            openNote: { [weak screen] in screen?.openInserted(id: $0) },
            closeWindow: { [weak self] in self?.onboarding?.close() }
        )
        self.onboardingModel = onboardingModel
        let onboarding = OnboardingWindowController(model: onboardingModel)
        self.onboarding = onboarding
        panel.keepsAppVisible = { [weak settings, weak onboarding] in (settings?.isVisible ?? false) || (onboarding?.isVisible ?? false) }
        settings.keepsRegularPolicy = { [weak onboarding] in onboarding?.isVisible ?? false }
        onboarding.keepsRegularPolicy = { [weak settings] in settings?.isVisible ?? false }
        self.settings = settings
        menus.openSettings = { [weak settings] in settings?.show() }
        NSApp.mainMenu = menus.makeMainMenu()
        statusItem = menus.makeStatusItem()

        // The alerts of the load wait in the Panel until it shows.
        screen.load()
        openStackArgument(in: screen)

        // Before the Hotkey: it must not open the Panel behind the alert.
        offerMove(from: location)

        // While the onboarding is open the Hotkey brings it forward; the Panel stays out of its way.
        hotkeys.onPress = { [weak panel, weak onboarding] in
            if let onboarding, onboarding.isVisible { onboarding.bringForward() } else { panel?.toggle() }
        }
        // A Hotkey the system refuses is logged; the menu's Open Pith is the way in then.
        shortcuts.registerHotkey()

        // Every launch shows the Panel, as the Hotkey does, except the one of a login; the recorder window takes its place for `-PithShow recorder`.
        // The first launch shows the onboarding instead, and its Open Pith shows the Panel.
        if let tab = Surface.requested.settingsTab {
            settings.show(tab: tab, remembering: false)
        } else if Surface.requested == .recorder {
            let state = UserDefaults.standard.string(forKey: "PithRecorderState").flatMap(Self.recorderState)
            recorderWindow = RecorderTestWindow(store: shortcuts, size: windowSizeArgument(), state: state)
            recorderWindow?.show()
        } else if let step = Surface.requested.onboardingStep {
            onboardingModel.show(step: step)
            onboarding.show()
        } else if onboardingModel.shouldShow(
            launchedAsLoginItem: launchedAsLoginItem, fixture: UserDefaults.standard.string(forKey: "PithFixture") != nil, surface: Surface.requested != .window
        ) {
            onboarding.show()
        } else if !launchedAsLoginItem {
            panel.show()
        }

        // `-PithBigNote YES` starts on the generated Note, as Debug → Generate 5k Lines does.
        if UserDefaults.standard.bool(forKey: "PithBigNote") { menus.generateBigNote(nil) }

        // `-PithSelection "<location> <length>"` starts with that selection in view, for screenshots of it.
        if UserDefaults.standard.string(forKey: "PithSelection") != nil { screen.scrollSelectionToVisible() }

        presentAlertArguments()

        showSurface(in: panel.panel, screen: screen)
    }

    /// "Move Pith to Applications?" before the Panel shows. A launch for development (a fixture, a surface for a screenshot)
    /// and a login launch do not ask.
    private func offerMove(from location: InstallLocation) {
        let defaults = UserDefaults.standard
        guard !launchedAsLoginItem, defaults.string(forKey: "PithFixture") == nil, Surface.requested == .window,
              MoveOffer.shouldAsk(location: location, suppressed: defaults.bool(forKey: MoveOffer.suppressedKey), isDebug: MoveOffer.isDebugBuild)
        else { return }
        MoveOffer(defaults: defaults).run(location: location)
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteScreen?.willTerminate()
    }

    /// `-PithNow <ISO 8601>` is "now" for the times of Search's rows, so that a screenshot shows "10:42" and "Yesterday".
    private func nowArgument() -> Date? {
        UserDefaults.standard.string(forKey: "PithNow").flatMap(Fixture.date(from:))
    }

    /// `-PithTextSize <n>` starts at that size instead of the stored one, and stores nothing.
    private static func textSizeArgument() -> Int? {
        let value = UserDefaults.standard.integer(forKey: "PithTextSize")
        return value == 0 ? nil : value
    }

    /// Where the notes are. With `-PithFixture <path>` it is an in-memory database holding one Note, that UTF-8 file's text
    /// with the selection of `-PithSelection "<location> <length>"`, or, for a `.json` file, the Notes in it (`Fixture`);
    /// nothing goes to disk. If the file cannot be read, the database is empty. Without the flag it is the real database in Application Support.
    private func makeStoreOpener() -> () throws -> (store: NoteStore, recovery: CorruptionRecovery?) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "PithFixture") else {
            return { try NoteStore.open(at: .file(NoteStore.defaultFileURL)) }
        }
        if path.hasSuffix(".json") {
            let entries: [Fixture.Entry]
            do {
                entries = try Fixture.parse(json: Data(contentsOf: URL(fileURLWithPath: path)))
            } catch {
                NSLog("Pith: cannot read fixture %@: %@", path, String(describing: error))
                return { try NoteStore.open(at: .memory) }
            }
            return { try Fixture.openStore(entries: entries) }
        }
        let text: String?
        do {
            text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        } catch {
            NSLog("Pith: cannot read fixture %@: %@", path, String(describing: error))
            text = nil
        }
        var selection = NoteSelection(location: 0, length: 0)
        if let numbers = defaults.string(forKey: "PithSelection")?.split(separator: " ").compactMap({ Int($0) }), numbers.count == 2 {
            selection = NoteSelection(location: numbers[0], length: numbers[1])
        }
        // `-PithStackSize N` fills the Stack with N short Notes, the fixture one of them, at the place `-PithStackIndex` says.
        let size = defaults.integer(forKey: "PithStackSize")
        let slot = Self.stackSlot(size: size)
        return {
            let opened = try NoteStore.open(at: .memory)
            guard size > 0 else {
                if let text { _ = try opened.store.insert(text: text, selection: selection, scrollOffset: 0) }
                return opened
            }
            for position in 1...size {
                if position == slot, let text {
                    _ = try opened.store.insert(text: text, selection: selection, scrollOffset: 0)
                } else {
                    _ = try opened.store.insert(text: "# Note \(position)\n\nA short Note to fill the Stack.", selection: NoteSelection(location: 0, length: 0), scrollOffset: 0)
                }
            }
            return opened
        }
    }

    /// The place of the fixture in a Stack of `size`: `-PithStackIndex <i>` from 1, the last one for `blank` or none.
    private static func stackSlot(size: Int) -> Int {
        let index = UserDefaults.standard.string(forKey: "PithStackIndex").flatMap { Int($0) }
        return min(max(index ?? size, 1), max(size, 1))
    }

    /// `-PithStackIndex <i>` opens the i-th Note of the Stack (from 1), `blank` opens a Blank; both with the footer lit.
    private func openStackArgument(in screen: NoteScreen) {
        guard let value = UserDefaults.standard.string(forKey: "PithStackIndex") else { return }
        if value == "blank" {
            screen.newNote()
        } else if let index = Int(value), screen.stack.ids.indices.contains(index - 1) {
            screen.show(noteID: screen.stack.ids[index - 1])
        }
    }

    /// `-PithWindowSize "<width> <height>"` sizes the Panel's content instead of its stored size, without saving it:
    /// screenshots at a fixed size. The Panel has no title bar, so its content is its whole frame.
    private func windowSizeArgument() -> CGSize? {
        guard let size = UserDefaults.standard.string(forKey: "PithWindowSize")?.split(separator: " ").compactMap({ Double($0) }),
              size.count == 2 else { return nil }
        return CGSize(width: size[0], height: size[1])
    }

    /// `-PithCorruptAlert <path>` shows the alert about a damaged notes file set aside at `path`.
    /// `-PithOpenFailureAlert <reason>` shows the alert about notes that did not open, with Try Again;
    /// `-PithOpenFailureAlert newerSchema` shows its variant for notes from a newer Pith, with Quit only.
    /// `-PithSaveFailureAlert <reason>` shows the alert about notes that could not be saved.
    private func presentAlertArguments() {
        guard let panel = panelController else { return }
        if let path = UserDefaults.standard.string(forKey: "PithCorruptAlert") {
            panel.presentCorruptionRecoveryAlert(movedFile: URL(fileURLWithPath: path))
        }
        if let reason = UserDefaults.standard.string(forKey: "PithOpenFailureAlert") {
            let canRetry = reason != "newerSchema"
            panel.presentOpenFailureAlert(reason: reason, canRetry: canRetry) {
                NSLog("Pith: Try Again pressed")
            }
        }
        if let reason = UserDefaults.standard.string(forKey: "PithSaveFailureAlert") {
            panel.presentSaveFailureAlert(reason: reason)
        }
    }

    /// What `-PithShow` opens for `make shots`. `window` opens nothing; a surface that adds a popup window sets `opensPopup`.
    private enum Surface: String {
        case window
        case contextMenu = "context-menu"
        /// The context menu on the misspelled word "tetsers": its corrections and Ignore Spelling on top.
        case contextMenuSpelling = "context-menu-spelling"
        /// The menu of the icon in the menu bar, open.
        case menuBar = "menu-bar"
        /// The size pill, held on screen.
        case textSize = "text-size"
        /// The sheet of the alert about notes that could not be saved.
        case saveFailure = "save-failure"
        /// The test window of the Shortcut recorder instead of the Panel.
        case recorder
        /// Search with an empty query, with the query "region" (two Notes), with the query "invoice" (none).
        case searchAll = "search-all"
        case searchResults = "search-results"
        case searchEmpty = "search-empty"
        /// Search with an empty query and rows 2 to 4 selected, the 4th active.
        case searchSelect = "search-select"
        /// The footer of the Stack lit, on a Note in the middle of the Stack, on a Blank, and on the Latest Note.
        case stack
        case stackNew = "stack-new"
        case jumpLatest = "jump-latest"
        /// The toast after ⌘⌫ on the open Note, held on screen.
        case deleteUndo = "delete-undo"
        /// The Trash, and over it the alert of Empty Trash and the alert of Delete permanently.
        case trash
        case trashConfirm = "trash-confirm"
        case trashDelete = "trash-delete"
        /// The Settings window instead of the Panel, on General and on Shortcuts.
        case settings
        case settingsShortcuts = "settings-shortcuts"
        /// Settings on General with the login item in the state `-PithLoginItemState` gives: needing approval, outside Applications.
        case settingsLoginApproval = "settings-login-approval"
        case settingsOutsideApplications = "settings-outside-applications"
        /// The alert "Move Pith to Applications?", which moves nothing here.
        case moveAlert = "move-alert"
        /// The onboarding on its steps, the second one also with Open at login unavailable (`-PithLoginItemState outside`).
        case onboardingHotkey = "onboarding-hotkey"
        case onboardingReady = "onboarding-ready"
        case onboardingReadyOutside = "onboarding-ready-outside"
        /// The Panel on the welcome Note, put into an empty database as finishing the onboarding does.
        case welcome

        /// The step of the onboarding window when that is the surface.
        var onboardingStep: OnboardingModel.Step? {
            switch self {
            case .onboardingHotkey: .hotkey
            case .onboardingReady, .onboardingReadyOutside: .ready
            default: nil
            }
        }

        /// The tab of the Settings window when that is the surface.
        var settingsTab: SettingsTab? {
            switch self {
            case .settings, .settingsLoginApproval, .settingsOutsideApplications: .general
            case .settingsShortcuts: .shortcuts
            default: nil
            }
        }

        var opensPopup: Bool { self == .contextMenu || self == .contextMenuSpelling || self == .menuBar }
        /// A sheet slides in, and Search or the Trash comes up after the window does; the window is captured only after they have.
        var opensSheet: Bool {
            switch self {
            case .saveFailure, .searchAll, .searchResults, .searchEmpty, .searchSelect, .deleteUndo, .trash, .trashConfirm, .trashDelete, .settings, .settingsShortcuts,
                 .settingsLoginApproval, .settingsOutsideApplications, .moveAlert, .onboardingHotkey, .onboardingReady, .onboardingReadyOutside, .welcome: true
            default: false
            }
        }

        static var requested: Surface {
            UserDefaults.standard.string(forKey: "PithShow").flatMap(Surface.init(rawValue:)) ?? .window
        }
    }

    /// `-PithRecorderState idle|recording|error` for the recorder window; `error` shows "Used by Bold".
    private static func recorderState(_ name: String) -> ShortcutRecorderModel.State? {
        switch name {
        case "idle": .idle
        case "recording": .recording(error: nil)
        case "error": .recording(error: Rejection.usedBy("Bold").message)
        default: nil
        }
    }

    /// The Settings window when it is the surface; it is on screen already.
    private func settingsShotWindow() -> NSWindow? {
        guard Surface.requested.settingsTab != nil else { return nil }
        return NSApp.windows.first { $0.windowNumber == settings?.windowNumber }
    }

    /// The onboarding window when it is the surface.
    private func onboardingShotWindow() -> NSWindow? {
        guard Surface.requested.onboardingStep != nil else { return nil }
        return NSApp.windows.first { $0.windowNumber == onboarding?.windowNumber }
    }

    /// A defaults domain that is emptied at every launch, for what a screenshot must not leave in the real one.
    private static func throwawayDefaults() -> UserDefaults {
        let domain = "io.github.itigancov.pith.shots"
        let defaults = UserDefaults(suiteName: domain) ?? .standard
        defaults.removePersistentDomain(forName: domain)
        return defaults
    }

    /// `-PithShow window|context-menu|context-menu-spelling|menu-bar|text-size|save-failure|recorder|stack|stack-new|jump-latest|search-all|search-results|
    /// search-empty|search-select|delete-undo|trash|trash-confirm|trash-delete|settings|settings-shortcuts|settings-login-approval|settings-outside-applications|move-alert|
    /// onboarding-hotkey|onboarding-ready|onboarding-ready-outside|welcome` opens that surface for `make shots`; `window` (the default) opens nothing. `-PithShots YES` reports the
    /// IDs of the app's visible windows on stdout once the surface is up.
    private func showSurface(in window: NSWindow, screen: NoteScreen) {
        let defaults = UserDefaults.standard
        let surface = Surface.requested
        let editor = screen.editor
        // The recorder window is the window to photograph there; the Panel stays hidden.
        let shotWindow = recorderWindow?.window ?? settingsShotWindow() ?? onboardingShotWindow() ?? window
        shotWindow.display()
        if defaults.bool(forKey: "PithShots") {
            // `popUp` blocks in its tracking loop, so the report is a timer that also fires there.
            let attempts = Counter()
            // The alert is the window to photograph there, not the Panel behind it.
            let panelNumber = surface == .moveAlert ? -1 : shotWindow.windowNumber
            let opensPopup = surface.opensPopup
            let opensSheet = surface.opensSheet
            let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
                attempts.value += 1
                let shots = Self.visibleShots(panel: panelNumber)
                // Wait until the surface is on screen; give up after 8 s and report what there is.
                let settled = !opensSheet || attempts.value >= 6
                guard attempts.value >= 32 || (settled && shots.contains { $0.role == "window" } && (!opensPopup || shots.contains { $0.role == "menu" })) else { return }
                timer.invalidate()
                for shot in shots { print("PithShot \(shot.role) \(shot.id)") }
                print("PithShot done")
                fflush(stdout)
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        // After the window is on screen: `popUp` started during launch can come up without anything on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            switch surface {
            case .contextMenu:
                // On the selection if there is one: a right click elsewhere moves it. Otherwise the middle of the visible text.
                var point = NSPoint(x: editor.visibleRect.midX, y: editor.visibleRect.midY)
                if editor.selectedRange().length > 0 { point = Self.point(of: editor.selectedRange(), in: editor, window: window) }
                Self.popUpContextMenu(of: editor, at: point, window: window)
            case .contextMenuSpelling:
                let word = (editor.string as NSString).range(of: "tetsers")
                // A point inside the word: the middle of its first letters, not the end of the line.
                let point = Self.point(of: NSRange(location: word.location, length: 1), in: editor, window: window)
                Self.popUpContextMenu(of: editor, at: point, window: window)
            case .menuBar:
                // Under the Panel's top edge, where the icon's menu would hang from the menu bar.
                self?.menus?.makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: window.frame.minX + 24, y: window.frame.maxY - 24), in: nil)
            case .textSize:
                screen.showSizeHUD(size: self?.textSize.size ?? TextSizeModel.defaultSize, autoHide: false)
            case .saveFailure:
                self?.panelController?.presentSaveFailureAlert(reason: "SQLite error 13: database or disk is full.")
            case .searchAll: self?.showSearch(query: "")
            case .searchResults: self?.showSearch(query: "region")
            case .searchEmpty: self?.showSearch(query: "invoice")
            case .searchSelect:
                self?.showSearch(query: "")
                // As after ⇧↓ twice from the second row, once the list has its size: the pill scrolls to the active row.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    (self?.panelController?.topScreen as? SearchScreen)?.selectRows(from: 1, to: 3)
                }
            case .window, .recorder, .settings, .settingsShortcuts, .settingsLoginApproval, .settingsOutsideApplications,
                 .onboardingHotkey, .onboardingReady, .onboardingReadyOutside: break
            case .welcome:
                // As finishing the onboarding does; the flag goes to the throwaway domain.
                self?.onboardingModel?.skip()
            case .moveAlert:
                // Modal: the shots are reported from a timer. Whatever the button, nothing is moved.
                NSApp.activate()
                _ = MoveOffer.makeAlert().runModal()
            case .deleteUndo:
                screen.moveToTrash()
                // The mouse on the toast holds it, so the shot finds it there.
                screen.toastHoverChanged(true)
            case .trash: self?.showTrash()
            case .trashConfirm: self?.showTrash()?.emptyTrash()
            case .trashDelete: self?.showTrash()?.deleteSelectedPermanently()
            case .stack, .stackNew, .jumpLatest:
                screen.activateFooter(pinned: true)
            }
        }
    }

    /// The middle of `range` in the editor's coordinates.
    private static func point(of range: NSRange, in editor: NSTextView, window: NSWindow) -> NSPoint {
        let onScreen = editor.firstRect(forCharacterRange: range, actualRange: nil)
        let inWindow = window.convertFromScreen(NSRect(x: onScreen.midX, y: onScreen.midY, width: 0, height: 0)).origin
        return editor.convert(inWindow, from: nil)
    }

    private static func popUpContextMenu(of editor: NSTextView, at point: NSPoint, window: NSWindow) {
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown, location: editor.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )
        if let event, let menu = editor.menu(for: event) {
            menu.popUp(positioning: nil, at: point, in: editor)
        }
    }

    @discardableResult
    private func showTrash() -> TrashScreen? {
        trashController?.showTrash(nil)
        return panelController?.topScreen as? TrashScreen
    }

    private func showSearch(query: String) {
        searchController?.find(nil)
        guard let search = panelController?.topScreen as? SearchScreen else { return }
        search.setQuery(query)
        // The caret after the text, as on the artboards, not the whole text selected.
        if let editor = search.field.currentEditor() { editor.selectedRange = NSRange(location: (query as NSString).length, length: 0) }
    }

    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    /// The visible windows of this process: the Panel is the window (its sheet shows in its capture), anything at the
    /// popup menu level or above is a menu (a menu sits on layer 101).
    private nonisolated static func visibleShots(panel: Int) -> [(role: String, id: Int)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let modalLayer = Int(CGWindowLevelForKey(.modalPanelWindow))
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? Int == pid,
                  let id = info[kCGWindowNumber as String] as? Int, let layer = info[kCGWindowLayer as String] as? Int else { return nil }
            // A modal alert is the window of its surface; it has no number to know beforehand.
            if id == panel || layer == modalLayer { return ("window", id) }
            return layer >= menuLayer ? ("menu", id) : nil
        }
    }
}
