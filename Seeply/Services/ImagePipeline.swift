import Foundation
import CoreGraphics
import ImageIO

enum ImageIODecoder {
    static func decode(_ item: ImageItem, maxDimension: Int, pixelBudget: Double = 64_000_000) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ViewerError.unreadable(item.name)
        }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] ?? [:]
        let width = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? 1
        let height = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? 1
        let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        let transpose = [5, 6, 7, 8].contains(orientation)
        let pixels = CGSize(width: transpose ? height : width, height: transpose ? width : height)
        let longest = max(width, height)
        let safetyScale = min(1, sqrt(pixelBudget / max(1, width * height)))
        let limit = max(1, min(maxDimension, Int(ceil(longest * safetyScale))))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw ViewerError.unsupported(item.name)
        }
        // ImageIO preserves the source image's color space in the returned CGImage.
        return DecodedImage(image: image, sourcePixels: pixels, requestedDimension: maxDimension,
                            resolutionLimited: Double(limit) + 1 < min(Double(maxDimension), longest))
    }
}

actor ImagePipeline {
    static let shared = ImagePipeline()
    private enum Key: Hashable, Sendable {
        case image(String, Int)
        case thumbnail(String)
    }
    private var images: CostLRUCache<Key, DecodedImage>
    private var thumbnails = CostLRUCache<String, DecodedImage>(budget: 40 * 1024 * 1024)
    private let requests = SharedRequestPool<Key, DecodedImage>()
    private let worker = WorkQueue(name: "app.seeply.decode", concurrency: 2, qos: .userInitiated)
    private let thumbnailWorker = WorkQueue(name: "app.seeply.thumbnails", concurrency: 2, qos: .utility)
    private let pixelBudget: Double
    private var cacheGeneration: UInt64 = 0

    private init() {
        let budget = Int(min(512 * 1024 * 1024, max(128 * 1024 * 1024, ProcessInfo.processInfo.physicalMemory / 8)))
        images = CostLRUCache(budget: budget)
        pixelBudget = Double(min(64_000_000, budget / 8))
    }

    func image(for item: ImageItem, dimension: Int, prefetch: Bool = false) async throws -> DecodedImage {
        try Task.checkCancellation()
        let bucket = max(512, Int(ceil(Double(dimension) / 512)) * 512)
        let key = Key.image(item.revision, bucket)
        if let cached = images.value(for: key) { return cached }
        let pixelBudget = self.pixelBudget
        let worker = self.worker
        let generation = cacheGeneration
        return try await requests.value(for: key) { [weak self] in
            if let cached = await self?.cachedImage(for: key) { return cached }
            let result = try await worker.run(priority: prefetch ? .veryLow : .veryHigh) {
                try ImageIODecoder.decode(item, maxDimension: bucket, pixelBudget: pixelBudget)
            }
            try Task.checkCancellation()
            await self?.storeImage(result, for: key, generation: generation)
            return result
        }
    }

    func thumbnail(for item: ImageItem) async throws -> DecodedImage {
        try Task.checkCancellation()
        if let cached = thumbnails.value(for: item.revision) { return cached }
        let worker = thumbnailWorker
        let generation = cacheGeneration
        return try await requests.value(for: .thumbnail(item.revision)) { [weak self] in
            if let cached = await self?.cachedThumbnail(for: item.revision) { return cached }
            let result = try await worker.run {
                try ImageIODecoder.decode(item, maxDimension: 400, pixelBudget: 400 * 400)
            }
            try Task.checkCancellation()
            await self?.storeThumbnail(result, revision: item.revision, generation: generation)
            return result
        }
    }

    private func cachedImage(for key: Key) -> DecodedImage? { images.value(for: key) }
    private func cachedThumbnail(for revision: String) -> DecodedImage? { thumbnails.value(for: revision) }

    private func storeImage(_ result: DecodedImage, for key: Key, generation: UInt64) {
        guard generation == cacheGeneration else { return }
        images.insert(result, for: key, cost: result.cost)
    }

    private func storeThumbnail(_ result: DecodedImage, revision: String, generation: UInt64) {
        guard generation == cacheGeneration else { return }
        thumbnails.insert(result, for: revision, cost: result.cost)
    }

    func clear() {
        cacheGeneration &+= 1
        images.removeAll()
        thumbnails.removeAll()
        // Active readers still receive their image; older jobs cannot refill a cleared cache.
    }
}
