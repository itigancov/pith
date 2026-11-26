import AppKit
import Testing
@testable import PithApp

struct LaunchEventTests {
    private func openApplication(loginItem: Bool) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        if loginItem {
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }

    @Test func aLoginLaunchIsQuiet() {
        #expect(LaunchEvent.isLoginLaunch(openApplication(loginItem: true)))
    }

    @Test func anOrdinaryLaunchShowsThePanel() {
        #expect(!LaunchEvent.isLoginLaunch(openApplication(loginItem: false)))
        #expect(!LaunchEvent.isLoginLaunch(nil))
    }

    @Test func otherEventsAreNotLoginLaunches() {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        #expect(!LaunchEvent.isLoginLaunch(event))
    }
}
