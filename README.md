# Clip

A fast, simple, privacy-first clipboard manager for macOS. Lives in your menu bar; pops up with **⌘⇧V**.

## Features

- **Instant history popup** — global hotkey (default ⌘⇧V, rebindable), opens at your cursor
- **Fuzzy search** — type to filter; characters match in order anywhere in the clip
- **Keyboard-first** — ↑/↓ navigate · ⏎ paste · ⌥⏎ paste as plain text · ⌘1–9 quick paste · ⌘P pin · ⌫ delete · ⎋ close
- **Pin favorites** — pinned items stay on top and survive history clears
- **Text, images, and files** — rich text keeps its formatting; ⌥⏎ strips it on demand
- **Privacy by default** — honors the [nspasteboard.org](http://nspasteboard.org) concealed/transient types, so passwords copied from 1Password etc. are never recorded; per-app ignore list; everything stored locally (no cloud, no network), history file is owner-read-only
- **Direct paste** — selecting an item pastes straight into the app you were using
- **Settings** — history size, hotkey recorder, launch at login, image capture toggle, clear options

## Requirements

- macOS 13 (Ventura) or later — Intel and Apple Silicon
- Xcode 15+ to build

## Build & run

1. Open `Clip.xcodeproj` in Xcode
2. Select the **Clip** scheme → **My Mac** → press **⌘R**
3. Look for the paperclip icon in your menu bar

Or from the command line:

```sh
xcodebuild -project Clip.xcodeproj -scheme Clip -configuration Release build
```

### First-run permissions

For **direct paste** (Clip presses ⌘V for you), macOS will prompt once for **Accessibility** permission: System Settings → Privacy & Security → Accessibility → enable Clip. Without it, Clip still works — selecting an item copies it and you paste manually. You can also turn off "Paste directly" in Settings.

### Notes

- The app is **not sandboxed**: simulating ⌘V and reading the frontmost app aren't possible in the App Sandbox. This is the same trade-off Maccy's non-App-Store build makes. All data stays on your Mac.
- History is stored at `~/Library/Application Support/Clip/history.json` with `600` permissions.

## Why another clipboard manager?

See [RESEARCH.md](RESEARCH.md) — a comparison of Maccy, Paste, Pastebot, Raycast, and others, and the gaps Clip is built to fill: Maccy's speed, Paste's pinning UX, and Pastebot's privacy rigor, with zero subscriptions and zero cloud.

## Roadmap

- Sequential paste queue (paste several items one after another)
- Text transform filters at paste time (case, trim, etc.)
- OCR search inside image clips

## License

MIT © 2026 Raj Parmar
