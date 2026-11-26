import Foundation
import Testing
@testable import PithApp

@MainActor final class FakeLoginService: LoginItemService {
    struct Refusal: Error {}
    var status: LoginItemStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openedSettings = 0

    init(status: LoginItemStatus = .notRegistered) { self.status = status }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        if status != .requiresApproval { status = .enabled }
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() { openedSettings += 1 }
}

struct LoginItemTests {
    private let downloads = InstallLocation.elsewhere(original: URL(fileURLWithPath: "/Users/someone/Downloads/Pith.app"))

    private func makeDefaults() -> UserDefaults {
        let name = "pith-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Row

    @Test func rowStateFollowsStatusAndPlace() {
        let cases: [(LoginItemStatus, InstallLocation, LoginItemRow.State)] = [
            (.enabled, .applications, .on),
            (.notRegistered, .applications, .off),
            (.notFound, .applications, .off),
            (.requiresApproval, .applications, .needsApproval),
            (.enabled, downloads, .outsideApplications),
            (.notRegistered, downloads, .outsideApplications),
            (.requiresApproval, .translocated(original: nil), .outsideApplications),
        ]
        for (status, location, state) in cases {
            for error in [false, true] {
                #expect(LoginItemRow.state(status: status, location: location, error: error).state == state)
            }
        }
    }

    @Test func rowSwitchAndCaption() {
        let on = LoginItemRow.state(status: .enabled, location: .applications, error: false)
        #expect(on.isOn && on.isEnabled && !on.showsApprovalButton)
        #expect(on.caption() == "Keeps the shortcut working after a restart")
        #expect(on.caption(plain: "So the shortcut always works") == "So the shortcut always works")

        let approval = LoginItemRow.state(status: .requiresApproval, location: .applications, error: false)
        #expect(!approval.isOn && approval.isEnabled && approval.showsApprovalButton)
        #expect(approval.caption() == "Pith is turned off in System Settings")

        let outside = LoginItemRow.state(status: .notRegistered, location: downloads, error: false)
        #expect(!outside.isOn && !outside.isEnabled && !outside.showsApprovalButton)
        #expect(outside.caption() == "Move Pith to Applications to turn this on")

        let failed = LoginItemRow.state(status: .notRegistered, location: .applications, error: true)
        #expect(!failed.isOn && failed.isEnabled)
        #expect(failed.caption() == "macOS didn’t allow it. Try again or check Login Items.")
    }

    // MARK: Switch

    @Test func turningOnRegistersAndKeepsTheWish() {
        let service = FakeLoginService()
        let defaults = makeDefaults()
        let item = LoginItem(service: service, location: .applications, defaults: defaults)
        item.setEnabled(true)
        #expect(service.registerCalls == 1)
        #expect(item.intent)
        #expect(item.row.isOn)
        #expect(defaults.bool(forKey: "OpenAtLogin"))
    }

    @Test func turningOffUnregistersAndDropsTheWish() {
        let service = FakeLoginService(status: .enabled)
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.intent = true
        item.setEnabled(false)
        #expect(service.unregisterCalls == 1)
        #expect(!item.intent)
        #expect(!item.row.isOn)
    }

    @Test func aRefusalShowsTheRealStatusAndTheError() {
        let service = FakeLoginService()
        service.registerError = FakeLoginService.Refusal()
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.setEnabled(true)
        #expect(item.row.failed)
        #expect(!item.row.isOn)
        #expect(!item.intent)
        // Pressed again, the error goes while the call runs.
        service.registerError = nil
        item.setEnabled(true)
        #expect(!item.row.failed)
        #expect(item.row.isOn)
    }

    @Test func anErrorStaysUntilClearedAndRefreshDoesNotClearIt() {
        let service = FakeLoginService(status: .enabled)
        service.unregisterError = FakeLoginService.Refusal()
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.setEnabled(false)
        #expect(item.row.failed)
        // The system still says enabled.
        #expect(item.row.isOn)
        item.refresh()
        #expect(item.row.failed)
        item.clearError()
        #expect(!item.row.failed)
    }

    @Test func outsideApplicationsNothingIsRegistered() {
        let service = FakeLoginService()
        let item = LoginItem(service: service, location: downloads, defaults: makeDefaults())
        item.setEnabled(true)
        #expect(service.registerCalls == 0)
        #expect(!item.intent)
    }

    // MARK: Refresh

    @Test func refreshReadsTheStatusAndLiftsTheWishWhenEnabled() {
        let service = FakeLoginService()
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        #expect(!item.intent)
        // The user enabled Pith in System Settings.
        service.status = .enabled
        item.refresh()
        #expect(item.row.isOn)
        #expect(item.intent)
    }

    @Test func refreshKeepsTheWishWhileApprovalIsNeeded() {
        let service = FakeLoginService(status: .enabled)
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.refresh()
        #expect(item.intent)
        service.status = .requiresApproval
        item.refresh()
        #expect(item.intent)
        #expect(item.row.state == .needsApproval)
        // Back from System Settings with Pith allowed.
        service.status = .enabled
        item.refresh()
        #expect(item.row.isOn)
    }

    @Test func openLoginItemsOpensSystemSettings() {
        let service = FakeLoginService(status: .requiresApproval)
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.openSystemSettings()
        #expect(service.openedSettings == 1)
    }

    // MARK: Launch

    @Test func launchRegistersAgainEvenWhenEnabled() {
        let service = FakeLoginService(status: .enabled)
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.intent = true
        item.restoreAtLaunch()
        #expect(service.registerCalls == 1)
    }

    @Test func launchRegistersWhenTheRecordIsLost() {
        let service = FakeLoginService(status: .notFound)
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.intent = true
        item.restoreAtLaunch()
        #expect(service.registerCalls == 1)
        #expect(item.row.isOn)
    }

    @Test func launchLeavesAloneWithoutTheWish() {
        let service = FakeLoginService()
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.restoreAtLaunch()
        #expect(service.registerCalls == 0)
    }

    @Test func launchLeavesAloneWhileApprovalIsNeeded() {
        let service = FakeLoginService(status: .requiresApproval)
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.intent = true
        item.restoreAtLaunch()
        #expect(service.registerCalls == 0)
        #expect(item.intent)
    }

    @Test func launchOutsideApplicationsNeverRegisters() {
        let service = FakeLoginService()
        let item = LoginItem(service: service, location: downloads, defaults: makeDefaults())
        item.intent = true
        item.restoreAtLaunch()
        #expect(service.registerCalls == 0)
    }

    @Test func aRefusalAtLaunchIsNotShown() {
        let service = FakeLoginService()
        service.registerError = FakeLoginService.Refusal()
        let item = LoginItem(service: service, location: .applications, defaults: makeDefaults())
        item.intent = true
        item.restoreAtLaunch()
        #expect(!item.row.failed)
    }
}
