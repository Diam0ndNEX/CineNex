import SwiftUI
import UIKit
import ImageIO

struct CachedPosterImage: View {
    let url: URL?
    let fallbackSymbol: String
    let symbolSize: CGFloat

    @StateObject private var loader = PosterImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: symbolSize, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .allowsHitTesting(false)
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
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  data.count <= 20_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_000,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                return
            }

            let decodedImage = UIImage(cgImage: thumbnail)
            Self.cache.setObject(decodedImage, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            image = decodedImage
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            image = nil
        }
    }
}
