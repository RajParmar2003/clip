import SwiftUI

/// One clip rendered as a premium card — the shared building block for the
/// popup and the window. Calm, two type sizes, glyph tile, category dot,
/// pin marker. Content-forward but restrained: images show a small thumbnail
/// inside the tile, never a full-width preview.
struct ClipCard: View {
    let item: ClipboardItem
    let category: ClipCategory?
    var isSelected: Bool = false
    var quickSlot: Int? = nil
    var isQueued: Bool = false

    private var glyph: ClipGlyph { ClipGlyph.of(item) }

    var body: some View {
        HStack(spacing: 12) {
            tile

            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewTitle)
                    .font(.system(size: Theme.titleSize,
                                  weight: .regular,
                                  design: glyph == .code ? .monospaced : .default))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if let category {
                        Circle()
                            .fill(category.color)
                            .frame(width: 6, height: 6)
                        Text(category.name)
                    }
                    Text(metaLine)
                }
                .font(.system(size: Theme.metaSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            trailing
        }
        .padding(.horizontal, Theme.cardPaddingH)
        .padding(.vertical, Theme.cardPaddingV)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.09) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var tile: some View {
        if glyph == .image, let img = item.nsImage() {
            // Small thumbnail lives inside the tile shape — never full-bleed.
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .fill(glyph.tileFill)
                .frame(width: Theme.tileSize, height: Theme.tileSize)
                .overlay(
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Theme.tileSize, height: Theme.tileSize)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                )
        } else {
            GlyphTile(glyph: glyph)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 7) {
            if let slot = quickSlot {
                Text("⌃⌥\(slot + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.purple)
            }
            if isQueued {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(glyph == .image ? glyph.tint : .orange)
            }
        }
    }

    private var metaLine: String {
        let app = item.sourceAppName
        let when = Self.relative(item.copiedAt)
        if let app, !app.isEmpty { return "\(app) · \(when)" }
        return when
    }

    private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 8 { return "just now" }
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
