# Clip

A fast, private, **unlimited** clipboard manager for macOS. Everything stays on your Mac. Everything is free.

Press **⌘⇧V** anywhere: everything you've ever copied, searchable in milliseconds.

## Why Clip

Every competitor rations what your own disk already paid for: Raycast caps free history at 3 months, Paste charges $29.99/year, Windows keeps 25 items, Apple's built-in forgets after ~8 hours. Clip keeps **everything, forever, locally**, and gives away the features others paywall. See [RESEARCH.md](RESEARCH.md) for the competitive analysis and [ROADMAP.md](ROADMAP.md) for where it's going.

## Features

**Capture**: every copy (text with formatting, images, files) lands in history automatically. Passwords from password managers are excluded by design. Optional: screenshots you take (⇧⌘4) are captured too, no copying needed.

**Find**: the ⌘⇧V popup with instant full-history search (SQLite FTS under the hood: milliseconds at any size), plus a real desktop window with sidebar filters. Images are OCR'd on-device, so screenshots are searchable by the text inside them. The "Now:" strip always shows exactly what ⌘V would paste.

**Paste**: one click pastes into the app you were using. Option-click for plain text. Paste with transforms (UPPERCASE, trim, pretty-print JSON, URL encode…). Queue several items, then paste them one per ⌘V with a floating progress bar. Multi-select and paste joined.

**Organize**: pin favorites, file clips into color-coded categories, flip a category into "collect mode" to auto-file everything you copy during a research sprint. Quick-edit any text clip before pasting.

**Forgive**: deletes go to a 30-day Trash with one-click restore. Holding Backspace can't mass-delete. Re-copying trashed content rescues it.

**Trust**: 100% local. No account, no cloud, no telemetry, no subscription. The only optional network feature (link previews) is off by default and clearly labeled. History is stored owner-only at `~/Library/Application Support/Clip/`.

## Shortcuts

| Keys | Action |
|---|---|
| ⌘⇧V | Open the popup (rebindable in Settings) |
| ↑ ↓ then ⏎ | Choose and paste |
| ⌥⏎ | Paste as plain text |
| ⌘1–9 | Paste item 1–9 instantly |
| ⌘P | Pin / unpin |
| ⎋ | Close |
| ⌃⌘V | Paste next queued item |

## Install

**Requirements:** macOS 13 (Ventura) or later, Apple Silicon or Intel.

Until the notarized download ships (v1.0.0), build from source:

1. Clone, open `Clip.xcodeproj` in Xcode 15+
2. Set your development team under Signing & Capabilities (a stable signing identity keeps macOS permissions across rebuilds)
3. Run (⌘R), then grant the two permissions Clip asks for, each explained in-app:
   - **Accessibility**: lets Clip press Paste for you (direct paste)
   - **Screenshots folder**: only if you enable screenshot capture

## Testing

[TESTING.md](TESTING.md) is the full regression checklist run before every release.

## License

MIT © 2026 Raj Parmar
