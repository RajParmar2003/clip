# Mac Clipboard Manager — Competitive Analysis

*June 2026*

## The landscape

The market splits into three camps: free/open-source minimalists (Maccy, Clipy, CopyClip), premium polished apps (Paste, Pastebot, ClipBook), and launcher-bundled (Raycast). No single tool covers everything well — that's the gap.

## Feature matrix

| Feature | Maccy | Paste | Pastebot | Raycast | CopyClip/Clipy |
|---|---|---|---|---|---|
| Price | Free (OSS) | $29.99/yr sub | $12.99 one-time | Free tier | Free |
| Global hotkey popup | ✅ | ✅ | ✅ | ✅ | ✅ |
| Instant search | ✅ (fuzzy) | ✅ | ✅ | ✅ | ⚠️ basic |
| Pin/favorite items | ✅ (⌥P) | ✅ Pinboards | ✅ Collections | ✅ | ❌ |
| Images/files/rich content | ✅ | ✅ best-in-class | ✅ | ✅ | ⚠️ text-mostly |
| Paste plain text option | ✅ | ✅ | ✅ | ⚠️ default-only | ❌ |
| Sequential/queue paste | ❌ | ❌ | ✅ unique | ❌ | ❌ |
| Text transform filters | ❌ | ❌ | ✅ unique | ❌ | ❌ |
| App blacklist (ignore apps) | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Password/concealed-type exclusion | ✅ | ✅ | ✅ | ✅ | ❌ |
| iCloud sync (iPhone/iPad) | ❌ | ✅ unique | ✅ Mac-only | ❌ | ❌ |
| OCR / search in images | ❌ | ✅ (2025) | ❌ | ❌ | ❌ |
| Local-only privacy | ✅ | ❌ (iCloud) | ✅ optional | ✅ | ✅ |
| Lightweight (low RAM/CPU) | ✅ best | ❌ heavy | ⚠️ | ⚠️ whole launcher | ✅ |
| Open source | ✅ | ❌ | ❌ | ❌ | Clipy ✅ |

## What each does uniquely well

- **Maccy** — speed and simplicity. Opens and searches the whole history in a fraction of a second; fully local; every shortcut rebindable. The benchmark for "fast and out of the way."
- **Paste** — visual timeline UI, Pinboards, iCloud sync across Apple devices, OCR search in image clips. The benchmark for polish.
- **Pastebot** — power features nobody else has: sequential paste queues (⌃⇧V pastes items one after another) and live text-transform filters (case change, whitespace strip, etc.) applied at paste time.
- **Raycast** — clipboard is a free bonus inside a launcher; shows source app, timestamp, and type filters.
- **ClipBook** — per-type retention periods, keeps favorites when clearing history, OCR text extraction.

## Common complaints (the openings)

1. **Paste's subscription** — $29.99/yr for a utility; users want one-time or free.
2. **Paste's iCloud** — sensitive data stored off-device; privacy-conscious users avoid it.
3. **Maccy/Raycast paste unformatted only as a binary** — users want both formatted and plain paste per-item, on demand.
4. **Nobody combines** Pastebot's power (queues, filters) with Maccy's speed/price and Paste's pinning UX.

## Recommended feature set for Clip (v1)

The all-in-one play: Maccy's speed + the must-have features from each, 100% local, free.

1. Menu-bar app, near-zero idle CPU, instant popup on **⌘⇧V**
2. Searchable history (fuzzy, as-you-type), keyboard-first navigation (↑↓ + ⏎, ⌘1–9 quick paste)
3. Pin favorites to top (⌘P)
4. Paste formatted (⏎) **or** plain text (⌥⏎) per item
5. Text, images, file URLs supported
6. Privacy by default: honor `org.nspasteboard.ConcealedType`/`TransientType` (skips 1Password etc.), per-app ignore list, everything stored locally
7. Settings: history size, hotkey, launch at login, paste-directly vs copy-only
8. v2 roadmap: sequential paste queue, transform filters, OCR — the Pastebot/Paste features that justify "all-in-one"

## Sources

- [QuietClip — Clipboard Manager Comparison 2026](https://quietclip.app/blog/clipboard-manager-comparison/)
- [OneTap — Paste App Alternatives 2026](https://www.onetapapp.co/OneTap-blog-posts/paste-app-alternatives-7-best-clipboard-managers-for-mac-in-2026)
- [Maccy — GitHub](https://github.com/p0deje/Maccy) / [maccy.app](https://maccy.app/)
- [Paste — pasteapp.io](https://pasteapp.io/) / [Pricing](https://pasteapp.io/pricing)
- [Pastebot — Tapbots](https://tapbots.com/pastebot/) / [Preferences docs](https://tapbots.com/pastebot/help/08_preferences/)
- [Raycast Clipboard History](https://www.raycast.com/core-features/clipboard-history)
- [ClipBook Changelog](https://clipbook.app/changelog/)
- [NSPasteboard.org — transient/concealed types](http://nspasteboard.org/)
- [Zapier — Best Clipboard Managers](https://zapier.com/blog/best-clipboard-managers/)
