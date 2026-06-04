import AppKit
import Foundation

enum ClipContent: Codable, Equatable {
    case text(String)
    case image(Data)          // PNG data
    case fileURLs([String])   // file paths

    var isText: Bool { if case .text = self { return true }; return false }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
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
