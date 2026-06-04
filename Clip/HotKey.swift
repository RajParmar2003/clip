import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon RegisterEventHotKey — works on every macOS version,
/// requires no Accessibility permission, and fires even when the app is inactive.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void
    private static var counter: UInt32 = 0

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        HotKey.counter += 1
        var hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: HotKey.counter) // 'CLIP'

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                let instance = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                if hkID.id == instance.registeredID {
                    DispatchQueue.main.async { instance.handler() }
                }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler
        )
        guard installStatus == noErr else { return nil }

        registeredID = hotKeyID.id
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            // deinit will remove the event handler; don't remove twice.
            return nil
        }
    }

    private var registeredID: UInt32 = 0

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

/// Helpers for displaying and recording hotkeys.
enum KeyCodeHelper {
    static func description(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        parts += keyName(for: keyCode)
        return parts
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func keyName(for keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            36: "⏎", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let name = special[keyCode] { return name }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue() as Data

        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        var deadKeyState: UInt32 = 0
        let status = layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> OSStatus in
            let layout = ptr.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(1 << kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &actualLength, &chars)
        }
        guard status == noErr, actualLength > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: actualLength).uppercased()
    }
}
