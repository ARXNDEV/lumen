import AppKit
import Carbon.HIToolbox

/// Registers the global ⌥Space hotkey using the Carbon hotkey API
/// (works without Accessibility permission).
final class HotkeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private let handlers: [UInt32: () -> Void]

    /// toggle = ⌥Space (open/close launcher)
    /// screenshot = ⌥⇧2 (silent screenshot → Ask AI)
    init(toggle: @escaping () -> Void, screenshot: @escaping () -> Void) {
        handlers = [1: toggle, 2: screenshot]

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                let id = hkID.id
                DispatchQueue.main.async { manager.handlers[id]?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        register(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), id: 1)
        register(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(optionKey | shiftKey), id: 2)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4D4E31), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        hotKeyRefs.append(ref)
    }

    deinit {
        for ref in hotKeyRefs where ref != nil {
            UnregisterEventHotKey(ref)
        }
    }
}
