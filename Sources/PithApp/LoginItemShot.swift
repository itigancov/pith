import Foundation

/// `-PithLoginItemState on|off|approval|outside|error` for `make shots`: the row of Open at login in a state the machine is not
/// in. A fake login item stands in for the system's, so nothing is registered; the wish goes to a throwaway defaults domain.
enum LoginItemShot: String {
    case on, off, approval, outside, error

    /// The service that answers with the state and does nothing.
    private struct Service: LoginItemService {
        let status: LoginItemStatus
        func register() throws {}
        func unregister() throws {}
        func openSystemSettingsLoginItems() {}
    }

    static var requested: LoginItemShot? {
        UserDefaults.standard.string(forKey: "PithLoginItemState").flatMap(LoginItemShot.init(rawValue:))
    }

    func makeLoginItem() -> LoginItem {
        let domain = "io.github.itigancov.pith.shots"
        let defaults = UserDefaults(suiteName: domain) ?? .standard
        defaults.removePersistentDomain(forName: domain)
        let status: LoginItemStatus = switch self {
        case .on: .enabled
        case .off, .outside, .error: .notRegistered
        case .approval: .requiresApproval
        }
        let location: InstallLocation = self == .outside
            ? .elsewhere(original: URL(fileURLWithPath: "/Users/someone/Downloads/Pith.app")) : .applications
        return LoginItem(service: Service(status: status), location: location, defaults: defaults, failed: self == .error)
    }
}
