import SwiftUI
import UIKit
import ImageIO

struct CachedPosterImage: View {
    let url: URL?
    let fallbackSymbol: String
    let symbolSize: CGFloat

    @StateObject private var loader = PosterImageLoader()

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: symbolSize, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: max(0, geometry.size.width), height: max(0, geometry.size.height))
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: url) {
            await loader.load(from: url)
        }
    }
}

@MainActor
private final class PosterImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 250
        cache.totalCostLimit = 60 * 1024 * 1024
        return cache
    }()

    static func clearMemoryCache() { cache.removeAllObjects() }

    func load(from url: URL?) async {
        image = nil
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            image = nil
            return
        }

        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            image = cachedImage
            return
        }

        image = nil
        do {
            let data = try await ArtworkDiskCache.shared.data(for: url)
            try Task.checkCancellation()
            guard let decoded = await PosterThumbnailDecoder.shared.decode(data) else {
                await ArtworkDiskCache.shared.invalidate(url)
                return
            }
            try Task.checkCancellation()
            let decodedImage = UIImage(cgImage: decoded.image)
            Self.cache.setObject(decodedImage, forKey: url as NSURL, cost: decoded.cost)
            image = decodedImage
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            image = nil
        }
    }
}

/// CGImage is immutable after construction and is safe to hand to the main actor.
private struct DecodedPosterThumbnail: @unchecked Sendable {
    let image: CGImage
    var cost: Int { image.bytesPerRow * image.height }
}

/// Serial decoding avoids decoding an entire poster shelf concurrently on startup.
private actor PosterThumbnailDecoder {
    static let shared = PosterThumbnailDecoder()

    func decode(_ data: Data) -> DecodedPosterThumbnail? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return DecodedPosterThumbnail(image: image)
    }
}

@MainActor
enum ArtworkCacheMaintenance {
    static func clear() async {
        PosterImageLoader.clearMemoryCache()
        await ArtworkDiskCache.shared.clear()
    }
}
