import SwiftUI

enum ClipFilter: String, CaseIterable, Identifiable {
    case all = "All History"
    case pinned = "Pinned"
    case text = "Text"
    case links = "Links"
    case images = "Images"
    case files = "Files"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "clock"
        case .pinned: return "pin"
        case .text: return "text.alignleft"
        case .links: return "link"
        case .images: return "photo"
        case .files: return "doc"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return item.isPinned
        case .text: return item.content.isText && item.asURL == nil
        case .links: return item.asURL != nil
        case .images: if case .image = item.content { return true }; return false
        case .files: if case .fileURLs = item.content { return true }; return false
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var store: ClipboardStore
    let controller: MainWindowController

    @State private var query = ""
    @State private var filter: ClipFilter = .all
    @State private var showClearConfirm = false

    private var filtered: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            let base = store.items
                .filter { filter.matches($0) }
                .sorted { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                    return lhs.copiedAt > rhs.copiedAt
                }
            return Array(base.prefix(500))
        }
        // Full-history search via the engine, then apply the sidebar filter.
        return store.search(q).filter { filter.matches($0) }
    }

    var body: some View {
        NavigationSplitView {
            List(ClipFilter.allCases, selection: $filter) { f in
                Label(f.rawValue, systemImage: f.systemImage).tag(f)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
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
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(filter.rawValue.lowercased())…", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { item in
                    MainItemRow(
                        item: item,
                        onPaste: { controller.select(item, plainTextOnly: false) },
                        onPastePlain: { controller.select(item, plainTextOnly: true) },
                        onCopy: { controller.copyOnly(item) },
                        onPin: { store.togglePin(item) },
                        onDelete: { store.delete(item) }
                    )
                }
            }
            .padding(8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: filter.systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing here yet" : "No matches")
                .foregroundStyle(.secondary)
            if filter == .all && query.isEmpty {
                Text("Copy something anywhere — it will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear All (keeps pinned)") { showClearConfirm = true }
                .controlSize(.small)
                .confirmationDialog("Remove all unpinned items?",
                                    isPresented: $showClearConfirm) {
                    Button("Clear All", role: .destructive) {
                        store.clearHistory(keepPinned: true)
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Row with visible hover actions

private struct MainItemRow: View {
    let item: ClipboardItem
    let onPaste: () -> Void
    let onPastePlain: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let app = item.sourceAppName { Text(app) }
                    Text(item.copiedAt, style: .relative)
                    if let url = item.asURL, item.linkTitle != nil {
                        Text(url.host ?? "").lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if hovering {
                HStack(spacing: 4) {
                    rowButton("doc.on.clipboard", help: "Copy") { onCopy() }
                    rowButton(item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? "Unpin" : "Pin") { onPin() }
                    Menu {
                        Button("Paste") { onPaste() }
                        Button("Paste as Plain Text") { onPastePlain() }
                        Button("Copy") { onCopy() }
                        Divider()
                        Button(item.isPinned ? "Unpin" : "Pin") { onPin() }
                        if let url = item.asURL {
                            Button("Open in Browser") { NSWorkspace.shared.open(url) }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("More actions")
                }
            } else if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            NSEvent.modifierFlags.contains(.option) ? onPastePlain() : onPaste()
        }
        .help("Click to paste into the app you were using")
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder
    private var icon: some View {
        if let png = item.linkIconPNG, let img = NSImage(data: png) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            switch item.content {
            case .text:
                Image(systemName: item.asURL != nil ? "link" : "text.alignleft")
                    .foregroundStyle(.secondary)
            case .image:
                if let img = item.nsImage() {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "photo")
                }
            case .fileURLs:
                Image(systemName: "doc").foregroundStyle(.secondary)
            }
        }
    }
}
