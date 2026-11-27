import XCTest
import AppKit
@testable import Seeply

final class ImageIOTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) throws -> ImageItem {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return ImageItem(url: url)
    }

    func testExifOrientationIsAppliedToPreviewAndSourceDimensions() throws {
        let image = try ImageIODecoder.decode(fixture("orientation6", "jpg"), maxDimension: 200)
        XCTAssertEqual(image.sourcePixels, CGSize(width: 40, height: 80))
        XCTAssertEqual(image.image.width, 40)
        XCTAssertEqual(image.image.height, 80)
        XCTAssertNotNil(image.image.colorSpace)
    }

    func testReadableExifValuesAndGPS() throws {
        let metadata = try MetadataService.read(fixture("orientation6", "jpg"))
        XCTAssertEqual(metadata.camera, "Luma Test Fixture Camera")
        XCTAssertEqual(metadata.lens, "Fixture 35 mm")
        XCTAssertEqual(try XCTUnwrap(metadata.exposure), 1.0 / 250, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(metadata.aperture), 1.4, accuracy: 0.001)
        XCTAssertEqual(metadata.iso, 100)
        XCTAssertTrue(metadata.sections.contains { $0.id == "Location" })
        XCTAssertTrue(metadata.copyText(language: .english).contains("2026-01-02"))
        XCTAssertTrue(metadata.copyText(language: .english).contains("Camera:"))
        XCTAssertTrue(metadata.copyText(language: .traditionalChinese).contains("相機："))
    }

    func testImageWithoutExifHasNoFabricatedCameraData() throws {
        let metadata = try MetadataService.read(fixture("plain", "png"))
        XCTAssertNil(metadata.camera)
        XCTAssertNil(metadata.lens)
        XCTAssertEqual(metadata.summary, "")
        XCTAssertFalse(metadata.sections.contains { $0.id == "Location" })
    }

    func testCorruptedImageReturnsAnError() throws {
        let item = try fixture("broken", "jpg")
        XCTAssertThrowsError(try ImageIODecoder.decode(item, maxDimension: 200))
    }

    func testFileNamesUseFinderStyleNaturalOrdering() {
        let items = ["image10.jpg", "image2.jpg", "image1.jpg"].map {
            ImageItem(url: URL(fileURLWithPath: "/tmp/" + $0))
        }
        XCTAssertEqual(FileAccess.sorted(items).map(\.name), ["image1.jpg", "image2.jpg", "image10.jpg"])
    }
}

@MainActor
final class ImageCanvasDrawingTests: XCTestCase {
    private let bitmapSize = 160
    private let canvasBounds = CGRect(x: 48, y: 48, width: 64, height: 64)

    private func bitmap(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
    }

    private func largeRedPreview() throws -> DecodedImage {
        let source = try bitmap(width: 1, height: 1)
        source.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        source.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return DecodedImage(image: try XCTUnwrap(source.makeImage()),
            sourcePixels: CGSize(width: 7008, height: 4672), requestedDimension: 1, resolutionLimited: false)
    }

    private func viewport() -> ViewportController {
        let viewport = ViewportController()
        viewport.setImage(CGSize(width: 7008, height: 4672), reset: true)
        viewport.setViewport(canvasBounds.size, scale: 2)
        viewport.actualSize()
        return viewport
    }

    private func rgba(_ context: CGContext, x: Int, y: Int) throws -> [UInt8] {
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (0..<4).map { data[offset + $0] }
    }

    func testLarge100PercentImageCannotOverwriteSurroundingControls() async throws {
        let image = try largeRedPreview()
        let viewport = viewport()
        let pans = [CGSize.zero, CGSize(width: 10_000, height: 10_000),
                    CGSize(width: -10_000, height: 10_000), CGSize(width: -10_000, height: -10_000),
                    CGSize(width: 10_000, height: -10_000)]
        for rotation in 0..<4 {
            if rotation > 0 { viewport.rotate() }
            for pan in pans {
                viewport.translate(x: pan.width - viewport.pan.width, y: pan.height - viewport.pan.height)
                let context = try bitmap(width: bitmapSize, height: bitmapSize)
                context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: CGFloat(bitmapSize), height: CGFloat(bitmapSize)))
                ImageCanvas.drawImage(image, in: canvasBounds, viewport: viewport, context: context)

                XCTAssertEqual(try rgba(context, x: 80, y: 80), [255, 0, 0, 255], "The image is still drawn at 100%")
                for point in [(80, 16), (80, 144), (16, 80), (144, 80)] {
                    XCTAssertEqual(try rgba(context, x: point.0, y: point.1), [0, 255, 0, 255],
                        "Pixels outside the canvas must survive rotation \(rotation), pan \(pan)")
                }
                XCTAssertEqual(viewport.zoom, 1)
                XCTAssertFalse(viewport.isFitted)
            }
        }
    }

    func testImageDrawingRestoresTheClipAndTransformForFollowingControls() async throws {
        let context = try bitmap(width: bitmapSize, height: bitmapSize)
        let viewport = viewport()
        viewport.rotate()
        ImageCanvas.drawImage(try largeRedPreview(), in: canvasBounds, viewport: viewport, context: context)
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(bitmapSize), height: CGFloat(bitmapSize)))
        for point in [(80, 80), (80, 16), (80, 144), (16, 80), (144, 80)] {
            XCTAssertEqual(try rgba(context, x: point.0, y: point.1), [0, 0, 255, 255],
                "Later controls must not inherit the image's clipping region or transform")
        }
    }
}
