import AppKit
import Combine

/// Sequential paste: queue clips, then press Control+Command+V in any app to
/// paste them one per press, in order. Unlimited (Pastebot caps at 25).
final class PasteQueue: ObservableObject {
    @Published private(set) var queued: [ClipboardItem] = []

    private weak var store: ClipboardStore?

    init(store: ClipboardStore) {
        self.store = store
    }

    var isEmpty: Bool { queued.isEmpty }
    var count: Int { queued.count }

    func enqueue(_ item: ClipboardItem) {
        guard !queued.contains(where: { $0.id == item.id }) else { return }
        queued.append(item)
    }

    func remove(_ item: ClipboardItem) {
        queued.removeAll { $0.id == item.id }
    }

    func clear() {
        queued.removeAll()
    }

    func contains(_ item: ClipboardItem) -> Bool {
        queued.contains { $0.id == item.id }
    }

    /// Pastes the next queued item into the frontmost app. Called from the
    /// global hotkey, so the target app already has focus — no activation
    /// dance needed, just load the pasteboard and synthesize Command+V.
    func pasteNext() {
        guard let store, !queued.isEmpty else {
            NSSound.beep()
            return
        }
        let item = queued.removeFirst()
        store.copyToPasteboard(item, plainTextOnly: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.sendCmdV()
        }
    }
}
