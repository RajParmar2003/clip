import SwiftUI

/// The popup UI: search field on top, keyboard-navigable history list below.
/// Keys: ↑/↓ move · ⏎ paste · ⌥⏎ paste plain · ⌘1–9 quick paste · ⌘P pin · ⌫ (empty search) delete · ⎋ close
struct HistoryPanelView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var controller: PanelController

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardItem] {
        let base = store.items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.copiedAt > rhs.copiedAt
        }
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter { fuzzyMatch(needle: q, haystack: $0.searchableText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 420, height: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { resetState() }
        .onChange(of: controller.showGeneration) { _ in resetState() }
        .onChange(of: query) { _ in selectedIndex = 0 }
        .background(KeyCaptureView(onKeyDown: handleKey))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history…", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { pasteSelected(plain: false) }
        }
        .padding(12)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item,
                                isSelected: index == selectedIndex,
                                shortcutNumber: index < 9 ? index + 1 : nil)
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
                                Divider()
                                Button("Delete", role: .destructive) { store.delete(item) }
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: selectedIndex) { newIndex in
                guard filtered.indices.contains(newIndex) else { return }
                proxy.scrollTo(filtered[newIndex].id, anchor: nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing copied yet" : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("⏎ paste", systemImage: "")
                .labelStyle(.titleOnly)
            Text("⌥⏎ plain")
            Text("⌘P pin")
            Spacer()
            Text("\(filtered.count) items")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

// MARK: - Row

private struct ItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let shortcutNumber: Int?

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let app = item.sourceAppName {
                        Text(app)
                    }
                    Text(item.copiedAt, style: .relative)
                    if let count = item.characterCount {
                        Text("\(count) chars")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let n = shortcutNumber {
                Text("⌘\(n)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
        case .image:
            if let img = item.nsImage() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
            }
        case .fileURLs:
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        }
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
