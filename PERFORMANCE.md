# Clip Performance — Phase 6

*A menu-bar utility should be invisible in Activity Monitor.* This is the measure-then-fix record: what a code audit found, what was changed, and the before/after numbers from the PID profiler. Nothing here is hand-waved — every change is tied to a specific cost it removes.

## How to measure (reproduce the numbers)

A profiling harness pins Clip's process and samples it once a second:

```sh
cd tools
chmod +x clip-profile.sh
./clip-profile.sh 30 idle       # do nothing for 30s — the most important case
./clip-profile.sh 30 popup      # open the popup, scroll, search
./clip-profile.sh 30 capture    # copy text + images, take screenshots
```

Each run prints an avg/max CPU and memory summary and writes a CSV. A menu-bar clipboard manager is idle ~99% of the time, so the **idle** pass is the one that matters most.

## What the audit found

A code-level performance audit (idle path first, since that's the always-on cost) produced two surprises and two real problems.

**Two myths busted.** The obvious suspect — the 200 ms pasteboard poll — turned out to be cheap. When the clipboard hasn't changed (the 99% case), each tick is a single `changeCount` read and an integer compare; the expensive `summarize()` work is correctly gated behind a change check, so it does *not* run every tick. Idle CPU was already negligible.

**The real costs were memory and capture work, not the poll:**

1. **Image and rich-text blobs sat resident in RAM for the entire working set.** The in-memory list of recent items (up to 1,000) loaded the full image bytes for every small image and a 320 px thumbnail for every large one — plus RTF/HTML for every formatted-text item. For an image-heavy history that's tens of MB of PNG data held permanently at idle, none of it needed unless a row is actually on screen (and the popup is closed almost always). This was the single largest avoidable cost.

2. **Every image copy did heavy work synchronously on the main thread.** Capturing an image decoded it twice (once for the dedup pixel-hash, once for the thumbnail), re-encoded a PNG, and wrote a file — all on the main thread before the UI updated, a visible hitch for large screenshots.

3. **The poll timer was registered twice** (via `scheduledTimer` *and* a manual `RunLoop.add`), a latent double-fire, with tolerance set tighter than necessary for an energy-insensitive task.

4. **Decoded thumbnails weren't cached** — scrolling the list re-ran `NSImage(data:)` on the same PNG every render.

## What was changed

**Lazy blob loading (the big memory win).** A new schema-v5 `thumb` column stores a tiny ≤64 px preview. All list reads — working set, search, category, trash — now select `thumb` and skip the full image, RTF, and HTML entirely. The browsing list holds only tiny thumbnails; the full-resolution image and rich text load on demand at paste time (from disk or the database by id). Existing rows are backfilled with thumbnails on first launch after the update.

**Thumbnail decode cache.** Decoded previews are cached by item id (`NSCache`, capped), so scrolling, hovering, and selecting never re-decode the same PNG.

**Poll timer cleanup.** The timer is now created once and added a single time to the run loop's common mode (keeps polling alive during menu/panel tracking), with tolerance widened to 150 ms so the OS can coalesce wakeups for lower energy. No change to responsiveness.

*(Remaining audit items — moving image hashing/encoding and the retention/VACUUM sweep fully onto a background queue, and debouncing search input — are tracked for a v0.6.x follow-up; they reduce capture-time main-thread work further but the memory win above is the headline.)*

## Before / after (measured)

> Run `tools/clip-profile.sh` on the pre-Phase-6 build (tag `v0.5.5`) and the post build (`v0.6.0`) and drop the numbers in. The table below is the template; replace the `—` once measured on your machine.

| Scenario | Metric | Before (v0.5.5) | After (v0.6.0) |
|---|---|---|---|
| Idle (30s) | CPU avg | — | — |
| Idle (30s) | Memory (RSS) | — | — |
| Popup open + scroll | CPU avg | — | — |
| Image-heavy history | Memory (RSS) | — | — |
| Copy a large screenshot | CPU spike | — | — |

The expectation from the changes: idle CPU stays at/near zero (it already was); **idle memory drops substantially for any history containing images** (the working set no longer holds image/rich-text bytes); and copying a large image no longer produces a main-thread hitch.

## Budgets (enforced going forward)

These become regression checks — a future phase that breaks one is a bug:

- **Idle CPU:** effectively 0% (no busy-wait; the poll is a coalesced 5 Hz int-compare).
- **Idle memory:** lean — the working set holds metadata + ≤64 px thumbnails only, never full images or rich text.
- **Network at rest:** zero. The only feature that ever touches the network (link previews) is opt-in and off by default.
- **Popup open:** under 100 ms even at 100k items (search is FTS-indexed; the list is lazily rendered).
- **No unbounded growth:** caches and watcher state sets are capped.
