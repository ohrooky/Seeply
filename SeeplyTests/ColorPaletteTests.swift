import XCTest
#if canImport(SeeplyCore)
@testable import SeeplyCore
#else
@testable import Seeply
#endif

final class ColorPaletteTests: XCTestCase {
    func testUniformImageProducesOneExactColor() {
        let result = PaletteExtractor.extract(Array(repeating: PalettePixel(72, 128, 173), count: 100))
        XCTAssertEqual(result.colors.count, 1)
        XCTAssertEqual(result.colors.first?.hex, "#4880AD")
        XCTAssertEqual(result.colors.first?.fraction, 1)
    }

    func testFourSeparatedColorsRemainDistinct() {
        let pixels = [PalettePixel(255, 0, 0), PalettePixel(0, 255, 0), PalettePixel(0, 0, 255), PalettePixel(255, 255, 255)]
        let result = PaletteExtractor.extract(pixels)
        XCTAssertEqual(Set(result.colors.map(\.hex)), Set(["#FF0000", "#00FF00", "#0000FF", "#FFFFFF"]))
        XCTAssertEqual(result.colors.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1e-9)
    }

    func testTransparentPixelsDoNotContribute() {
        let pixels = Array(repeating: PalettePixel(255, 0, 0, alpha: 0), count: 100) + [PalettePixel(0, 255, 0)]
        XCTAssertEqual(PaletteExtractor.extract(pixels).colors.map(\.hex), ["#00FF00"])
        XCTAssertTrue(PaletteExtractor.extract([]).colors.isEmpty)
        XCTAssertTrue(PaletteExtractor.extract([PalettePixel(0, 0, 0, alpha: 0)]).colors.isEmpty)
        XCTAssertTrue(PaletteExtractor.extract(pixels, colorCount: 0).colors.isEmpty)
    }

    func testPremultipliedPixelsAreUnpremultiplied() {
        let result = PaletteExtractor.extract([PalettePixel(128, 0, 0, alpha: 128)])
        XCTAssertEqual(result.colors.first?.hex, "#FF0000")
    }

    func testDoesNotInventFourColorsForTwoColorImage() {
        let result = PaletteExtractor.extract([PalettePixel(0, 0, 0), PalettePixel(255, 255, 255)])
        XCTAssertEqual(result.colors.count, 2)
        XCTAssertEqual(Set(result.colors.map(\.hex)), Set(["#000000", "#FFFFFF"]))
    }

    func testOutputIsDeterministicForReorderedInput() {
        let pixels: [PalettePixel] = (0..<240).map { (index: Int) -> PalettePixel in
            let red = UInt8(index)
            let green = UInt8((index * 3) % 256)
            let blue = UInt8((index * 7) % 256)
            return PalettePixel(red, green, blue)
        }
        XCTAssertEqual(PaletteExtractor.extract(pixels), PaletteExtractor.extract(Array(pixels.reversed())))
    }

    func testSmallSaturatedAccentIsRepresented() {
        let pixels = Array(repeating: PalettePixel(238, 235, 229), count: 500)
            + Array(repeating: PalettePixel(40, 69, 57), count: 200)
            + Array(repeating: PalettePixel(58, 86, 75), count: 100)
            + Array(repeating: PalettePixel(176, 152, 119), count: 180)
            + Array(repeating: PalettePixel(221, 43, 33), count: 20)
        let result = PaletteExtractor.extract(pixels)
        XCTAssertEqual(result.colors.count, 4)
        XCTAssertTrue(result.colors.contains { $0.red > 180 && $0.green < 90 && $0.blue < 90 })
    }
}
