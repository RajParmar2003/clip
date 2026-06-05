import AppKit
import Foundation

enum ClipContent: Codable, Equatable {
    case text(String)
    case image(Data)          // PNG data
    case fileURLs([String])   // file paths

    var isText: Bool { if case .text = self { return true }; return false }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    private(set) var id: UUID
    var content: ClipContent
    var copiedAt: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var isPinned: Bool
    /// RTF/HTML alongside plain text, so we can paste with formatting.
    var rtfData: Data?
    var htmlData: Data?
    /// Filled in asynchronously for URL items when link previews are enabled.
    var linkTitle: String?
    var linkIconPNG: Data?
    /// For large images stored on disk: filename inside the images directory.
    /// When set, `content` holds only a thumbnail; paste loads the full file.
    var imageFile: String?
    /// Category assignment (Phase 3).
    var categoryID: UUID?

    init(content: ClipContent,
         sourceAppBundleID: String? = nil,
         sourceAppName: String? = nil,
         rtfData: Data? = nil,
         htmlData: Data? = nil) {
        self.id = UUID()
        self.content = content
        self.copiedAt = Date()
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.isPinned = false
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.linkTitle = nil
        self.linkIconPNG = nil
        self.imageFile = nil
        self.categoryID = nil
    }

    /// Used by the storage engine when rehydrating a row: a DB row keeps the
    /// identity it was stored with, not a freshly generated one.
    mutating func restoreIdentity(id: UUID, copiedAt: Date, isPinned: Bool) {
        self.id = id
        self.copiedAt = copiedAt
        self.isPinned = isPinned
    }

    /// If this item is a single copied http(s) URL, returns it.
    var asURL: URL? {
        guard case .text(let s) = content else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    var previewTitle: String {
        if let linkTitle, !linkTitle.isEmpty { return linkTitle }
        switch content {
        case .text(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
            return firstLine.isEmpty ? "(whitespace)" : String(firstLine.prefix(120))
        case .image:
            return "Image"
        case .fileURLs(let paths):
            if paths.count == 1 {
                return (paths[0] as NSString).lastPathComponent
            }
            return "\(paths.count) files"
        }
    }

    var searchableText: String {
        switch content {
        case .text(let s): return s
        case .image: return "image"
        case .fileURLs(let paths): return paths.joined(separator: " ")
        }
    }

    var characterCount: Int? {
        if case .text(let s) = content { return s.count }
        return nil
    }

    func nsImage() -> NSImage? {
        if case .image(let data) = content { return NSImage(data: data) }
        return nil
    }
}
