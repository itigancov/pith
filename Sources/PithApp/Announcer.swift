import AppKit

/// What VoiceOver is told when nothing it has focused changed: the toast after ⌘⌫, the size pill, the place in the Stack, the
/// count of Search. One seam for them all, so that a test hears what a user without a screen would.
enum Announcer {
    struct Announcement: Equatable {
        var text: String
        var priority: NSAccessibilityPriorityLevel
    }

    /// Sends `text` to VoiceOver as an announcement of `element`; tests put their own in its place.
    static var post: (_ text: String, _ priority: NSAccessibilityPriorityLevel, _ element: Any) -> Void = { text, priority, element in
        NSAccessibility.post(
            element: element, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: priority.rawValue]
        )
    }

    /// `.high` for what the user did and waits for (the toast, the move through the Stack), `.medium` for what a pill
    /// reports about a state (the size, the selection, the count of Search): it does not cut off what is being said.
    static func announce(_ text: String, priority: NSAccessibilityPriorityLevel, on element: Any = NSApp as Any) {
        post(text, priority, element)
    }
}
