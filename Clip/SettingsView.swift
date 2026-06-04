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

            Picker("History size", selection: Binding(
                get: { prefs.historyLimit },
                set: { prefs.historyLimit = $0 }
            )) {
                Text("100").tag(100)
                Text("250").tag(250)
                Text("500").tag(500)
                Text("1,000").tag(1000)
                Text("5,000").tag(5000)
            }

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
