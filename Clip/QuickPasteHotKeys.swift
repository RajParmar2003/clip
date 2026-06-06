import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Per-clip global hotkeys: assign Control+Option+1…9 to specific clips so a
/// single chord pastes your address, signature, a token — from any app.
///
/// Assignments are slot → item-id, persisted in UserDefaults. The clip itself
/// lives in the database; if the clip is deleted, the slot empties on next
/// access. Pinning isn't required, but the Settings UI surfaces pinned items
/// first since those are the ones worth a permanent shortcut.
final class QuickPasteHotKeys: ObservableObject {
    static let slotCount = 9
    /// slot index (0-based) → assigned item id
    @Published private(set) var assignments: [Int: UUID] = [:]

    private var hotKeys: [HotKey?] = []
    private weak var store: ClipboardStore?
    private let defaultsKey = "quickPasteAssignments"

    init(store: ClipboardStore) {
        self.store = store
        load()
        registerAll()
    }

    func assignedItemID(slot: Int) -> UUID? { assignments[slot] }

    func slot(for itemID: UUID) -> Int? {
        assignments.first(where: { $0.value == itemID })?.key
    }

    func assign(slot: Int, itemID: UUID?) {
        // A clip can only hold one slot; clear any previous binding to it.
        if let itemID, let existing = self.slot(for: itemID) {
            assignments[existing] = nil
        }
        if let itemID {
            assignments[slot] = itemID
        } else {
            assignments[slot] = nil
        }
        save()
        registerAll()
    }

    /// Human-readable chord for slot n (Control+Option+digit).
    func chordDescription(slot: Int) -> String {
        "⌃⌥\(slot + 1)"
    }

    // MARK: - Registration

    private func registerAll() {
        hotKeys = []
        let digitKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1..9
        for slot in 0..<Self.slotCount {
            guard assignments[slot] != nil else { hotKeys.append(nil); continue }
            let hk = HotKey(keyCode: digitKeyCodes[slot],
                            modifiers: UInt32(controlKey | optionKey)) { [weak self] in
                self?.fire(slot: slot)
            }
            hotKeys.append(hk)
        }
    }

    private func fire(slot: Int) {
        guard let store, let id = assignments[slot] else { return }
        guard let item = store.item(withID: id) else {
            // Clip was deleted — free the slot.
            assignments[slot] = nil
            save()
            registerAll()
            NSSound.beep()
            return
        }
        store.copyToPasteboard(item, plainTextOnly: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.sendCmdV()
        }
    }

    // MARK: - Persistence

    private func save() {
        let dict = assignments.reduce(into: [String: String]()) { acc, pair in
            acc[String(pair.key)] = pair.value.uuidString
        }
        UserDefaults.standard.set(dict, forKey: defaultsKey)
        objectWillChange.send()
    }

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] else { return }
        for (k, v) in dict {
            if let slot = Int(k), let id = UUID(uuidString: v) {
                assignments[slot] = id
            }
        }
    }
}
