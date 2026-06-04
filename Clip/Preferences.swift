import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement

extension Notification.Name {
    static let clipHotKeyChanged = Notification.Name("clipHotKeyChanged")
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let historyLimit = "historyLimit"
        static let pasteDirectly = "pasteDirectly"
        static let ignoreConcealed = "ignoreConcealed"
        static let captureImages = "captureImages"
        static let ignoredApps = "ignoredApps"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let maxItemLength = "maxItemLength"
        static let fetchLinkPreviews = "fetchLinkPreviews"
        static let hasOnboarded = "hasOnboarded"
    }

    private init() {
        defaults.register(defaults: [
            Keys.historyLimit: 500,
            Keys.pasteDirectly: true,
            Keys.ignoreConcealed: true,
            Keys.captureImages: true,
            Keys.ignoredApps: [String](),
            // Default hotkey: ⌘⇧V (kVK_ANSI_V = 9)
            Keys.hotKeyCode: 9,
            Keys.hotKeyModifiers: cmdKey | shiftKey,
            Keys.maxItemLength: 0, // 0 = unlimited
            // The single network-touching feature; privacy-first means opt-in.
            Keys.fetchLinkPreviews: false,
            Keys.hasOnboarded: false,
        ])
    }

    var fetchLinkPreviews: Bool {
        get { defaults.bool(forKey: Keys.fetchLinkPreviews) }
        set { defaults.set(newValue, forKey: Keys.fetchLinkPreviews); objectWillChange.send() }
    }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Keys.hasOnboarded) }
        set { defaults.set(newValue, forKey: Keys.hasOnboarded); objectWillChange.send() }
    }

    var historyLimit: Int {
        get { defaults.integer(forKey: Keys.historyLimit) }
        set { defaults.set(newValue, forKey: Keys.historyLimit); objectWillChange.send() }
    }

    /// true: selecting an item pastes it into the frontmost app. false: copies only.
    var pasteDirectly: Bool {
        get { defaults.bool(forKey: Keys.pasteDirectly) }
        set { defaults.set(newValue, forKey: Keys.pasteDirectly); objectWillChange.send() }
    }

    var ignoreConcealed: Bool {
        get { defaults.bool(forKey: Keys.ignoreConcealed) }
        set { defaults.set(newValue, forKey: Keys.ignoreConcealed); objectWillChange.send() }
    }

    var captureImages: Bool {
        get { defaults.bool(forKey: Keys.captureImages) }
        set { defaults.set(newValue, forKey: Keys.captureImages); objectWillChange.send() }
    }

    var maxItemLength: Int {
        get { defaults.integer(forKey: Keys.maxItemLength) }
        set { defaults.set(newValue, forKey: Keys.maxItemLength); objectWillChange.send() }
    }

    var ignoredApps: [String] {
        get { defaults.stringArray(forKey: Keys.ignoredApps) ?? [] }
        set { defaults.set(newValue, forKey: Keys.ignoredApps); objectWillChange.send() }
    }

    var hotKeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: Keys.hotKeyCode)) }
        set { defaults.set(Int(newValue), forKey: Keys.hotKeyCode); objectWillChange.send() }
    }

    var hotKeyModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: Keys.hotKeyModifiers)) }
        set { defaults.set(Int(newValue), forKey: Keys.hotKeyModifiers); objectWillChange.send() }
    }

    func setHotKey(code: UInt32, modifiers: UInt32) {
        hotKeyCode = code
        hotKeyModifiers = modifiers
        NotificationCenter.default.post(name: .clipHotKeyChanged, object: nil)
    }

    var hotKeyDescription: String {
        KeyCodeHelper.description(keyCode: hotKeyCode, carbonModifiers: hotKeyModifiers)
    }

    // MARK: - Launch at login (SMAppService, macOS 13+)

    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Clip: launch-at-login change failed: \(error)")
                }
                objectWillChange.send()
            }
        }
    }
}
