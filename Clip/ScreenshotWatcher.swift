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
    private var folderSource: DispatchSourceFileSystemObject?
    private var folderFD: Int32 = -1
    private let log = Logger(subsystem: "com.rajparmar.Clip", category: "screenshots")

    init(store: ClipboardStore) {
        self.store = store
    }

    /// Where macOS saves screenshots: the user's configured location
    /// (`defaults write com.apple.screencapture location`) or ~/Desktop.
    static func screenshotsDirectory() -> URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (custom as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func start() {
        guard !started else { return }
        started = true

        // Snapshot existing files so only screenshots taken from now on count.
        seedFolderBaseline()

        // Primary: Spotlight metadata (path- and locale-independent).
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

        // Fallback + consent trigger: watch the screenshots folder directly.
        // Spotlight silently hides TCC-protected folders (Desktop!) until the
        // user grants access, and the grant is only prompted by an actual
        // read — so we read immediately and watch the directory ourselves.
        startFolderWatch()
        scanFolder() // first read = macOS shows the folder-access prompt now
    }

    func stop() {
        guard started else { return }
        started = false
        initialGatherDone = false
        query.stop()
        NotificationCenter.default.removeObserver(self)
        folderSource?.cancel()
        folderSource = nil
        if folderFD >= 0 { close(folderFD) }
        folderFD = -1
    }

    // MARK: - Folder watch (fallback path)

    private func startFolderWatch() {
        let dir = Self.screenshotsDirectory()
        folderFD = open(dir.path, O_EVTONLY)
        guard folderFD >= 0 else {
            log.warning("cannot open screenshots folder for watching: \(dir.path, privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: folderFD, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in
            // Let the screenshot file finish writing before reading.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self?.scanFolder()
            }
        }
        source.resume()
        folderSource = source
        log.info("watching screenshots folder: \(dir.path, privacy: .public)")
    }

    /// Snapshot the directory at start so "new" means "not present at start" —
    /// immune to system clock changes, unlike a creation-date comparison.
    private func seedFolderBaseline() {
        let dir = Self.screenshotsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return } // permission pending — first new file still ingests
        for file in files { seenPaths.insert(Self.normalize(file.path)) }
    }

    /// Looks for image files that appeared after the watcher started. "New" is
    /// determined by absence from seenPaths (seeded at start), not by clock.
    private func scanFolder() {
        guard started else { return }
        let dir = Self.screenshotsDirectory()
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            log.warning("cannot list screenshots folder (permission pending or denied)")
            return
        }
        for file in files {
            let key = Self.normalize(file.path)
            guard imageExtensions.contains(file.pathExtension.lowercased()),
                  !seenPaths.contains(key) else { continue }
            markSeen(key)
            ingest(path: file.path, retriesLeft: 3)
        }
    }

    /// Standardize a path so the metadata and folder paths agree on identity
    /// (symlinked Desktop, /private prefixes, trailing slashes).
    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Insert into seenPaths with a bound so a long session can't grow it
    /// without limit (Phase 7 memory budget).
    private func markSeen(_ key: String) {
        if seenPaths.count > 4000 {
            seenPaths.removeAll(keepingCapacity: true)
            seedFolderBaseline()
        }
        seenPaths.insert(key)
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
            guard let rawPath = item.value(forAttribute: NSMetadataItemPathKey as String) as? String else { continue }
            let key = Self.normalize(rawPath)
            guard !seenPaths.contains(key) else { continue }
            markSeen(key)
            ingest(path: rawPath, retriesLeft: 3)
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
        // The store enforces the real size cap (and the captureImages gate);
        // a generous pre-filter here just avoids decoding absurd files.
        guard png.count <= 60_000_000 else { return }

        store?.addScreenshot(png: png)
        log.info("captured screenshot (\(png.count) bytes)")
    }
}
