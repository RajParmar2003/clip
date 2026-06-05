import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: ClipboardStore
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            GeneralSettings(prefs: prefs)
                .tabItem { Label("General", systemImage: "gear") }
            StorageSettings(prefs: prefs, store: store)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            PrivacySettings(prefs: prefs, store: store)
                .tabItem { Label("Privacy", systemImage: "lock") }
        }
        .frame(width: 440)
        .padding(.bottom, 4)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = Preferences.shared.launchAtLogin

    var body: some View {
        Form {
            LabeledContent("Open history") {
                HotKeyRecorder()
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    prefs.launchAtLogin = newValue
                    // Re-read in case the change failed.
                    launchAtLogin = prefs.launchAtLogin
                }

            Toggle("Paste directly into the active app", isOn: Binding(
                get: { prefs.pasteDirectly },
                set: { prefs.pasteDirectly = $0 }
            ))
            Text("When off, selecting an item only copies it. Direct paste needs Accessibility permission (you'll be prompted once).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Capture images", isOn: Binding(
                get: { prefs.captureImages },
                set: { prefs.captureImages = $0 }
            ))

            Toggle("Fetch link previews", isOn: Binding(
                get: { prefs.fetchLinkPreviews },
                set: { prefs.fetchLinkPreviews = $0 }
            ))
            Text("Shows page titles and site icons for copied links. This is Clip's only feature that touches the network — it fetches each link's own page, nothing else. Off by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @ObservedObject var prefs: Preferences
    let store: ClipboardStore
    @State private var stats: SQLiteStore.Stats?
    @State private var compacting = false

    var body: some View {
        Form {
            Section("Usage") {
                LabeledContent("Items", value: statsText { "\($0.totalItems.formatted()) (\($0.pinnedItems) pinned)" })
                LabeledContent("Database", value: statsText { byteString($0.dbBytes) })
                LabeledContent("Image files", value: statsText { byteString($0.imageFileBytes) })
                Button(compacting ? "Compacting…" : "Compact Storage") {
                    compacting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        store.engine.compact()
                        stats = store.engine.stats()
                        compacting = false
                    }
                }
                .disabled(compacting)
            }

            Section("Retention") {
                Picker("Keep items", selection: Binding(
                    get: { prefs.historyLimit },
                    set: { prefs.historyLimit = $0; store.applyRetention(); stats = store.engine.stats() }
                )) {
                    Text("Unlimited").tag(0)
                    Text("Last 1,000").tag(1000)
                    Text("Last 10,000").tag(10_000)
                    Text("Last 100,000").tag(100_000)
                }
                Picker("Expire after", selection: Binding(
                    get: { prefs.retentionDays },
                    set: { prefs.retentionDays = $0; store.applyRetention(); stats = store.engine.stats() }
                )) {
                    Text("Never").tag(0)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                Picker("Expire images after", selection: Binding(
                    get: { prefs.imageRetentionDays },
                    set: { prefs.imageRetentionDays = $0; store.applyRetention(); stats = store.engine.stats() }
                )) {
                    Text("Never").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                Text("Pinned items are never expired, by any rule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear { stats = store.engine.stats() }
    }

    private func statsText(_ transform: (SQLiteStore.Stats) -> String) -> String {
        stats.map(transform) ?? "…"
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @ObservedObject var prefs: Preferences
    let store: ClipboardStore
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Toggle("Ignore passwords and sensitive data", isOn: Binding(
                get: { prefs.ignoreConcealed },
                set: { prefs.ignoreConcealed = $0 }
            ))
            Text("Skips items that password managers (1Password, etc.) mark as concealed or transient.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Recognize text in images", isOn: Binding(
                get: { prefs.ocrImages },
                set: { prefs.ocrImages = $0 }
            ))
            Text("Makes screenshots searchable by the text inside them. Runs entirely on this Mac (Apple Vision) — nothing leaves your device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("Ignored apps") {
                if prefs.ignoredApps.isEmpty {
                    Text("Copies from apps in this list are never recorded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(prefs.ignoredApps, id: \.self) { bundleID in
                    HStack {
                        Text(appName(for: bundleID) ?? bundleID)
                        Spacer()
                        Button(role: .destructive) {
                            prefs.ignoredApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add App…") { pickApp() }
            }

            Section {
                Button("Clear History (keep pinned)") {
                    store.clearHistory(keepPinned: true)
                }
                Button("Clear Everything", role: .destructive) {
                    showClearConfirm = true
                }
                .confirmationDialog("Delete all clipboard history, including pinned items?",
                                    isPresented: $showClearConfirm) {
                    Button("Delete All", role: .destructive) {
                        store.clearHistory(keepPinned: false)
                    }
                }
            }

            Text("All data is stored locally on this Mac. Nothing is synced or sent anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK,
           let url = panel.url,
           let bundle = Bundle(url: url),
           let bundleID = bundle.bundleIdentifier,
           !prefs.ignoredApps.contains(bundleID) {
            prefs.ignoredApps.append(bundleID)
        }
    }
}

// MARK: - Hotkey recorder

/// Click, then press the desired combination. Esc cancels.
struct HotKeyRecorder: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : prefs.hotKeyDescription) {
            recording ? stopRecording() : startRecording()
        }
        .buttonStyle(.bordered)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }
            if event.keyCode == 53 { return nil } // esc cancels
            let mods = KeyCodeHelper.carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier so plain typing can't become a hotkey.
            guard mods != 0 else { return nil }
            prefs.setHotKey(code: UInt32(event.keyCode), modifiers: mods)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
