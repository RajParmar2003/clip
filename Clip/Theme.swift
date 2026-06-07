import SwiftUI

/// Design tokens for the v0.7 premium redesign. One place for the radii,
/// spacing, and the glyph-tile tints so popup and window stay identical.
enum Theme {
    // Corner radii
    static let cardRadius: CGFloat = 13
    static let tileRadius: CGFloat = 10
    static let fieldRadius: CGFloat = 11
    static let panelRadius: CGFloat = 18

    // Spacing
    static let rowGap: CGFloat = 5
    static let cardPaddingH: CGFloat = 12
    static let cardPaddingV: CGFloat = 11
    static let tileSize: CGFloat = 38

    // Type sizes — deliberately only two for content.
    static let titleSize: CGFloat = 14.5
    static let metaSize: CGFloat = 12
}

/// What kind of clip a row represents — drives the glyph + tile tint.
enum ClipGlyph {
    case image, link, text, code, files

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .link: return "link"
        case .text: return "quote.opening"
        case .code: return "terminal"
        case .files: return "doc"
        }
    }

    /// Images get the signature amber wash; everything else stays neutral —
    /// restraint is the personality.
    var tint: Color {
        switch self {
        case .image: return Color(hex: "#BD7D12") ?? .orange
        default: return .secondary
        }
    }

    var tileFill: Color {
        switch self {
        case .image: return (Color(hex: "#BD7D12") ?? .orange).opacity(0.16)
        default: return Color.primary.opacity(0.06)
        }
    }

    /// Classify a clip into a glyph bucket.
    static func of(_ item: ClipboardItem) -> ClipGlyph {
        switch item.content {
        case .image: return .image
        case .fileURLs: return .files
        case .text(let s):
            if item.asURL != nil { return .link }
            // Heuristic: leading shell/code markers → code styling (mono).
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("cd ") || t.hasPrefix("git ") || t.hasPrefix("$ ")
                || t.hasPrefix("sudo ") || t.hasPrefix("npm ") || t.hasPrefix("brew ") {
                return .code
            }
            return .text
        }
    }
}

/// The rounded glyph tile that anchors every clip card.
struct GlyphTile: View {
    let glyph: ClipGlyph

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            .fill(glyph.tileFill)
            .frame(width: Theme.tileSize, height: Theme.tileSize)
            .overlay(
                Image(systemName: glyph.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(glyph.tint)
            )
    }
}
