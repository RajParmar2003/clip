import AppKit
import LinkPresentation

/// Fetches page title + icon for copied URLs using Apple's LinkPresentation
/// framework. Only runs when the user has opted in (Settings → General →
/// "Fetch link previews") — it's the one feature that touches the network,
/// so it ships off by default.
final class LinkMetadataFetcher {
    static let shared = LinkMetadataFetcher()
    private var inFlight = Set<UUID>()

    func enrich(_ item: ClipboardItem, in store: ClipboardStore) {
        guard Preferences.shared.fetchLinkPreviews,
              let url = item.asURL,
              item.linkTitle == nil,
              !inFlight.contains(item.id) else { return }
        inFlight.insert(item.id)

        let provider = LPMetadataProvider()
        provider.timeout = 10
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            guard let metadata else {
                DispatchQueue.main.async { self?.inFlight.remove(item.id) }
                return
            }
            let title = metadata.title

            func finish(_ iconPNG: Data?) {
                DispatchQueue.main.async {
                    self?.inFlight.remove(item.id)
                    store.applyLinkMetadata(itemID: item.id, title: title, iconPNG: iconPNG)
                }
            }

            guard let iconProvider = metadata.iconProvider else {
                finish(nil)
                return
            }
            iconProvider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else {
                    finish(nil)
                    return
                }
                finish(Self.pngThumbnail(of: image, maxDimension: 64))
            }
        }
    }

    /// Downscale to a small PNG so history stays light.
    private static func pngThumbnail(of image: NSImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
