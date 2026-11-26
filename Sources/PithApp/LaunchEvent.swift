import AppKit

/// How the system started Pith.
enum LaunchEvent {
    /// Whether `event` is the "open application" event of a login: the system started Pith as a login item, so no Panel shows.
    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
