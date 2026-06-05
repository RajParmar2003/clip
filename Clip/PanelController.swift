import AppKit
import SwiftUI

/// Floating panel that appears at the mouse location on the active screen.
/// Uses NSPanel + .nonactivatingPanel so the previously-active app keeps focus
/// context, which is what makes "paste directly" work seamlessly.
final class PanelController: NSObject, NSWindowDelegate, ObservableObject {
    private var panel: NSPanel!
    private let store: ClipboardStore
    let queue: PasteQueue
    /// The app that was frontmost before the panel opened — paste target.
    private(set) var previousApp: NSRunningApplication?
    /// Bumped on every show() so the SwiftUI view resets search/selection/focus
    /// (onAppear only fires once because orderOut doesn't tear the view down).
    @Published private(set) var showGeneration = 0

    init(store: ClipboardStore, queue: PasteQueue) {
        self.store = store
        self.queue = queue
        super.init()
        buildPanel()
    }

    /// Paste with a text transform applied on the fly.
    func selectTransformed(_ item: ClipboardItem, transform: TextTransform) {
        store.copyTransformed(item, transform: transform)
        hide()
        guard Preferences.shared.pasteDirectly else { return }
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendCmdV()
        }
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self

        let root = HistoryPanelView(store: store, controller: self, queue: queue)
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        // Position near the mouse, clamped to the screen containing the cursor.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height + 24)
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
            origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        }
        panel.setFrameOrigin(origin)

        showGeneration += 1
        panel.makeKeyAndOrderFront(nil)
        // Activate so the search field receives keystrokes immediately.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Select an item: copy to pasteboard, hide, optionally send ⌘V to the previous app.
    func select(_ item: ClipboardItem, plainTextOnly: Bool) {
        store.copyToPasteboard(item, plainTextOnly: plainTextOnly)
        hide()

        guard Preferences.shared.pasteDirectly else { return }
        let target = previousApp
        // Re-activate the original app, then synthesize ⌘V after a short beat
        // so focus has settled. 120ms is the empirically reliable window.
        target?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendCmdV()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Click-away dismisses, like Spotlight.
        hide()
    }
}

/// Synthesizes ⌘V via CGEvent. Requires Accessibility permission (one-time prompt).
enum Paster {
    static func sendCmdV() {
        guard accessibilityGranted(promptIfNeeded: true) else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        // 9 = kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    static func accessibilityGranted(promptIfNeeded: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
