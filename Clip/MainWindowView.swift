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

enum SidebarSelection: Hashable {
    case filter(ClipFilter)
    case category(UUID)
    case trash
}

struct MainWindowView: View {
    @ObservedObject var store: ClipboardStore
    let controller: MainWindowController
    @ObservedObject var queue: PasteQueue

    @State private var query = ""
    @State private var selection: SidebarSelection = .filter(.all)
    @State private var showClearConfirm = false
    @State private var newCategorySheet = false
    @State private var editingItem: ClipboardItem?
    @State private var selectedIDs = Set<UUID>()
    @State private var multiSeparator = "\n"

    private var currentCategory: ClipCategory? {
        if case .category(let id) = selection {
            return store.categories.first { $0.id == id }
        }
        return nil
    }

    private var filtered: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selection {
        case .trash:
            let base = store.trashItems()
            guard !q.isEmpty else { return base }
            let needle = q.lowercased()
            return base.filter { fuzzyMatch(needle: needle, haystack: $0.searchableText.lowercased()) }
        case .category(let id):
            guard let category = store.categories.first(where: { $0.id == id }) else { return [] }
            let base = store.items(in: category)
            guard !q.isEmpty else { return base }
            return store.search(q).filter { $0.categoryID == category.id }
        case .filter(let filter):
            if q.isEmpty {
                let base = store.items
                    .filter { filter.matches($0) }
                    .sorted { lhs, rhs in
                        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                        return lhs.copiedAt > rhs.copiedAt
                    }
                return Array(base.prefix(500))
            }
            return store.search(q).filter { filter.matches($0) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(ClipFilter.allCases) { f in
                        Label(f.rawValue, systemImage: f.systemImage)
                            .tag(SidebarSelection.filter(f))
                    }
                }
                Section("Categories") {
                    ForEach(store.categories) { category in
                        HStack(spacing: 8) {
                            Circle().fill(category.color).frame(width: 9, height: 9)
                            Text(category.name)
                            if category.isCollecting {
                                Image(systemName: "record.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .help("Collecting: new copies are filed here")
                            }
                        }
                        .tag(SidebarSelection.category(category.id))
                        .contextMenu {
                            Button(category.isCollecting ? "Stop Collecting" : "Start Collecting") {
                                store.setCollecting(category, enabled: !category.isCollecting)
                            }
                            Divider()
                            Button("Delete Category", role: .destructive) {
                                if selection == .category(category.id) { selection = .filter(.all) }
                                store.deleteCategory(category)
                            }
                        }
                    }
                    Button {
                        newCategorySheet = true
                    } label: {
                        Label("New Category…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }
                Section {
                    Label(store.trashCount > 0 ? "Trash (\(store.trashCount))" : "Trash",
                          systemImage: "trash")
                        .tag(SidebarSelection.trash)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                searchBar
                if let now = store.currentClipboard {
                    ClipboardNowStrip(summary: now) { store.clearSystemClipboard() }
                }
                Divider()
                if filtered.isEmpty {
                    emptyState
                } else {
                    list
                }
                Divider()
                if selectedIDs.count > 1 {
                    multiSelectBar
                    Divider()
                }
                footer
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .sheet(isPresented: $newCategorySheet) {
            NewCategorySheet { name, colorHex in
                store.addCategory(name: name, colorHex: colorHex)
            }
        }
        .sheet(item: $editingItem) { item in
            QuickEditSheet(item: item) { newText in
                store.updateText(item, to: newText)
            }
        }
        .onChange(of: selection) { _ in selectedIDs.removeAll() }
    }

    private var searchTitle: String {
        if let category = currentCategory { return category.name.lowercased() }
        if case .filter(let f) = selection { return f.rawValue.lowercased() }
        return "history"
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(searchTitle)…", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { item in
                    if selection == .trash {
                        TrashItemRow(
                            item: item,
                            onRestore: { store.restore(item) },
                            onDeleteForever: { store.deleteForever(item) }
                        )
                    } else {
                    MainItemRow(
                        item: item,
                        categories: store.categories,
                        itemCategory: store.categories.first { $0.id == item.categoryID },
                        isMultiSelected: selectedIDs.contains(item.id),
                        isQueued: queue.contains(item),
                        onPaste: { controller.select(item, plainTextOnly: false) },
                        onPastePlain: { controller.select(item, plainTextOnly: true) },
                        onPasteTransformed: { controller.selectTransformed(item, transform: $0) },
                        onCopy: { controller.copyOnly(item) },
                        onPin: { store.togglePin(item) },
                        onDelete: { store.delete(item) },
                        onEdit: { editingItem = item },
                        onAssign: { store.assign(item, to: $0) },
                        onToggleQueue: {
                            if queue.contains(item) {
                                queue.remove(item)
                            } else {
                                queue.enqueue(item)
                            }
                        },
                        onToggleMultiSelect: {
                            if selectedIDs.contains(item.id) {
                                selectedIDs.remove(item.id)
                            } else {
                                selectedIDs.insert(item.id)
                            }
                        }
                    )
                    }
                }
            }
            .padding(8)
        }
    }

    private var multiSelectBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedIDs.count) selected")
                .font(.caption)
            Picker("Join with", selection: $multiSeparator) {
                Text("New line").tag("\n")
                Text("Space").tag(" ")
                Text("Tab").tag("\t")
                Text("Comma").tag(", ")
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 160)
            Button("Paste \(selectedIDs.count) Items") { pasteSelectedItems() }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            Spacer()
            Button("Clear Selection") { selectedIDs.removeAll() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Joins the selected text items (in list order) and pastes as one.
    private func pasteSelectedItems() {
        let chosen = filtered.filter { selectedIDs.contains($0.id) }
        let textParts: [String] = chosen.compactMap {
            if case .text(let s) = $0.content { return s }
            return nil
        }
        guard !textParts.isEmpty else { return }
        var combined = ClipboardItem(content: .text(textParts.joined(separator: multiSeparator)))
        combined.restoreIdentity(id: UUID(), copiedAt: Date(), isPinned: false)
        selectedIDs.removeAll()
        controller.select(combined, plainTextOnly: false)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: currentCategory != nil ? "folder" : "clock")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing here yet" : "No matches")
                .foregroundStyle(.secondary)
            if let category = currentCategory, query.isEmpty {
                Text("Right-click an item and choose \"Add to \(category.name)\" — or Start Collecting to file every new copy here automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
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
            if !queue.isEmpty {
                Divider().frame(height: 12)
                Label("\(queue.count) queued — ⌃⌘V pastes next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear Queue") { queue.clear() }
                    .controlSize(.mini)
            }
            Spacer()
            if selection == .trash {
                Text("Items are removed forever after 30 days")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Empty Trash", role: .destructive) { showClearConfirm = true }
                    .controlSize(.small)
                    .confirmationDialog("Permanently delete everything in the Trash?",
                                        isPresented: $showClearConfirm) {
                        Button("Empty Trash", role: .destructive) {
                            store.emptyTrash()
                        }
                    }
            } else {
                Button("Clear All (keeps pinned)") { showClearConfirm = true }
                    .controlSize(.small)
                    .confirmationDialog("Move all unpinned items to the Trash?",
                                        isPresented: $showClearConfirm) {
                        Button("Move to Trash", role: .destructive) {
                            store.clearHistory(keepPinned: true)
                        }
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
    let categories: [ClipCategory]
    let itemCategory: ClipCategory?
    let isMultiSelected: Bool
    let isQueued: Bool
    let onPaste: () -> Void
    let onPastePlain: () -> Void
    let onPasteTransformed: (TextTransform) -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onAssign: (ClipCategory?) -> Void
    let onToggleQueue: () -> Void
    let onToggleMultiSelect: () -> Void

    @State private var hovering = false

    private var isEditableText: Bool {
        if case .text = item.content { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let category = itemCategory {
                        HStack(spacing: 3) {
                            Circle().fill(category.color).frame(width: 6, height: 6)
                            Text(category.name)
                        }
                    }
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
                        transformMenu
                        Button("Copy") { onCopy() }
                        if isEditableText {
                            Button("Edit…") { onEdit() }
                        }
                        Divider()
                        Button(isQueued ? "Remove from Paste Queue" : "Add to Paste Queue") { onToggleQueue() }
                        Button(item.isPinned ? "Unpin" : "Pin") { onPin() }
                        categoryMenu
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
            } else {
                if isQueued {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .help("In the paste queue")
                }
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isMultiSelected ? Color.accentColor.opacity(0.18)
                      : hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isMultiSelected ? Color.accentColor.opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            if mods.contains(.command) {
                onToggleMultiSelect()
            } else if mods.contains(.option) {
                onPastePlain()
            } else {
                onPaste()
            }
        }
        .contextMenu {
            Button("Paste") { onPaste() }
            Button("Paste as Plain Text") { onPastePlain() }
            transformMenu
            if isEditableText { Button("Edit…") { onEdit() } }
            Divider()
            Button(isQueued ? "Remove from Paste Queue" : "Add to Paste Queue") { onToggleQueue() }
            Button(item.isPinned ? "Unpin" : "Pin") { onPin() }
            categoryMenu
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .help("Click to paste · Command-click to select multiple")
    }

    @ViewBuilder
    private var transformMenu: some View {
        if isEditableText {
            Menu("Paste with Transform") {
                ForEach(TextTransform.allCases) { transform in
                    Button(transform.rawValue) { onPasteTransformed(transform) }
                }
            }
        }
    }

    @ViewBuilder
    private var categoryMenu: some View {
        if !categories.isEmpty {
            Menu("Add to Category") {
                ForEach(categories) { category in
                    Button {
                        onAssign(category)
                    } label: {
                        if category.id == item.categoryID {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
                if item.categoryID != nil {
                    Divider()
                    Button("Remove from Category") { onAssign(nil) }
                }
            }
        }
    }

    fileprivate func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
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

// MARK: - Trash row

private struct TrashItemRow: View {
    let item: ClipboardItem
    let onRestore: () -> Void
    let onDeleteForever: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let app = item.sourceAppName { Text(app) }
                    Text(item.copiedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if hovering {
                Button("Restore") { onRestore() }
                    .controlSize(.small)
                Button(role: .destructive) { onDeleteForever() } label: {
                    Text("Delete Forever")
                }
                .controlSize(.small)
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
        .contextMenu {
            Button("Restore") { onRestore() }
            Button("Delete Forever", role: .destructive) { onDeleteForever() }
        }
    }

    private var iconName: String {
        switch item.content {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .fileURLs: return "doc"
        }
    }
}

// MARK: - Sheets

private struct NewCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = ClipCategory.palette[0]
    let onCreate: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Category").font(.headline)
            TextField("Name (e.g. Work, Links, Receipts)", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                ForEach(ClipCategory.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .orange)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(colorHex == hex ? 0.8 : 0), lineWidth: 2)
                        )
                        .onTapGesture { colorHex = hex }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed, colorHex)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

private struct QuickEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ClipboardItem
    let onSave: (String) -> Void
    @State private var text: String

    init(item: ClipboardItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        if case .text(let s) = item.content {
            _text = State(initialValue: s)
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Clip").font(.headline)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minWidth: 420, minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            Text("Saving replaces the clip's text (formatting is removed).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
