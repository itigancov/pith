import Foundation
import Observation
import ServiceManagement

/// What the system says of Pith's login item (`SMAppService.Status`).
enum LoginItemStatus: Equatable {
    case notRegistered, enabled, requiresApproval, notFound
}

/// The system's login item, for `LoginItem` to work on; a fake stands in for it in tests and screenshots.
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

/// `SMAppService.mainApp`.
struct MainAppLoginItemService: LoginItemService {
    private var service: SMAppService { .mainApp }

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .notFound
        @unknown default: .notRegistered
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openSystemSettingsLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

/// What the Open at login row shows, from the real status and the place of the app.
struct LoginItemRow: Equatable {
    enum State: Equatable {
        case on, off
        /// The user turned Pith off in System Settings.
        case needsApproval
        /// Pith does not sit in Applications, so it cannot be a login item.
        case outsideApplications
    }

    static let defaultCaption = "Keeps the shortcut working after a restart"
    static let approvalCaption = "Pith is turned off in System Settings"
    static let outsideCaption = "Move Pith to Applications to turn this on"
    static let errorCaption = "macOS didn’t allow it. Try again or check Login Items."

    let state: State
    /// The last `register()` or `unregister()` failed: its caption replaces the one of the state.
    let failed: Bool

    /// The switch is on only while the system has the item enabled; outside Applications nothing else matters.
    static func state(status: LoginItemStatus, location: InstallLocation, error: Bool) -> LoginItemRow {
        let state: State
        if !location.isApplications {
            state = .outsideApplications
        } else {
            switch status {
            case .enabled: state = .on
            case .requiresApproval: state = .needsApproval
            case .notRegistered, .notFound: state = .off
            }
        }
        return LoginItemRow(state: state, failed: error)
    }

    var isOn: Bool { state == .on }
    var isEnabled: Bool { state != .outsideApplications }
    var showsApprovalButton: Bool { state == .needsApproval }

    /// `offCaption` is the one of the plain states; the onboarding has its own.
    func caption(plain offCaption: String = LoginItemRow.defaultCaption) -> String {
        if failed { return Self.errorCaption }
        switch state {
        case .on, .off: return offCaption
        case .needsApproval: return Self.approvalCaption
        case .outsideApplications: return Self.outsideCaption
        }
    }
}

/// Open at login: the user's wish, kept in `UserDefaults`, and the system's login item. Settings and the onboarding use the same one.
@Observable
final class LoginItem {
    static let intentKey = "OpenAtLogin"

    private(set) var status: LoginItemStatus
    /// The last `register()` or `unregister()` failed; the row says so until the window hides or the switch is pressed again.
    private(set) var failed: Bool
    let location: InstallLocation

    @ObservationIgnored private let service: LoginItemService
    @ObservationIgnored private let defaults: UserDefaults

    init(service: LoginItemService, location: InstallLocation, defaults: UserDefaults = .standard, failed: Bool = false) {
        self.service = service
        self.location = location
        self.defaults = defaults
        self.failed = failed
        status = service.status
    }

    /// Whether the user wants Pith to open at login; survives a new signature that loses the system's record.
    var intent: Bool {
        get { defaults.bool(forKey: Self.intentKey) }
        set { defaults.set(newValue, forKey: Self.intentKey) }
    }

    var row: LoginItemRow { .state(status: status, location: location, error: failed) }

    /// Reads the status again: the user may have changed it in System Settings.
    func refresh() {
        status = service.status
        if status == .enabled { intent = true }
    }

    /// The switch was turned on or off.
    func setEnabled(_ enabled: Bool) {
        guard location.isApplications else { return }
        failed = false
        do {
            if enabled {
                try service.register()
                intent = true
            } else {
                try service.unregister()
                intent = false
            }
        } catch {
            failed = true
            NSLog("Pith: login item %@ failed: %@", enabled ? "register" : "unregister", String(describing: error))
        }
        refresh()
    }

    /// At launch, from Applications, with the wish on: registers again, even when the system says enabled, because after a
    /// change of the ad-hoc signature the record can be stale. Not when the user turned Pith off in System Settings.
    /// A failure is only logged.
    func restoreAtLaunch() {
        refresh()
        guard intent, location.isApplications, status != .requiresApproval else { return }
        do {
            try service.register()
        } catch {
            NSLog("Pith: cannot register the login item at launch: %@", String(describing: error))
        }
        refresh()
    }

    /// The window of the row hides: an error is forgotten.
    func clearError() { failed = false }

    func openSystemSettings() { service.openSystemSettingsLoginItems() }
}
