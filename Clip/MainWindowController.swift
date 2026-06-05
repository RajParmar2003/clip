import AppKit
import SwiftUI

/// The full desktop window: sidebar filters, search, visible per-item actions.
/// This is the click-first entry point for people who never learn shortcuts.
final class MainWindowController: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?
    private let store: ClipboardStore
    let queue: PasteQueue
    /// App that was frontmost before this window took focus — the paste target.
    private(set) var previousApp: NSRunningApplication?

    init(store: ClipboardStore, queue: PasteQueue) {
        self.store = store
        self.queue = queue
        super.init()
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

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Clip"
            w.titlebarAppearsTransparent = true
            w.minSize = NSSize(width: 560, height: 360)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("ClipMainWindow")
            w.delegate = self
            w.contentView = NSHostingView(
                rootView: MainWindowView(store: store, controller: self, queue: queue)
            )
            window = w
        }

        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// One-click paste: copy item, hide window, paste into the previous app.
    func select(_ item: ClipboardItem, plainTextOnly: Bool) {
        store.copyToPasteboard(item, plainTextOnly: plainTextOnly)
        hide()

        guard Preferences.shared.pasteDirectly else { return }
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendCmdV()
        }
    }

    /// Copy without pasting or closing — for "I just want it on my clipboard".
    func copyOnly(_ item: ClipboardItem) {
        store.copyToPasteboard(item, plainTextOnly: false)
    }
}
