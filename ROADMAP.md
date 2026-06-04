# Clip Roadmap

*Researched and written June 2026. Built on ~25 web searches and 30+ fetched primary sources: Hacker News threads, Reddit/forum complaints, GitHub issue trackers (vote-ranked), vendor documentation, sqlite.org engineering docs, and current pricing pages. Sources listed at the bottom of each section.*

## The thesis

Every competitor monetizes or rations exactly the things that cost nothing when the data lives on the user's own disk. Raycast caps free history at 3 months and sells "unlimited." Alfred hard-caps everyone at 3 months. Paste charges $29.99/year, largely for sync and OCR search. Windows Win+V caps at 25 items and wipes on reboot. Apple's new built-in (macOS Tahoe) keeps history for only ~8 hours and users call it "lunacy."

Clip's position: **everything unlimited, everything local, everything free.** The user's disk is the storage bill, Apple's on-device Vision framework is the OCR bill, and there is no server. We give away the paywalled features and win on trust.

## The three users we design for

**Joe Schmoe (casual)** — copies a YouTube link, gets distracted, copies something else, loses the link. Needs: a visible thing to click (menu bar + a real window), recognizable previews (favicon, thumbnail), one click to paste, one click to "keep this," and zero configuration. Never reads docs, never learns more than one shortcut.

**The average user** — copies addresses, code snippets, screenshots all day. Needs: search that always finds it, favorites organized into categories, drag-and-drop, paste-as-plain-text, and confidence that passwords never get recorded.

**The ultra-productive user** — fills forms, transforms text, pastes sequences. Needs: paste queues, transforms/filters at paste time, per-clip hotkeys, snippets, OCR'd screenshots, and everything reachable without the mouse.

The roadmap below sequences features so each release ships value for at least two of the three.

---

## Phase 1 — Predictability (v1.1, the Win+V lessons)

Research finding: Win+V's reputation for being "easy" rests on four patterns — one-click paste into the previously focused field, a flat newest-first list with visible per-item actions, pin-survives-everything, and self-onboarding (pressing the shortcut the first time offers to turn it on). Apple's Tahoe history validates this by failing at each: double-click to paste, buried in Spotlight, no pins, 8-hour memory.

1. **Main desktop window** (your ask). The popup stays for speed, but Clip gets a real, resizable window: sidebar (History, Favorites, categories), card list with previews, search bar, visible Pin / Delete / Copy buttons on hover, and a visible "Clear All (keeps pinned)" button. Click the menu bar paperclip → window opens. No shortcut knowledge required. Research: resizable window with large preview pane is the stated reason ClipBook was built — both Alfred and Raycast refuse to allow it.
2. **One-click paste.** Single click on a row pastes into the app you were just in (current behavior keeps double-safety: click pastes, right-click menu for more). The single most load-bearing Win+V interaction.
3. **Self-onboarding.** First launch: a 3-step welcome (here's the icon, here's the shortcut, here's how pin works) and the Accessibility permission flow explained in plain words with a live "test paste" box.
4. **Reliability hardening.** The #1 cross-app failure users report (ClipBook, Raycast, Paste, Pastebot, Win+V all) is *missed copies* from polling. Tighten the poll loop, add a watchdog, and log capture misses so we can prove we don't drop copies. Also fix file round-tripping (Pastebot can't paste files back into Finder — a known years-old gap we can win).
5. **Link previews.** Fetch favicon + page title for copied URLs (off-by-default network toggle for the privacy-strict, like Raycast does). This is the Joe Schmoe feature: "my YouTube link" is found by its thumbnail, not by memory.
6. **Per-item visible "..." menu** with Pin, Paste as Plain Text, Edit, Delete, Share. Recognition over recall (Nielsen heuristic #6): every capability discoverable by looking.

## Phase 2 — Infinite storage (v2, the engine swap)

Research findings, all from sqlite.org docs, benchmarks, and competitor GitHub issues: JSON read-modify-write breaks around 1 MB / a few thousand items (we currently use JSON — fine for v1, a wall for v2). Maccy's 999-item cap is its single most-upvoted open issue since 2021 (+46). Ditto users hit 9–14 GB databases from un-vacuumed image bloat. SQLite FTS5 with a trigram tokenizer turns 1.7-second substring scans into 10–30 ms at 18 million rows — meaning effectively instant at any clipboard scale.

1. **SQLite + FTS5 storage engine.** WAL mode, one transaction per copy. Full-text substring search via trigram tokenizer with `detail='none'` (~1.15x storage overhead). Migration from history.json is automatic and silent.
2. **Truly unlimited history.** No cap, no time expiry by default. The marketing line writes itself: "Raycast charges $96/year for unlimited history. Your disk already paid for it."
3. **Hybrid image storage.** SQLite's own measured guidance: blobs under 100 KB are faster inside the DB; larger ones faster as files. Thumbnails in-DB, full images as SHA-256 content-addressed files on disk. Hash-based dedup means re-copying the same screenshot costs zero bytes.
4. **Lazy UI.** The documented failure at 30k–50k items in Maccy and CopyQ is never the database — it's eager rendering. The window renders ~100 rows and pages; everything older is reached through search.
5. **Optional retention controls** for those who want them: count cap, age expiry, separate text vs image policies (requested for years in Maccy, never shipped), pin exemption always. Real `DELETE`s plus scheduled `VACUUM` — Ditto's orphaned-row bloat (24 MB of clips inside a 1.7 GB file) is the cautionary tale.
6. **Storage dashboard** in Settings: items count, disk used, largest items, one-click compaction.

## Phase 3 — Favorites, categories, and organization (v2.5, your "clips" model)

Research: Paste's Pinboards and Pastebot's Custom Pasteboards are the loved organization models; Copy 'Em's "Auto-Star into the active list" is the sleeper feature for research sessions.

1. **Favorites with categories.** A clip can be favorited (one click / Command+P) and assigned to a named, color-coded category: Work, Snippets, Links, Receipts. Categories appear in the main-window sidebar and as submenus in the popup. Favorites never expire and survive Clear All — the Win+V pin contract, extended.
2. **Collect mode.** Toggle a category as "collecting": every new copy lands in it automatically. Built for research sprints (copy 20 quotes, they're all filed).
3. **Drag-and-drop both ways.** Drag a clip out into any app (paste) or into a category (file it). Drag images out as files.
4. **Quick edit.** Command+E opens an inline editor to tweak a clip before pasting — a top wish in the ClipBook Show HN thread.
5. **Multi-select paste with separators.** Select several clips, paste them joined by newline/tab/space — ClipBook's quasi-queue, and the answer to Maccy's #2 most-upvoted issue (+31, "paste several items as one").

## Phase 4 — Power tier (v3)

Research: these are the features that remain genuinely power-exclusive across the market, and the ones Pastebot's $12.99 reputation rests on.

1. **Paste queue (sequential paste).** Arrow-right on clips to enqueue; Control+Command+V pastes them one per press. Pastebot caps this at 25 items; we don't.
2. **Transforms at paste time.** Built-in filters: plain text, UPPER/lower/Title case, trim whitespace, JSON pretty-print, URL encode/decode, markdown→plain. Chainable and saveable like Pastebot, but keyboard-invokable end-to-end — the #1 wish of the power user who left Pastebot ("I'd like to do this mouse-free").
3. **OCR on copied images.** Apple Vision framework, on-device, free. Screenshots become searchable. Paste subscription-gates this; Raycast ships it free — we match Raycast and beat Paste.
4. **Per-clip global hotkeys.** Assign Command+Option+1 to your address, Command+Option+2 to your signature. Pastebot's secret weapon, made discoverable.
5. **Snippets with placeholders** (later in phase): {date}, {time}, {clipboard:N}, {cursor} — the Alfred model.
6. **Scripting surface**: a small CLI (`clip list`, `clip get N`, `clip search`) and Shortcuts.app actions. Power users on HN consistently reward scriptability with loyalty.

## Phase 5 — Reach (v4, the honest trade-offs)

1. **Optional iCloud sync** — off by default, loudly labeled, favorites-only mode available (the CopyLess model), full-history mode for those who opt in. Research is two-sided here: sync is both the most-requested feature (Maccy #182) *and* the most-distrusted ("I don't trust a 'secure' product that defaults to unsafe behavior" — HN on Paste). Default-off with Apple's E2E iCloud is the only stance consistent with our privacy thesis.
2. **iOS companion** (favorites + recent history via that opt-in sync). Pastebot's most-mourned gap.
3. **On-device AI (Apple Intelligence)**: summarize a long clip, clean up formatting, "find the URL I copied yesterday about X" natural-language search. Undercuts the Paste/Raycast AI subscriptions with zero server bill.
4. **Sharing**: export a category as a file; AirDrop a clip set. No accounts, ever.

---

## Explicit non-goals

No subscription, no accounts, no telemetry, no cloud-by-default, no Electron, no feature that requires our server to exist. Each of these is a documented complaint against a competitor; their absence is the product.

## UX principles (carved from the research)

Recognition over recall: every action visible in the UI, shortcuts as accelerators only. One famous shortcut (Command+Shift+V — chosen by Paste and ClipBook too, because it rhymes with paste). Pin means safe: survives clears, reboots, retention — one concept, triple duty. Forgiveness is the product: the core emotional moment is "I thought I lost it — it's there." Privacy is never violated: concealed-type exclusion stays on by default, and the first password that *doesn't* appear in history is the moment trust is won.

## Competitive scoreboard to beat

| | Win+V | Tahoe built-in | Maccy | Raycast free | Paste ($29.99/yr) | Clip target |
|---|---|---|---|---|---|---|
| History size | 25 items | ~8 hours | 999 items | 3 months | unlimited | **unlimited, free** |
| Survives reboot | pins only | no | yes | yes | yes | **yes** |
| Search | none | minimal | fuzzy | yes | yes + OCR | **FTS5 + OCR, free** |
| Main window | no | no | no | no | yes | **yes** |
| One-click paste | yes | no (double) | yes | yes | yes | **yes** |
| Favorites + categories | pins only | no | pins only | pins | Pinboards | **categories + collect mode** |
| Transforms / queue | no | no | no | partial | stack only | **both, unlimited** |
| Local-only | partial | yes | yes | yes | no (iCloud) | **yes, by default** |
| Price | free | free | free | free→$96/yr | $29.99/yr | **free** |

## Engineering checkpoints

Phase 2 is the riskiest (storage migration) — ship it behind a "new engine" beta toggle first. Capture reliability (Phase 1.4) gets a regression test: scripted 100-copy burst, assert 100 rows. UI perf budget: popup opens in under 100 ms with 100k items in the DB. Every phase ends with the app notarized and a GitHub release so non-Xcode users can download a .dmg — that's the real "desktop app for everyone" milestone.

---

## Source notes

User complaints and wishes: [HN Maccy thread](https://news.ycombinator.com/item?id=31867121) · [ClipBook Show HN](https://news.ycombinator.com/item?id=40648404) · [Keyboard Maestro forum: Switching from Pastebot](https://forum.keyboardmaestro.com/t/switching-from-pastebot/50339) · [MacRumors: Tahoe 8-hour clipboard](https://forums.macrumors.com/threads/tahoe-clipboard-manager-has-an-8-hour-memory-why.2458897/) · [Maccy #310 unlimited history](https://github.com/p0deje/Maccy/issues/310) · [Maccy #239 paste-multiple](https://github.com/p0deje/Maccy/issues/239) · [raycast/extensions #24425 missed copies](https://github.com/raycast/extensions/issues/24425)

Win+V UX: [Microsoft clipboard docs](https://support.microsoft.com/en-us/windows/using-the-clipboard-30375039-ce71-9fe4-5b30-21b7aab6b13f) · [How-To Geek](https://www.howtogeek.com/clipboard-history-is-the-best-windows-feature-youre-probably-not-using/) · [Office Watch on macOS 26 history](https://office-watch.com/2025/macos-26-clipboard-history/) · [NN/g usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/) · [Ditto](https://sabrogden.github.io/Ditto/)

Feature tiers: [Pastebot sequential paste](https://tapbots.com/pastebot/help/07_sequential_paste/) · [Pastebot filters](https://tapbots.com/pastebot/help/05_filters/) · [Paste on Mac help](https://pasteapp.io/help/paste-on-mac) · [Raycast clipboard manual](https://manual.raycast.com/clipboard-history) · [Alfred dynamic placeholders](https://www.alfredapp.com/help/features/clipboard/dynamic-placeholders/) · [Copy 'Em](https://apprywhere.com/ce-mac.html) · [ClipBook](https://clipbook.app/)

Storage engineering: [SQLite internal vs external BLOBs](https://sqlite.org/intern-v-extern-blob.html) · [SQLite faster than FS](https://sqlite.org/fasterthanfs.html) · [FTS5 docs](https://sqlite.org/fts5.html) · [FTS5 trigram benchmark](https://andrewmara.com/blog/faster-sqlite-like-queries-using-fts5-trigram-indexes) · [When not JSON](https://pl-rants.net/posts/when-not-json/) · [Maccy Storage.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Storage.swift) · [Ditto DB bloat thread](https://sourceforge.net/p/ditto-cp/discussion/287511/thread/21a624a7/)

Pricing (June 2026): [Paste pricing](https://pasteapp.io/pricing) ($3.99/mo, $29.99/yr, $89.99 lifetime) · [Pastebot buy](https://tapbots.com/pastebot/buy/) ($12.99) · [ClipBook pricing](https://clipbook.app/pricing/) ($9.99–$29.99) · [Raycast pricing](https://www.raycast.com/pricing) (Pro $8/mo annual; free history capped at 3 months)
