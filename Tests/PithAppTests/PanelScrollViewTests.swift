import AppKit
import Testing
@testable import PithApp

@MainActor
@Suite struct PanelScrollViewTests {
    @Test func staysOverlayWhenThePreferredStyleChanges() {
        let scrollView = PanelScrollView()
        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.hasVerticalScroller)
        #expect(!scrollView.hasHorizontalScroller)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.scrollerKnobStyle == .default)

        // As the system does it when a mouse is plugged in or the setting changes.
        scrollView.scrollerStyle = .legacy
        NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: NSScroller.self)
        #expect(scrollView.scrollerStyle == .overlay)
    }
}
