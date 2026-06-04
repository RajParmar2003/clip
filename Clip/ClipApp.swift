import SwiftUI

@main
struct ClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.clipboardStore)
        }
    }
}

/// Opens the SwiftUI Settings scene from AppKit code.
/// macOS 13: the `showSettingsWindow:` selector works.
/// macOS 14+: that selector is blocked ("Please use SettingsLink"); the supported
/// path is the `openSettings` environment action, which we reach by rendering a
/// throwaway hidden view that grabs it and fires immediately.
enum SettingsOpener {
    static func open() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
            openViaEnvironment()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    @available(macOS 14.0, *)
    private static func openViaEnvironment() {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OpenerView { window.close() })
        window.orderFrontRegardless()
    }

    @available(macOS 14.0, *)
    private struct OpenerView: View {
        @Environment(\.openSettings) private var openSettings
        let done: () -> Void

        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear {
                    openSettings()
                    DispatchQueue.main.async { done() }
                }
        }
    }
}

extension Notification.Name {
    static let clipOpenMainWindow = Notification.Name("clipOpenMainWindow")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let clipboardStore = ClipboardStore()
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var mainWindowController: MainWindowController!
    private let onboarding = OnboardingController()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clip")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        panelController = PanelController(store: clipboardStore)
        mainWindowController = MainWindowController(store: clipboardStore)
        clipboardStore.startMonitoring()
        registerHotKey()

        NotificationCenter.default.addObserver(
            self, selector: #selector(hotKeyPreferenceChanged),
            name: .clipHotKeyChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(openMainWindow),
            name: .clipOpenMainWindow, object: nil
        )

        onboarding.showIfNeeded()
    }

    @objc func openMainWindow() {
        panelController.hide()
        mainWindowController.show()
    }

    func registerHotKey() {
        hotKey = nil
        let prefs = Preferences.shared
        hotKey = HotKey(keyCode: prefs.hotKeyCode, modifiers: prefs.hotKeyModifiers) { [weak self] in
            self?.togglePanel()
        }
        if hotKey == nil {
            let alert = NSAlert()
            alert.messageText = "Couldn't register the shortcut"
            alert.informativeText = "\(prefs.hotKeyDescription) appears to be taken by another app or the system. Pick a different shortcut in Settings."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func hotKeyPreferenceChanged() {
        registerHotKey()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        panelController.toggle()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Clipboard History", action: #selector(menuShowPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Open Clip Window", action: #selector(openMainWindow), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Welcome Tour", action: #selector(menuShowOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Clear History", action: #selector(menuClearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clip", action: #selector(menuQuit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // restore left-click action handling
    }

    @objc private func menuShowPanel() { panelController.show() }

    @objc private func menuShowOnboarding() { onboarding.show() }

    @objc private func menuOpenSettings() {
        SettingsOpener.open()
    }

    @objc private func menuClearHistory() {
        clipboardStore.clearHistory(keepPinned: true)
    }

    @objc private func menuQuit() { NSApp.terminate(nil) }
}
