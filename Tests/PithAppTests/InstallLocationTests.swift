import Foundation
import Testing
@testable import PithApp

struct InstallLocationTests {
    private let home = URL(fileURLWithPath: "/Users/someone")

    private func isIn(_ path: String) -> Bool {
        InstallLocation.isInApplications(URL(fileURLWithPath: path), home: home)
    }

    @Test func applicationsFoldersCount() {
        #expect(isIn("/Applications/Pith.app"))
        #expect(isIn("/Applications/Utilities/Pith.app"))
        #expect(isIn("/Users/someone/Applications/Pith.app"))
    }

    @Test func otherPlacesDoNot() {
        #expect(!isIn("/Users/someone/Downloads/Pith.app"))
        #expect(!isIn("/Applications.bak/Pith.app"))
        #expect(!isIn("/Volumes/Pith/Pith.app"))
        #expect(!isIn("/Users/someone/work/pith/.build/xcode/Build/Products/Release/Pith.app"))
        #expect(!isIn("/Applications"))
        #expect(!isIn("/Users/other/Applications/Pith.app"))
    }

    @Test func aLinkIntoApplicationsCounts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pith-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeHome = root.appending(path: "home")
        try FileManager.default.createDirectory(at: fakeHome.appending(path: "Applications"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "elsewhere"), withIntermediateDirectories: true)
        // A folder elsewhere that is a link to ~/Applications, and a link in ~/Applications to a folder elsewhere.
        try FileManager.default.createSymbolicLink(at: root.appending(path: "shortcut"), withDestinationURL: fakeHome.appending(path: "Applications"))
        try FileManager.default.createSymbolicLink(at: fakeHome.appending(path: "Applications/out"), withDestinationURL: root.appending(path: "elsewhere"))
        try FileManager.default.createDirectory(at: root.appending(path: "elsewhere/Pith.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeHome.appending(path: "Applications/Pith.app"), withIntermediateDirectories: true)
        #expect(InstallLocation.isInApplications(root.appending(path: "shortcut/Pith.app"), home: fakeHome))
        #expect(!InstallLocation.isInApplications(fakeHome.appending(path: "Applications/out/Pith.app"), home: fakeHome))
    }

    @Test func aBundleInApplicationsIsInApplications() {
        let location = InstallLocation.classify(bundleURL: URL(fileURLWithPath: "/Applications/Pith.app"), home: home) { _ in .notTranslocated }
        #expect(location == .applications)
    }

    @Test func aBundleInDownloadsIsElsewhere() {
        let url = URL(fileURLWithPath: "/Users/someone/Downloads/Pith.app")
        #expect(InstallLocation.classify(bundleURL: url, home: home) { _ in .notTranslocated } == .elsewhere(original: url))
    }

    @Test func aTranslocatedBundleIsJudgedByItsOriginal() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Pith.app")
        let downloads = URL(fileURLWithPath: "/Users/someone/Downloads/Pith.app")
        let location = InstallLocation.classify(bundleURL: translocated, home: home) { _ in .translocated(original: downloads) }
        #expect(location == .translocated(original: downloads))
        #expect(location.originalURL == downloads)
        // Translocated from Applications (a quarantined copy put there by hand) is in Applications.
        let applications = URL(fileURLWithPath: "/Applications/Pith.app")
        #expect(InstallLocation.classify(bundleURL: translocated, home: home) { _ in .translocated(original: applications) } == .applications)
    }

    @Test func withoutTheSystemsAnswerTheTranslocationPathGivesItAway() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Pith.app")
        #expect(InstallLocation.classify(bundleURL: translocated, home: home) { _ in .unknown } == .translocated(original: nil))
        #expect(InstallLocation.classify(bundleURL: translocated, home: home) { _ in .translocated(original: nil) } == .translocated(original: nil))
        let plain = URL(fileURLWithPath: "/Users/someone/Downloads/Pith.app")
        #expect(InstallLocation.classify(bundleURL: plain, home: home) { _ in .unknown } == .elsewhere(original: plain))
    }

    @Test func theSystemAnswersForARealPath() {
        // Not a translocated path; whatever the system says, it does not crash and is not "translocated".
        let answer = Translocation.ask(URL(fileURLWithPath: "/Applications/Safari.app"))
        #expect(answer != .translocated(original: nil))
    }
}
