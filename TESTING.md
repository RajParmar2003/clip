# Clip — Regression Test Checklist

Run this full pass before tagging any release candidate. Every step is written so it can be followed without prior knowledge. Before starting: confirm exactly one Clip is running (`pgrep -fl Clip.app` shows one line).

## 1. Capture

- [ ] 1.1 Copy text anywhere (select text, Command+C). Open Clip (Command+Shift+V) — it's the top item, with the source app's name and "x seconds" under it.
- [ ] 1.2 Copy the same text again — it stays as one item (no duplicate), timestamp refreshes.
- [ ] 1.3 Copy an image (right-click an image in a browser → Copy Image). It appears with a thumbnail.
- [ ] 1.4 Copy a file in Finder (click a file, Command+C). It appears with the filename.
- [ ] 1.5 Copy a password from your password manager — it must NOT appear in Clip.
- [ ] 1.6 Put the Mac to sleep for a minute, wake it, copy something — it's captured.

## 2. Popup (Command+Shift+V)

- [ ] 2.1 Popup opens near the mouse; the search box has focus immediately.
- [ ] 2.2 The "Now:" strip under the search box matches what you last copied; copying something else updates it.
- [ ] 2.3 Type to search — results filter live; a word from an OLD item still finds it.
- [ ] 2.4 Arrow keys move the selection; Return pastes the selected item into the app you came from.
- [ ] 2.5 Option+Return pastes without formatting (test with bold text copied from a webpage).
- [ ] 2.6 Command+1 pastes the first item directly.
- [ ] 2.7 Command+P pins the selected item (moves to top with pin icon); Command+P again unpins.
- [ ] 2.8 Press and HOLD Backspace with an item selected — exactly one item is deleted, not many.
- [ ] 2.9 Escape closes the popup; clicking anywhere outside closes it too.

## 3. Main window

- [ ] 3.1 Right-click the menu bar paperclip → Open Clip Window. Window opens with sidebar.
- [ ] 3.2 Sidebar filters work: Text / Links / Images / Files each show only their kind.
- [ ] 3.3 Single click on a row pastes it into the previous app. Option+click pastes plain.
- [ ] 3.4 Hover a row → Copy and Pin buttons appear, plus the "…" menu.
- [ ] 3.5 Resize the window; close and reopen — size is remembered.

## 4. Categories

- [ ] 4.1 Sidebar → New Category… → name it, pick a color → it appears with its color dot.
- [ ] 4.2 Right-click an item → Add to Category → pick it. The item shows the category badge; the sidebar category lists it.
- [ ] 4.3 Right-click the category → Start Collecting (red dot appears). Copy 2 things — both auto-file into it. Stop Collecting.
- [ ] 4.4 Right-click category → Delete Category — items survive, just uncategorized.

## 5. Editing and multi-select

- [ ] 5.1 Right-click a text item → Edit… → change text → Save → the item shows the new text; pasting pastes the new text.
- [ ] 5.2 Command-click 3 items in the window → bar appears at the bottom → choose a separator → "Paste 3 Items" pastes them joined as one.

## 6. Paste queue

- [ ] 6.1 Right-click 3 items → Add to Paste Queue. A floating bar appears at the bottom of the screen showing "Next paste" and the count.
- [ ] 6.2 Click into Notes. Press plain Command+V three times — the three items paste in order; the bar counts down and disappears after the last.
- [ ] 6.3 Queue 2 items, then COPY something new — the bar disappears (queue cancelled) and Command+V pastes the new copy.
- [ ] 6.4 Queue 1 item, press Control+Command+V (hands off other keys after) — it pastes.

## 7. Transforms

- [ ] 7.1 Right-click a lowercase text item → Paste with Transform → UPPERCASE → it pastes in caps; the stored item is unchanged (still lowercase in the list).
- [ ] 7.2 Copy `{"b":1,"a":2}` → Paste with Transform → Pretty-Print JSON → pastes formatted across lines.

## 8. OCR

- [ ] 8.1 Take a screenshot of visible text (or copy an image containing text). Wait ~5 seconds. Search for a word that appears only inside the image — the image is found.
- [ ] 8.2 Settings → Privacy → toggle "Recognize text in images" off; new images are not OCR'd (existing results still searchable).

## 9. Screenshots

- [ ] 9.1 Settings → General → "Capture screenshots I take" ON (grant the folder permission if asked). Shift+Command+4, drag a region, wait for the thumbnail to slide away — the screenshot appears in history with source "Screenshot."
- [ ] 9.2 With "Also put screenshots on the clipboard" ON: take a screenshot, then just Command+V in Notes — it pastes.
- [ ] 9.3 Toggle capture OFF, take a screenshot — it does NOT appear.

## 10. Trash

- [ ] 10.1 Delete an item (right-click → Delete). Sidebar Trash count increments; the item is inside.
- [ ] 10.2 Trash → hover the item → Restore — it returns to history (pin/category intact).
- [ ] 10.3 Re-copy content that's sitting in the Trash — it rescues itself out automatically.
- [ ] 10.4 Trash → Delete Forever on one item — gone. Empty Trash — all gone, after a confirmation.
- [ ] 10.5 "Clear All (keeps pinned)" moves everything unpinned to Trash — nothing is lost outright.

## 11. Storage & settings

- [ ] 11.1 Settings → Storage shows live item count and disk usage; Compact Storage runs without errors and search still works afterward (search for an old item).
- [ ] 11.2 Set "Keep items" to Last 1,000 then back to Unlimited — no data loss beyond the rule (expired items appear in Trash).
- [ ] 11.3 Settings → General → record a different popup shortcut → it works; restore Command+Shift+V.
- [ ] 11.4 Launch at login ON → log out and in (or reboot) → exactly ONE Clip is running (`pgrep -fl Clip.app`).
- [ ] 11.5 Settings → Privacy → add an app to the ignore list → copies from it are not recorded → remove it.

## 12. Lifecycle

- [ ] 12.1 Quit Clip (right-click paperclip → Quit) and relaunch — history, pins, categories all intact.
- [ ] 12.2 Try to launch Clip twice (open the app again while running) — the second launch hands off; still one process.
- [ ] 12.3 Welcome Tour reopens from the menu and walks all three steps.

Failures become v0.x.y patches. A clean pass green-lights the release candidate.
