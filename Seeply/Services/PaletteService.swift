import Foundation
import CoreGraphics

actor PaletteService {
    static let shared = PaletteService()
    private var cache = CostLRUCache<String, PhotoPalette>(budget: 128)
    private let requests = SharedRequestPool<String, PhotoPalette>()
    private let worker = WorkQueue(name: "app.seeply.palette", concurrency: 1, qos: .utility)
    private var generation: UInt64 = 0

    func palette(for item: ImageItem, preview: DecodedImage) async throws -> PhotoPalette {
        try Task.checkCancellation()
        if let value = cache.value(for: item.revision) { return value }
        let worker = self.worker
        let generation = self.generation
        return try await requests.value(for: item.revision) { [weak self] in
            if let value = await self?.cached(item.revision) { return value }
            let value = try await worker.run { try Self.analyze(preview) }
            try Task.checkCancellation()
            await self?.store(value, revision: item.revision, generation: generation)
            return value
        }
    }

    private func cached(_ revision: String) -> PhotoPalette? { cache.value(for: revision) }
    private func store(_ value: PhotoPalette, revision: String, generation: UInt64) {
        guard generation == self.generation else { return }
        cache.insert(value, for: revision, cost: 1)
    }
    func clear() { generation &+= 1; cache.removeAll() }

    private static func analyze(_ preview: DecodedImage) throws -> PhotoPalette {
        let image = preview.image
        let ratio = min(1, 192 / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * ratio).rounded()))
        let height = max(1, Int((Double(image.height) * ratio).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw PaletteError.unavailable
        }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.clear(bounds)
        context.interpolationQuality = .high
        // Core Graphics converts the embedded source profile to the sRGB palette output.
        context.draw(image, in: bounds)
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw PaletteError.unavailable }
        var pixels: [PalettePixel] = []
        pixels.reserveCapacity(width * height)
        let stride = context.bytesPerRow
        withExtendedLifetime(context) {
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * stride + x * 4
                    pixels.append(PalettePixel(data[offset], data[offset + 1], data[offset + 2], alpha: data[offset + 3]))
                }
            }
        }
        return PaletteExtractor.extract(pixels)
    }
}

private enum PaletteError: PresentableError {
    case unavailable
    var displayText: DisplayText { .key("The color palette is temporarily unavailable for this photo.") }
}
