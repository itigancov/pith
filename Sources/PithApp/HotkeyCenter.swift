import AppKit
import Carbon.HIToolbox

/// Registers one global Hotkey with Carbon and calls `onPress` on the main actor when it is pressed.
/// Carbon needs no Accessibility or Input Monitoring permission.
final class HotkeyCenter {
    var onPress: () -> Void = {}

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// 'PITH'.
    private static let signature: OSType = 0x5049_5448

    /// Registers `hotkey` exclusively, so other apps with the same shortcut lose it; replaces an earlier registration.
    /// Failures are logged with their `OSStatus`.
    func register(_ hotkey: Hotkey) {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            Hotkey.carbonModifiers(hotkey.modifiers),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        guard status == noErr else {
            NSLog("Pith: cannot register the hotkey (keyCode %u, modifiers %lu): OSStatus %d",
                  hotkey.keyCode, hotkey.modifiers.rawValue, status)
            return
        }
        hotkeyRef = ref
    }

    /// Frees the shortcut for other apps.
    func unregister() {
        guard let hotkeyRef else { return }
        UnregisterEventHotKey(hotkeyRef)
        self.hotkeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyPressed,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr { NSLog("Pith: cannot install the hotkey handler: OSStatus %d", status) }
    }

    fileprivate func handle(_ id: EventHotKeyID) {
        guard id.signature == Self.signature else { return }
        onPress()
    }
}

/// Carbon delivers hotkey events on the main thread, through the application event target.
nonisolated private func hotkeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr else { return status }
    nonisolated(unsafe) let pointer = userData
    MainActor.assumeIsolated {
        Unmanaged<HotkeyCenter>.fromOpaque(pointer).takeUnretainedValue().handle(id)
    }
    return noErr
}
