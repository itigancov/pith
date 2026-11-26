import AppKit
import Foundation
import Testing
@testable import PithApp

struct MoveOfferTests {
    private let downloads = InstallLocation.elsewhere(original: URL(fileURLWithPath: "/Users/someone/Downloads/Pith.app"))

    @Test func theAlertShowsOnlyOutsideApplicationsInReleaseUnlessSuppressed() {
        #expect(MoveOffer.shouldAsk(location: downloads, suppressed: false, isDebug: false))
        #expect(MoveOffer.shouldAsk(location: .translocated(original: nil), suppressed: false, isDebug: false))
        #expect(!MoveOffer.shouldAsk(location: .applications, suppressed: false, isDebug: false))
        #expect(!MoveOffer.shouldAsk(location: downloads, suppressed: true, isDebug: false))
        #expect(!MoveOffer.shouldAsk(location: downloads, suppressed: false, isDebug: true))
    }

    @Test func theAlertsSayWhatTheySpecSays() {
        let alert = MoveOffer.makeAlert()
        #expect(alert.alertStyle == .informational)
        #expect(alert.messageText == "Move Pith to Applications?")
        #expect(alert.informativeText == "Pith can open at login only from the Applications folder.")
        #expect(alert.buttons.map(\.title) == ["Move", "Not Now"])
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
        #expect(alert.showsSuppressionButton)
        #expect(alert.suppressionButton?.title == "Don’t ask again")

        let failure = MoveOffer.makeFailureAlert()
        #expect(failure.alertStyle == .warning)
        #expect(failure.messageText == "Couldn’t move Pith")
        #expect(failure.informativeText == "Drag Pith to Applications yourself.")
        #expect(failure.buttons.map(\.title) == ["OK"])
    }
}
