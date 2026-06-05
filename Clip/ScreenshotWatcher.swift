import AppKit
import Foundation
import os.log

/// Captures screenshots the user takes (Shift+Command+3/4/5 file mode)
/// straight into history — no Command+C required.
///
/// Design (ROADMAP Phase 5): watch Spotlight metadata for files tagged
/// `kMDItemIsScreenCapture == 1` instead of watching a folder path. This
/// survives custom save locations (`defaults write com.apple.screencapture
/// location`), localized filenames, and OS updates, because it keys off
/// indexed metadata rather than naming conventions.
///
/// Notes from the design:
/// - The floating thumbnail delays the file write ~5s; the metadata update
///   arrives after, so we read on arrival (with one retry for slow writes).
/// - Clipboard-mode screenshots (Control+Shift+Command+3/4) are already
///   captured by the pasteboard watcher; content-hash dedup in the engine
///   means a screenshot seen via both paths still stores exactly once.
/// - Reading from Desktop triggers macOS's one-time folder-access consent.
final class ScreenshotWatcher {
    private let query = NSMetadataQuery()
    private weak var store: ClipboardStore?
    private var started = false
    private var initialGatherDone = false
    private var seenPaths = Set<String>()
    private let log = Logger(subsystem: "com.rajparmar.Clip", category: "screenshots")

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        guard !started else { return }
        started = true

        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.5

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(gatherFinished),
                           name: .NSMetadataQueryDidFinishGathering, object: query)
        center.addObserver(self, selector: #selector(queryUpdated),
                           name: .NSMetadataQueryDidUpdate, object: query)

        if !query.start() {
            log.error("screenshot metadata query failed to start — Spotlight may be disabled")
        }
    }

    func stop() {
        guard started else { return }
        started = false
        initialGatherDone = false
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    /// The initial gather returns every screenshot that already exists —
    /// history we must not import. Only post-gather additions are new.
    @objc private func gatherFinished(_ note: Notification) {
        initialGatherDone = true
        query.enableUpdates()
        log.info("screenshot watcher ready (\(self.query.resultCount) existing screenshots indexed)")
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard initialGatherDone else { return }
        let added = (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
        for item in added {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey as String) as? String,
                  !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)
            ingest(path: path, retriesLeft: 3)
        }
    }

    private func ingest(path: String, retriesLeft: Int) {
        guard Preferences.shared.captureScreenshots else { return }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            // The file can lag the metadata event (thumbnail editing, slow
            // disk). Retry briefly, then give up quietly.
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.ingest(path: path, retriesLeft: retriesLeft - 1)
                }
            } else {
                log.warning("could not read screenshot at \(path, privacy: .public)")
            }
            return
        }

        // Normalize to PNG (screenshots default to PNG; users can configure
        // JPG/HEIC — convert so downstream storage and paste stay uniform).
        let png: Data
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            png = data
        } else if let rep = NSBitmapImageRep(data: data),
                  let converted = rep.representation(using: .png, properties: [:]) {
            png = converted
        } else {
            log.warning("unrecognized screenshot format at \(path, privacy: .public)")
            return
        }
        guard png.count <= 50_000_000 else { return }

        store?.addScreenshot(png: png)
        log.info("captured screenshot (\(png.count) bytes)")
    }
}
