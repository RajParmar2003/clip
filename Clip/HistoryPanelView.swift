import SwiftUI

/// The popup UI: search field on top, keyboard-navigable history list below.
/// Keys: ↑/↓ move · ⏎ paste · ⌥⏎ paste plain · ⌘1–9 quick paste · ⌘P pin · ⌫ (empty search) delete · ⎋ close
struct HistoryPanelView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var controller: PanelController
    @ObservedObject var queue: PasteQueue
    @ObservedObject var quickPaste: QuickPasteHotKeys

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var filter: ClipFilter = .all
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [ClipboardItem]
        if q.isEmpty {
            base = store.items.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.copiedAt > rhs.copiedAt
            }
        } else {
            // Full-history search through the engine (FTS). For very short
            // queries, blend in fuzzy matches from the working set so 1–2
            // character typing still feels instant and forgiving.
            var results = store.search(q)
            if q.count < 3 {
                let needle = q.lowercased()
                let seen = Set(results.map(\.id))
                results += store.items.filter {
                    !seen.contains($0.id) && fuzzyMatch(needle: needle, haystack: $0.searchableText.lowercased())
                }
            }
            base = results
        }
        return base.filter { filter.matches($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterPills
            if let now = store.currentClipboard {
                ClipboardNowStrip(summary: now) { store.clearSystemClipboard() }
            }
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 440, height: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.panelRadius))
        .onAppear { resetState() }
        .onChange(of: controller.showGeneration) { _ in resetState() }
        .onChange(of: query) { _ in selectedIndex = 0 }
        .onChange(of: filter) { _ in selectedIndex = 0 }
        .background(KeyCaptureView(onKeyDown: handleKey))
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            TextField("Search everything you've copied", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { pasteSelected(plain: false) }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var filterPills: some View {
        HStack(spacing: 7) {
            ForEach(ClipFilter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.shortName)
                        .font(.system(size: 13))
                        .foregroundStyle(filter == f ? Color(NSColor.windowBackgroundColor) : .secondary)
                        .padding(.horizontal, filter == f ? 13 : 6)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(filter == f ? Color.primary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.rowGap) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        ClipCard(item: item,
                                 category: store.categories.first { $0.id == item.categoryID },
                                 isSelected: index == selectedIndex,
                                 quickSlot: quickPaste.slot(for: item.id),
                                 isQueued: queue.contains(item))
                            .id(item.id)
                            .onTapGesture {
                                selectedIndex = index
                                pasteSelected(plain: NSEvent.modifierFlags.contains(.option))
                            }
                            .contextMenu {
                                Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(item) }
                                Button("Paste as Plain Text") {
                                    selectedIndex = index
                                    pasteSelected(plain: true)
                                }
                                if item.content.isText {
                                    Menu("Paste with Transform") {
                                        ForEach(TextTransform.allCases) { transform in
                                            Button(transform.rawValue) {
                                                controller.selectTransformed(item, transform: transform)
                                            }
                                        }
                                    }
                                }
                                Button(queue.contains(item) ? "Remove from Paste Queue" : "Add to Paste Queue") {
                                    queue.contains(item) ? queue.remove(item) : queue.enqueue(item)
                                }
                                Menu("Quick-Paste Shortcut") {
                                    ForEach(0..<9, id: \.self) { slot in
                                        Button {
                                            quickPaste.assign(slot: slot, itemID: item.id)
                                        } label: {
                                            if quickPaste.slot(for: item.id) == slot {
                                                Label("Control+Option+\(slot + 1)", systemImage: "checkmark")
                                            } else {
                                                Text("Control+Option+\(slot + 1)")
                                            }
                                        }
                                    }
                                    if let s = quickPaste.slot(for: item.id) {
                                        Divider()
                                        Button("Remove Shortcut") { quickPaste.assign(slot: s, itemID: nil) }
                                    }
                                }
                                if !store.categories.isEmpty {
                                    Menu("Add to Category") {
                                        ForEach(store.categories) { category in
                                            Button(category.name) { store.assign(item, to: category) }
                                        }
                                        if item.categoryID != nil {
                                            Divider()
                                            Button("Remove from Category") { store.assign(item, to: nil) }
                                        }
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) { store.delete(item) }
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { newIndex in
                guard filtered.indices.contains(newIndex) else { return }
                proxy.scrollTo(filtered[newIndex].id, anchor: nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: filter == .all ? "tray" : filter.systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing here yet" : "No matches")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            shortcutHint("return", "paste")
            shortcutHint("⌘P", "pin")
            Spacer()
            if !queue.isEmpty {
                Text("⌃⌘V next of \(queue.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
            }
            Text("\(filtered.count) clips")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Button {
                controller.hide()
                NotificationCenter.default.post(name: .clipOpenMainWindow, object: nil)
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Open Clip Window")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).foregroundStyle(.secondary)
            Text(label).foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
    }

    // MARK: - Keyboard

    /// Returns true if the key was handled (consumed).
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // esc
            controller.hide()
            return true
        case 125: // down
            if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
            return true
        case 126: // up
            if selectedIndex > 0 { selectedIndex -= 1 }
            return true
        case 36: // return
            pasteSelected(plain: flags.contains(.option))
            return true
        case 51: // delete
            // Guard against key auto-repeat: holding Backspace must never
            // machine-gun through history. One press, one (recoverable) delete.
            if event.isARepeat { return true }
            if query.isEmpty, filtered.indices.contains(selectedIndex) {
                store.delete(filtered[selectedIndex])
                if selectedIndex >= filtered.count - 1 { selectedIndex = max(0, filtered.count - 2) }
                return true
            }
            return false
        default:
            break
        }

        // ⌘P pin
        if flags == .command, event.charactersIgnoringModifiers == "p" {
            if filtered.indices.contains(selectedIndex) {
                store.togglePin(filtered[selectedIndex])
            }
            return true
        }

        // ⌘1–⌘9 quick paste
        if flags == .command,
           let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), (1...9).contains(digit),
           filtered.indices.contains(digit - 1) {
            selectedIndex = digit - 1
            pasteSelected(plain: false)
            return true
        }

        return false
    }

    private func pasteSelected(plain: Bool) {
        guard filtered.indices.contains(selectedIndex) else { return }
        controller.select(filtered[selectedIndex], plainTextOnly: plain)
    }

    private func resetState() {
        query = ""
        selectedIndex = 0
        // Slight delay so focus lands after the panel becomes key.
        DispatchQueue.main.async { searchFocused = true }
    }
}

// MARK: - Current clipboard strip

/// "What will ⌘V paste right now?" — the live answer, always visible.
struct ClipboardNowStrip: View {
    let summary: ClipboardSummary
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Now:")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Image(systemName: summary.systemImage)
                .font(.caption)
                .foregroundStyle(.blue)
            Text(summary.preview)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            if !summary.detail.isEmpty {
                Text(summary.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Clear the clipboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .help("This is what's on your clipboard right now")
    }
}

// MARK: - Key capture

/// Intercepts keyDown events for the panel window via a local event monitor,
/// letting arrow keys/⏎/⎋ work while the search field stays focused.
private struct KeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MonitorView)?.onKeyDown = onKeyDown
    }

    final class MonitorView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let handler = self.onKeyDown,
                          event.window === self.window else { return event }
                    return handler(event) ? nil : event
                }
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

// MARK: - Fuzzy match

/// Subsequence fuzzy match: all needle chars must appear in order in haystack.
func fuzzyMatch(needle: String, haystack: String) -> Bool {
    if needle.isEmpty { return true }
    var needleIdx = needle.startIndex
    for ch in haystack {
        if ch == needle[needleIdx] {
            needleIdx = needle.index(after: needleIdx)
            if needleIdx == needle.endIndex { return true }
        }
    }
    return false
}
