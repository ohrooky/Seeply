import XCTest
#if canImport(SeeplyCore)
@testable import SeeplyCore
#else
@testable import Seeply
#endif

final class ViewportGeometryTests: XCTestCase {
    func testRetinaFitAndActualPixelsAreDifferent() {
        let zoom = ViewportGeometry.fitZoom(imagePixels: CGSize(width: 6000, height: 4000),
            viewport: CGSize(width: 1000, height: 800), backingScale: 2, padding: 0, allowUpscaling: false)
        XCTAssertEqual(zoom, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(6000 * zoom / 2, 1000, accuracy: 0.0001)
    }

    func testSmallImagesAreNotUpscaledByDefault() {
        let zoom = ViewportGeometry.fitZoom(imagePixels: CGSize(width: 100, height: 100),
            viewport: CGSize(width: 1000, height: 800), backingScale: 2, padding: 0, allowUpscaling: false)
        XCTAssertEqual(zoom, 1)
    }

    func testCursorAnchorPreservesTheSameImageCoordinate() {
        let viewport = CGSize(width: 900, height: 600)
        let anchor = CGPoint(x: 630, y: 180)
        let oldPan = CGSize(width: 10, height: -15)
        let newPan = ViewportGeometry.anchoredPan(oldPan, anchor: anchor, viewport: viewport, oldZoom: 0.5, newZoom: 1.4)
        let beforeX = (anchor.x - viewport.width / 2 - oldPan.width) / 0.5
        let afterX = (anchor.x - viewport.width / 2 - newPan.width) / 1.4
        let beforeY = (anchor.y - viewport.height / 2 - oldPan.height) / 0.5
        let afterY = (anchor.y - viewport.height / 2 - newPan.height) / 1.4
        XCTAssertEqual(beforeX, afterX, accuracy: 0.0001)
        XCTAssertEqual(beforeY, afterY, accuracy: 0.0001)
    }

    func testPanCannotExposeSpaceBeyondAnEnlargedImage() {
        let result = ViewportGeometry.clampedPan(CGSize(width: 5000, height: -5000),
            imagePixels: CGSize(width: 4000, height: 3000), viewport: CGSize(width: 1000, height: 800),
            zoom: 1, backingScale: 2)
        XCTAssertEqual(result.width, 500)
        XCTAssertEqual(result.height, -350)
    }

    func testSmallImageAlwaysStaysCentered() {
        let result = ViewportGeometry.clampedPan(CGSize(width: 500, height: 500),
            imagePixels: CGSize(width: 100, height: 100), viewport: CGSize(width: 1000, height: 800),
            zoom: 1, backingScale: 2)
        XCTAssertEqual(result, .zero)
    }

    func testRotatingPortraitSwapsDimensions() {
        XCTAssertEqual(ViewportGeometry.rotatedSize(CGSize(width: 4000, height: 6000), quarterTurns: 1),
                       CGSize(width: 6000, height: 4000))
    }

    func testWindowFitStaysOnSecondaryDisplayWithNegativeOrigin() {
        let screen = CGRect(x: -1920, y: 24, width: 1920, height: 1056)
        let frame = ViewportGeometry.fittedWindow(imagePixels: CGSize(width: 6000, height: 4000), zoom: 1,
            backingScale: 2, chromeHeight: 174, visibleFrame: screen,
            currentFrame: CGRect(x: -400, y: 900, width: 900, height: 700))
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.width, screen.width)
        XCTAssertEqual(frame.height, screen.height)
    }

    func testWindowFitMatchesTheCurrentImageScaleWhenItFits() {
        let frame = ViewportGeometry.fittedWindow(imagePixels: CGSize(width: 1200, height: 800), zoom: 1,
            backingScale: 2, chromeHeight: 68, visibleFrame: CGRect(x: 0, y: 0, width: 2400, height: 1400),
            currentFrame: CGRect(x: 100, y: 100, width: 900, height: 700))
        XCTAssertEqual(frame.width, 600)
        XCTAssertEqual(frame.height - 68, 400)
    }

    func testOversizedWindowFitClampsEachAxisWithoutScalingTheOther() {
        let frame = ViewportGeometry.fittedWindow(imagePixels: CGSize(width: 2000, height: 8000), zoom: 1,
            backingScale: 2, chromeHeight: 68, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            currentFrame: CGRect(x: 0, y: 0, width: 900, height: 700))
        XCTAssertEqual(frame.width, 1000, "The width should not shrink when only the height exceeds the screen")
        XCTAssertEqual(frame.height, 900)
    }

    func testWindowFitKeepsEnoughRoomForControlsOnANarrowImage() {
        let frame = ViewportGeometry.fittedWindow(imagePixels: CGSize(width: 100, height: 900), zoom: 1,
            backingScale: 2, chromeHeight: 160, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            currentFrame: CGRect(x: 0, y: 0, width: 900, height: 700))
        XCTAssertEqual(frame.width, 360)
        XCTAssertEqual(frame.height, 610)
    }

    func testWindowChromeMatchesTheVisibleControls() {
        XCTAssertEqual(ViewerLayoutMetrics.chromeHeight(immersive: false, filmstrip: true, imageCount: 2), 160)
        XCTAssertEqual(ViewerLayoutMetrics.chromeHeight(immersive: false, filmstrip: false, imageCount: 2), 68)
        XCTAssertEqual(ViewerLayoutMetrics.chromeHeight(immersive: false, filmstrip: true, imageCount: 1), 68)
        XCTAssertEqual(ViewerLayoutMetrics.chromeHeight(immersive: true, filmstrip: true, imageCount: 2), 0)
    }
}
