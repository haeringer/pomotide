import Carbon.HIToolbox

/// The global shortcut Shift-Option-Command-P.
///
/// Uses the Carbon hot key API, which works without Accessibility permission
/// because it only listens for this one key combination.
@MainActor
final class HotKey {
    static let displayName = "⇧⌥⌘P"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// The C callback cannot capture context, so the action lives here.
    private static var action: (@MainActor () -> Void)?

    /// Registers the shortcut. Returns false if another app already uses it.
    @discardableResult
    func register(action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        Self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { HotKey.action?() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x504F_4D4F), id: 1)  // "POMO"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(shiftKey | optionKey | cmdKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { unregister() }
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
