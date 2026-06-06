import AppKit
import CryptoKit
import Foundation
import SQLite3
import os.log

/// SQLite-backed storage engine: the "infinite history" core.
///
/// Design (see ROADMAP.md Phase 2):
/// - WAL mode, one transaction per copy
/// - FTS5 trigram index → substring search stays ~10ms at millions of rows
/// - Content-hash (SHA-256) dedup: re-copying identical content costs zero rows
/// - Hybrid images: ≤100KB PNGs live in the DB; larger ones go to
///   content-addressed files on disk with a small in-DB thumbnail
/// - All calls are main-thread (matches ClipboardStore's threading model);
///   each operation is milliseconds.
final class SQLiteStore {
    private var db: OpaquePointer?
    private let log = Logger(subsystem: "com.rajparmar.Clip", category: "storage")

    static let imageFileThreshold = 100_000 // bytes; sqlite.org's measured crossover

    private let dirURL: URL
    private let dbURL: URL
    let imagesDirURL: URL

    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        dirURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clip", isDirectory: true)
        dbURL = dirURL.appendingPathComponent("clip.sqlite3")
        imagesDirURL = dirURL.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirURL, withIntermediateDirectories: true)

        open()
        migrateSchema()
        migrateLegacyJSONIfPresent()
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: - Setup

    private func open() {
        if sqlite3_open_v2(dbURL.path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                           nil) != SQLITE_OK {
            log.fault("cannot open database: \(self.lastError())")
            return
        }
        exec("PRAGMA journal_mode = WAL")
        exec("PRAGMA synchronous = NORMAL")
        exec("PRAGMA foreign_keys = ON")
        // History can contain sensitive text — owner-only permissions.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbURL.path)
    }

    private func migrateSchema() {
        let version = scalarInt("PRAGMA user_version") ?? 0
        if version < 1 { migrateToV1() }
        if version < 2 { migrateToV2() }
        if version < 3 { migrateToV3() }
        if version < 4 { migrateToV4() }
    }

    /// v4: Trash. Deletes become recoverable — deleted_at marks an item as
    /// trashed; a sweep purges trash older than 30 days.
    private func migrateToV4() {
        let hasColumn = scalarInt("SELECT COUNT(*) FROM pragma_table_info('items') WHERE name = 'deleted_at'") ?? 0
        if hasColumn == 0 {
            exec("ALTER TABLE items ADD COLUMN deleted_at REAL")
        }
        exec("""
        CREATE INDEX IF NOT EXISTS idx_items_deleted ON items(deleted_at) WHERE deleted_at IS NOT NULL;
        PRAGMA user_version = 4;
        """)
    }

    /// v3: OCR text column, indexed by FTS. FTS5 can't add columns, so the
    /// index is dropped and rebuilt from the content table (fast: 'rebuild'
    /// scans items once).
    private func migrateToV3() {
        let hasColumn = scalarInt("SELECT COUNT(*) FROM pragma_table_info('items') WHERE name = 'ocr_text'") ?? 0
        if hasColumn == 0 {
            exec("ALTER TABLE items ADD COLUMN ocr_text TEXT")
        }
        exec("""
        DROP TRIGGER IF EXISTS items_ai;
        DROP TRIGGER IF EXISTS items_ad;
        DROP TRIGGER IF EXISTS items_au;
        DROP TABLE IF EXISTS items_fts;

        CREATE VIRTUAL TABLE items_fts USING fts5(
            text, link_title, ocr_text,
            content='items', content_rowid='rowid',
            tokenize='trigram'
        );

        CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
            INSERT INTO items_fts(rowid, text, link_title, ocr_text)
            VALUES (new.rowid, coalesce(new.text,''), coalesce(new.link_title,''), coalesce(new.ocr_text,''));
        END;
        CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text, link_title, ocr_text)
            VALUES ('delete', old.rowid, coalesce(old.text,''), coalesce(old.link_title,''), coalesce(old.ocr_text,''));
        END;
        CREATE TRIGGER items_au AFTER UPDATE OF text, link_title, ocr_text ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text, link_title, ocr_text)
            VALUES ('delete', old.rowid, coalesce(old.text,''), coalesce(old.link_title,''), coalesce(old.ocr_text,''));
            INSERT INTO items_fts(rowid, text, link_title, ocr_text)
            VALUES (new.rowid, coalesce(new.text,''), coalesce(new.link_title,''), coalesce(new.ocr_text,''));
        END;

        INSERT INTO items_fts(items_fts) VALUES('rebuild');
        PRAGMA user_version = 3;
        """)
    }

    private func migrateToV2() {
        exec("""
        CREATE TABLE IF NOT EXISTS categories (
            id            TEXT NOT NULL UNIQUE,
            name          TEXT NOT NULL,
            color_hex     TEXT NOT NULL DEFAULT '#F59E0B',
            is_collecting INTEGER NOT NULL DEFAULT 0,
            sort_order    INTEGER NOT NULL DEFAULT 0
        );
        """)
        // ALTER TABLE isn't idempotent — guard it so a partially-applied
        // migration can always be retried safely.
        let hasColumn = scalarInt("SELECT COUNT(*) FROM pragma_table_info('items') WHERE name = 'category_id'") ?? 0
        if hasColumn == 0 {
            exec("ALTER TABLE items ADD COLUMN category_id TEXT")
        }
        exec("""
        CREATE INDEX IF NOT EXISTS idx_items_category ON items(category_id) WHERE category_id IS NOT NULL;
        PRAGMA user_version = 2;
        """)
    }

    private func migrateToV1() {
        exec("""
        CREATE TABLE IF NOT EXISTS items (
            id            TEXT NOT NULL UNIQUE,
            kind          INTEGER NOT NULL,           -- 0 text, 1 image, 2 files
            text          TEXT,
            image_data    BLOB,                       -- full PNG if small, else thumbnail
            image_path    TEXT,                       -- content-addressed file for large images
            file_paths    TEXT,                       -- JSON array for kind=2
            content_hash  TEXT NOT NULL,
            copied_at     REAL NOT NULL,
            pinned        INTEGER NOT NULL DEFAULT 0,
            source_bundle TEXT,
            source_name   TEXT,
            rtf           BLOB,
            html          BLOB,
            link_title    TEXT,
            link_icon     BLOB
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_items_hash ON items(content_hash);
        CREATE INDEX IF NOT EXISTS idx_items_copied ON items(copied_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_pinned ON items(pinned) WHERE pinned = 1;

        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
            text, link_title,
            content='items', content_rowid='rowid',
            tokenize='trigram'
        );

        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
            INSERT INTO items_fts(rowid, text, link_title)
            VALUES (new.rowid, coalesce(new.text,''), coalesce(new.link_title,''));
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text, link_title)
            VALUES ('delete', old.rowid, coalesce(old.text,''), coalesce(old.link_title,''));
        END;
        CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE OF text, link_title ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text, link_title)
            VALUES ('delete', old.rowid, coalesce(old.text,''), coalesce(old.link_title,''));
            INSERT INTO items_fts(rowid, text, link_title)
            VALUES (new.rowid, coalesce(new.text,''), coalesce(new.link_title,''));
        END;

        PRAGMA user_version = 1;
        """)
    }

    // MARK: - Legacy JSON migration

    private func migrateLegacyJSONIfPresent() {
        let jsonURL = dirURL.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }

        log.info("migrating \(decoded.count) items from history.json")
        exec("BEGIN")
        // Oldest first so copied_at ordering survives.
        for item in decoded.reversed() {
            _ = upsert(item)
        }
        exec("COMMIT")
        let backupURL = dirURL.appendingPathComponent("history.json.migrated")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: jsonURL, to: backupURL)
    }

    // MARK: - Hashing & image files

    static func contentHash(of item: ClipboardItem) -> String {
        var hasher = SHA256()
        switch item.content {
        case .text(let s):
            hasher.update(data: Data("t:".utf8))
            hasher.update(data: Data(s.utf8))
        case .image(let d):
            hasher.update(data: Data("i:".utf8))
            hasher.update(data: d)
        case .fileURLs(let paths):
            hasher.update(data: Data("f:".utf8))
            hasher.update(data: Data(paths.joined(separator: "\u{0}").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// For large images: write full PNG to a content-addressed file, return
    /// (thumbnailPNG, relativePath). Small images return (full, nil).
    private func prepareImageStorage(fullPNG: Data, hash: String) -> (inDB: Data, path: String?) {
        guard fullPNG.count > Self.imageFileThreshold else { return (fullPNG, nil) }
        let filename = hash + ".png"
        let fileURL = imagesDirURL.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? fullPNG.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
        let thumb = Self.thumbnailPNG(from: fullPNG, maxDimension: 320) ?? fullPNG
        return (thumb, filename)
    }

    static func thumbnailPNG(from pngData: Data, maxDimension: CGFloat) -> Data? {
        guard let image = NSImage(data: pngData) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        if scale >= 1 { return pngData }
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Writes

    /// Insert or, if identical content exists, refresh its recency. Returns the
    /// stored item (existing row's identity wins on dedup).
    func upsert(_ item: ClipboardItem) -> ClipboardItem {
        let hash = Self.contentHash(of: item)

        if var existing = fetchOne(where: "content_hash = ?", binds: [.text(hash)]) {
            existing.copiedAt = item.copiedAt
            existing.sourceAppBundleID = item.sourceAppBundleID
            existing.sourceAppName = item.sourceAppName
            // Re-copying trashed content rescues it from the Trash.
            run("UPDATE items SET copied_at = ?, source_bundle = ?, source_name = ?, deleted_at = NULL WHERE content_hash = ?",
                [.real(item.copiedAt.timeIntervalSince1970),
                 .textOpt(item.sourceAppBundleID), .textOpt(item.sourceAppName), .text(hash)])
            return existing
        }

        var stored = item
        var imageBlob: Data?
        var imagePath: String?
        var text: String?
        var filePathsJSON: String?
        let kind: Int

        switch item.content {
        case .text(let s):
            kind = 0; text = s
        case .image(let d):
            kind = 1
            let prepared = prepareImageStorage(fullPNG: d, hash: hash)
            imageBlob = prepared.inDB
            imagePath = prepared.path
            if prepared.path != nil {
                stored.content = .image(prepared.inDB) // memory holds the thumbnail
                stored.imageFile = prepared.path
            }
        case .fileURLs(let paths):
            kind = 2
            filePathsJSON = String(data: (try? JSONEncoder().encode(paths)) ?? Data("[]".utf8),
                                   encoding: .utf8)
        }

        run("""
        INSERT INTO items (id, kind, text, image_data, image_path, file_paths, content_hash,
                           copied_at, pinned, source_bundle, source_name, rtf, html, link_title, link_icon, category_id)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, [
            .text(item.id.uuidString), .int(kind), .textOpt(text),
            .blobOpt(imageBlob), .textOpt(imagePath), .textOpt(filePathsJSON),
            .text(hash), .real(item.copiedAt.timeIntervalSince1970),
            .int(item.isPinned ? 1 : 0),
            .textOpt(item.sourceAppBundleID), .textOpt(item.sourceAppName),
            .blobOpt(item.rtfData), .blobOpt(item.htmlData),
            .textOpt(item.linkTitle), .blobOpt(item.linkIconPNG),
            .textOpt(item.categoryID?.uuidString),
        ])
        return stored
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        run("UPDATE items SET pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .text(id.uuidString)])
    }

    func setLinkMetadata(id: UUID, title: String?, iconPNG: Data?) {
        run("UPDATE items SET link_title = ?, link_icon = ? WHERE id = ?",
            [.textOpt(title), .blobOpt(iconPNG), .text(id.uuidString)])
    }

    /// Quick edit: replace a text item's content in place. Recomputes the
    /// content hash; the FTS index updates via trigger. If editing makes the
    /// text identical to another existing item, the edit still wins — the
    /// other row keeps its own identity (hash uniqueness is relaxed to
    /// "best effort" here by suffixing on conflict).
    func updateText(id: UUID, newText: String) {
        var probe = ClipboardItem(content: .text(newText))
        probe.restoreIdentity(id: id, copiedAt: Date(), isPinned: false)
        var hash = Self.contentHash(of: probe)
        if let clash = fetchOne(where: "content_hash = ? AND id != ?",
                                binds: [.text(hash), .text(id.uuidString)]), clash.id != id {
            hash += "-edited-" + id.uuidString.prefix(8)
        }
        run("UPDATE items SET text = ?, content_hash = ?, rtf = NULL, html = NULL, link_title = NULL, link_icon = NULL WHERE id = ?",
            [.text(newText), .text(hash), .text(id.uuidString)])
    }

    // MARK: - Categories

    func setCategory(itemID: UUID, categoryID: UUID?) {
        run("UPDATE items SET category_id = ? WHERE id = ?",
            [.textOpt(categoryID?.uuidString), .text(itemID.uuidString)])
    }

    func setOCRText(id: UUID, text: String?) {
        run("UPDATE items SET ocr_text = ? WHERE id = ?",
            [.textOpt(text), .text(id.uuidString)])
    }

    func fetchCategories() -> [ClipCategory] {
        var out: [ClipCategory] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, name, color_hex, is_collecting, sort_order FROM categories ORDER BY sort_order, name", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0),
                  let id = UUID(uuidString: String(cString: idC)),
                  let nameC = sqlite3_column_text(stmt, 1),
                  let colorC = sqlite3_column_text(stmt, 2) else { continue }
            out.append(ClipCategory(id: id,
                                    name: String(cString: nameC),
                                    colorHex: String(cString: colorC),
                                    isCollecting: sqlite3_column_int(stmt, 3) == 1,
                                    sortOrder: Int(sqlite3_column_int(stmt, 4))))
        }
        return out
    }

    func saveCategory(_ category: ClipCategory) {
        run("""
        INSERT INTO categories (id, name, color_hex, is_collecting, sort_order)
        VALUES (?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name, color_hex = excluded.color_hex,
            is_collecting = excluded.is_collecting, sort_order = excluded.sort_order
        """, [.text(category.id.uuidString), .text(category.name), .text(category.colorHex),
              .int(category.isCollecting ? 1 : 0), .int(category.sortOrder)])
    }

    /// Only one category may collect at a time.
    func setCollecting(categoryID: UUID?) {
        run("UPDATE categories SET is_collecting = 0", [])
        if let categoryID {
            run("UPDATE categories SET is_collecting = 1 WHERE id = ?", [.text(categoryID.uuidString)])
        }
    }

    func deleteCategory(id: UUID) {
        run("UPDATE items SET category_id = NULL WHERE category_id = ?", [.text(id.uuidString)])
        run("DELETE FROM categories WHERE id = ?", [.text(id.uuidString)])
    }

    func fetchItems(categoryID: UUID, limit: Int = 2_000) -> [ClipboardItem] {
        query("SELECT * FROM items WHERE category_id = ? AND deleted_at IS NULL ORDER BY pinned DESC, copied_at DESC LIMIT ?",
              [.text(categoryID.uuidString), .int(limit)])
    }

    func fetchItem(id: UUID) -> ClipboardItem? {
        fetchOne(where: "id = ? AND deleted_at IS NULL", binds: [.text(id.uuidString)])
    }

    /// Soft delete: moves the item to the Trash. Image files stay on disk
    /// until the trash entry is purged.
    func delete(id: UUID) {
        run("UPDATE items SET deleted_at = ? WHERE id = ?",
            [.real(Date().timeIntervalSince1970), .text(id.uuidString)])
    }

    func restore(id: UUID) {
        run("UPDATE items SET deleted_at = NULL WHERE id = ?", [.text(id.uuidString)])
    }

    /// Permanent removal — only reachable from the Trash UI or the purge sweep.
    func purge(id: UUID) {
        deleteImageFiles(where: "id = ?", binds: [.text(id.uuidString)])
        run("DELETE FROM items WHERE id = ?", [.text(id.uuidString)])
    }

    func emptyTrash() {
        deleteImageFiles(where: "deleted_at IS NOT NULL", binds: [])
        run("DELETE FROM items WHERE deleted_at IS NOT NULL", [])
    }

    /// Purges trash entries older than `days`.
    func purgeExpiredTrash(olderThanDays days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        deleteImageFiles(where: "deleted_at IS NOT NULL AND deleted_at < ?", binds: [.real(cutoff)])
        run("DELETE FROM items WHERE deleted_at IS NOT NULL AND deleted_at < ?", [.real(cutoff)])
    }

    func fetchTrash(limit: Int = 2_000) -> [ClipboardItem] {
        query("SELECT * FROM items WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT ?",
              [.int(limit)])
    }

    func trashCount() -> Int {
        scalarInt("SELECT COUNT(*) FROM items WHERE deleted_at IS NOT NULL") ?? 0
    }

    /// Clear All: soft — everything lands in the Trash, fully recoverable.
    func clear(keepPinned: Bool) {
        let condition = keepPinned ? "pinned = 0" : "1 = 1"
        run("UPDATE items SET deleted_at = ? WHERE deleted_at IS NULL AND (\(condition))",
            [.real(Date().timeIntervalSince1970)])
    }

    /// Retention sweep: 0 means "keep forever" for every knob. Expired items
    /// go to the Trash (30-day safety net) rather than vanishing.
    func applyRetention(maxItems: Int, maxAgeDays: Int, imageMaxAgeDays: Int) {
        let now = Date().timeIntervalSince1970
        if maxAgeDays > 0 {
            let cutoff = now - Double(maxAgeDays) * 86_400
            run("UPDATE items SET deleted_at = ? WHERE deleted_at IS NULL AND pinned = 0 AND copied_at < ?",
                [.real(now), .real(cutoff)])
        }
        if imageMaxAgeDays > 0 {
            let cutoff = now - Double(imageMaxAgeDays) * 86_400
            run("UPDATE items SET deleted_at = ? WHERE deleted_at IS NULL AND pinned = 0 AND kind = 1 AND copied_at < ?",
                [.real(now), .real(cutoff)])
        }
        if maxItems > 0 {
            run("""
                UPDATE items SET deleted_at = \(now) WHERE deleted_at IS NULL AND pinned = 0 AND rowid NOT IN
                (SELECT rowid FROM items WHERE deleted_at IS NULL AND pinned = 0 ORDER BY copied_at DESC LIMIT \(maxItems))
                """, [])
        }
    }

    private func deleteImageFiles(where condition: String, binds: [Bind]) {
        let paths = column("SELECT image_path FROM items WHERE image_path IS NOT NULL AND (\(condition))", binds)
        for path in paths {
            try? FileManager.default.removeItem(at: imagesDirURL.appendingPathComponent(path))
        }
    }

    func compact() {
        exec("VACUUM")
        // VACUUM may renumber implicit rowids; rebuild the external-content
        // FTS index so search never desyncs from the items table.
        exec("INSERT INTO items_fts(items_fts) VALUES('rebuild')")
    }

    // MARK: - Reads

    /// Working set: all pinned + most recent unpinned, newest first, pinned on top.
    func fetchWorkingSet(recentLimit: Int) -> [ClipboardItem] {
        query("""
        SELECT * FROM items WHERE pinned = 1 AND deleted_at IS NULL
        UNION ALL
        SELECT * FROM (SELECT * FROM items WHERE pinned = 0 AND deleted_at IS NULL ORDER BY copied_at DESC LIMIT ?)
        ORDER BY pinned DESC, copied_at DESC
        """, [.int(recentLimit)])
    }

    /// Substring search over the full history. Trigram FTS for queries of 3+
    /// characters; LIKE fallback below that (still indexed by recency).
    func search(_ rawQuery: String, limit: Int = 500) -> [ClipboardItem] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        if q.count >= 3 {
            let escaped = q.replacingOccurrences(of: "\"", with: "\"\"")
            return query("""
            SELECT items.* FROM items_fts
            JOIN items ON items.rowid = items_fts.rowid
            WHERE items_fts MATCH '"' || ? || '"' AND items.deleted_at IS NULL
            ORDER BY items.pinned DESC, items.copied_at DESC LIMIT ?
            """, [.text(escaped), .int(limit)])
        } else {
            let pattern = "%" + q
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            return query("""
            SELECT * FROM items
            WHERE deleted_at IS NULL
              AND (text LIKE ? ESCAPE '\\' OR link_title LIKE ? ESCAPE '\\' OR ocr_text LIKE ? ESCAPE '\\')
            ORDER BY pinned DESC, copied_at DESC LIMIT ?
            """, [.text(pattern), .text(pattern), .text(pattern), .int(limit)])
        }
    }

    func loadFullImage(for item: ClipboardItem) -> Data? {
        guard let file = item.imageFile else {
            if case .image(let d) = item.content { return d }
            return nil
        }
        return try? Data(contentsOf: imagesDirURL.appendingPathComponent(file))
    }

    // MARK: - Stats

    struct Stats {
        var totalItems: Int
        var pinnedItems: Int
        var dbBytes: Int64
        var imageFileBytes: Int64
    }

    func stats() -> Stats {
        let total = scalarInt("SELECT COUNT(*) FROM items WHERE deleted_at IS NULL") ?? 0
        let pinned = scalarInt("SELECT COUNT(*) FROM items WHERE pinned = 1 AND deleted_at IS NULL") ?? 0
        var dbBytes: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path + suffix)
            dbBytes += (attrs?[.size] as? Int64) ?? 0
        }
        var imageBytes: Int64 = 0
        if let files = try? FileManager.default.contentsOfDirectory(at: imagesDirURL,
                                                                    includingPropertiesForKeys: [.fileSizeKey]) {
            for f in files {
                imageBytes += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return Stats(totalItems: total, pinnedItems: pinned, dbBytes: dbBytes, imageFileBytes: imageBytes)
    }

    // MARK: - Row mapping

    private func item(from stmt: OpaquePointer?) -> ClipboardItem? {
        func text(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        func blob(_ i: Int32) -> Data? {
            guard let p = sqlite3_column_blob(stmt, i) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
        }
        // Column order matches CREATE TABLE.
        guard let idStr = text(0), let id = UUID(uuidString: idStr) else { return nil }
        let kind = sqlite3_column_int(stmt, 1)

        let content: ClipContent
        switch kind {
        case 0:
            content = .text(text(2) ?? "")
        case 1:
            content = .image(blob(3) ?? Data())
        default:
            let json = text(5) ?? "[]"
            let paths = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
            content = .fileURLs(paths)
        }

        var item = ClipboardItem(content: content,
                                 sourceAppBundleID: text(9),
                                 sourceAppName: text(10),
                                 rtfData: blob(11),
                                 htmlData: blob(12))
        item.restoreIdentity(id: id,
                             copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                             isPinned: sqlite3_column_int(stmt, 8) == 1)
        item.imageFile = text(4)
        item.linkTitle = text(13)
        item.linkIconPNG = blob(14)
        // category_id was added in schema v2 as column 15.
        if sqlite3_column_count(stmt) > 15, let cat = text(15) {
            item.categoryID = UUID(uuidString: cat)
        }
        // ocr_text was added in schema v3 as column 16.
        if sqlite3_column_count(stmt) > 16 {
            item.ocrText = text(16)
        }
        return item
    }

    // MARK: - SQLite plumbing

    enum Bind {
        case int(Int)
        case real(Double)
        case text(String)
        case textOpt(String?)
        case blobOpt(Data?)
    }

    private func bindAll(_ stmt: OpaquePointer?, _ binds: [Bind]) {
        for (i, bind) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch bind {
            case .int(let v): sqlite3_bind_int64(stmt, idx, Int64(v))
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .textOpt(let v):
                if let v { sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT) }
                else { sqlite3_bind_null(stmt, idx) }
            case .blobOpt(let v):
                if let v {
                    _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
                } else { sqlite3_bind_null(stmt, idx) }
            }
        }
    }

    @discardableResult
    private func run(_ sql: String, _ binds: [Bind]) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("prepare failed: \(self.lastError()) — \(sql)")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        bindAll(stmt, binds)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            log.error("step failed (\(rc)): \(self.lastError())")
            return false
        }
        return true
    }

    private func query(_ sql: String, _ binds: [Bind]) -> [ClipboardItem] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("prepare failed: \(self.lastError()) — \(sql)")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        bindAll(stmt, binds)
        var out: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = item(from: stmt) { out.append(item) }
        }
        return out
    }

    private func fetchOne(where condition: String, binds: [Bind]) -> ClipboardItem? {
        query("SELECT * FROM items WHERE \(condition) LIMIT 1", binds).first
    }

    private func column(_ sql: String, _ binds: [Bind]) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindAll(stmt, binds)
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }

    private func scalarInt(_ sql: String) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            log.error("exec failed: \(message)")
            sqlite3_free(err)
        }
    }

    private func lastError() -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }
}
