import AppKit
import Combine
import SwiftUI

/// Sequential paste, the predictable way: queueing items preloads the first
/// one onto the system clipboard, and every plain ⌘V the user presses pastes
/// it while Clip rotates the next item in behind the scenes. No synthesized
/// keystrokes, no extra shortcut to learn. A floating HUD shows what's next.
///
/// Copying anything new cancels the session — the user's intent changed.
final class PasteQueue: ObservableObject {
    @Published private(set) var queued: [ClipboardItem] = []
    @Published private(set) var sessionActive = false

    private weak var store: ClipboardStore?
    private var keyMonitor: Any?
    private var hud: QueueHUD?

    init(store: ClipboardStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            self, selector: #selector(externalCopyHappened),
            name: .clipExternalCopy, object: nil
        )
    }

    var isEmpty: Bool { queued.isEmpty }
    var count: Int { queued.count }
    var nextItem: ClipboardItem? { queued.first }

    func contains(_ item: ClipboardItem) -> Bool {
        queued.contains { $0.id == item.id }
    }

    // MARK: - Session

    func enqueue(_ item: ClipboardItem) {
        guard !queued.contains(where: { $0.id == item.id }) else { return }
        queued.append(item)
        if !sessionActive {
            startSession()
        }
        hudRefresh()
    }

    func remove(_ item: ClipboardItem) {
        let wasNext = queued.first?.id == item.id
        queued.removeAll { $0.id == item.id }
        if queued.isEmpty {
            endSession()
        } else if wasNext {
            loadNextOntoClipboard()
            hudRefresh()
        } else {
            hudRefresh()
        }
    }

    func clear() {
        queued.removeAll()
        endSession()
    }

    private func startSession() {
        sessionActive = true
        loadNextOntoClipboard()
        installKeyMonitor()
        showHUD()
    }

    private func endSession() {
        sessionActive = false
        queued.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        hud?.hide()
    }

    private func loadNextOntoClipboard() {
        guard let store, let next = queued.first else { return }
        store.copyToPasteboard(next, plainTextOnly: false)
    }

    /// Watches for the user's own ⌘V anywhere on the system (read-only —
    /// covered by the Accessibility permission Clip already has). When a
    /// paste happens, rotate the next item onto the clipboard.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 9, // kVK_ANSI_V
                  event.modifierFlags.intersection([.command, .control, .option])
                      == .command else { return }
            // Give the target app a beat to read the current pasteboard
            // before we swap in the next item.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.advance()
            }
        }
    }

    /// The item currently on the clipboard was just pasted — rotate.
    private func advance() {
        guard sessionActive, !queued.isEmpty else { return }
        queued.removeFirst()
        if queued.isEmpty {
            endSession()
        } else {
            loadNextOntoClipboard()
            hudRefresh()
        }
    }

    /// ⌃⌘V convenience trigger: synthesizes a plain ⌘V into the frontmost
    /// app; the key monitor sees it and advances, same as a physical paste.
    func pasteNext() {
        guard sessionActive, !queued.isEmpty else {
            NSSound.beep()
            return
        }
        Paster.sendCmdV()
    }

    @objc private func externalCopyHappened() {
        guard sessionActive else { return }
        endSession()
    }

    // MARK: - HUD

    private func showHUD() {
        if hud == nil { hud = QueueHUD(queue: self) }
        hud?.show()
    }

    private func hudRefresh() {
        objectWillChange.send()
    }
}

extension Notification.Name {
    /// Posted by ClipboardStore when a real (external) copy is captured.
    static let clipExternalCopy = Notification.Name("clipExternalCopy")
}

// MARK: - Floating HUD

/// Small non-activating panel pinned near the bottom of the screen while a
/// queue session is running: shows what the next ⌘V will paste.
final class QueueHUD {
    private var panel: NSPanel?
    private weak var queue: PasteQueue?

    init(queue: PasteQueue) {
        self.queue = queue
    }

    func show() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 44),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                backing: .buffered, defer: false
            )
            p.level = .statusBar
            p.isFloatingPanel = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.ignoresMouseEvents = false
            p.hidesOnDeactivate = false
            if let queue {
                p.contentView = NSHostingView(rootView: QueueHUDView(queue: queue))
            }
            panel = p
        }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.minY + 60))
    }
}

private struct QueueHUDView: View {
    @ObservedObject var queue: PasteQueue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(queue.nextItem.map { "Next paste: \($0.previewTitle.prefix(40))" } ?? "Queue finished")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("Press ⌘V to paste · \(queue.count) left · copying anything cancels")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Cancel") { queue.clear() }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .frame(width: 420)
    }
}
