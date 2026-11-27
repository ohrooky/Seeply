import XCTest
#if canImport(SeeplyCore)
@testable import SeeplyCore
#else
@testable import Seeply
#endif

final class ChromeAutoHideTests: XCTestCase {
    func testNormalWindowsNeverHideTheirControls() {
        var state = ChromeAutoHide()
        state.pointerActivity(at: 1)
        state.setHovered(.header, true, at: 2)
        state.setHovered(.header, false, at: 3)
        state.hideExpired(at: 100)
        XCTAssertTrue(state.isVisible(.header))
        XCTAssertTrue(state.isVisible(.bottom))
        XCTAssertNil(state.nextHideTime)
    }

    func testFramelessInitiallyHidesBothBarsAfterOneAndAHalfSeconds() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 10)
        state.hideExpired(at: 11.49)
        XCTAssertTrue(state.isVisible(.header))
        XCTAssertTrue(state.isVisible(.bottom))
        state.hideExpired(at: 11.5)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertFalse(state.isVisible(.bottom))
        XCTAssertNil(state.nextHideTime)
    }

    func testActivityOverThePhotoNeitherDelaysHidingNorRevealsFramelessBars() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.pointerActivity(at: 1.4)
        state.hideExpired(at: 1.5)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertFalse(state.isVisible(.bottom))
        state.pointerActivity(at: 5)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertFalse(state.isVisible(.bottom))
        XCTAssertNil(state.nextHideTime)
    }

    func testHoveringTheToolbarKeepsOnlyTheToolbarVisible() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.setHovered(.header, true, at: 1)
        state.hideExpired(at: 100)
        XCTAssertTrue(state.isVisible(.header))
        XCTAssertFalse(state.isVisible(.bottom))
    }

    func testThumbnailBrowsingDoesNotWakeTheToolbar() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.hideExpired(at: 2)
        state.setHovered(.bottom, true, at: 3)
        state.pointerActivity(at: 4) // Selecting another image also signals activity.
        state.hideExpired(at: 100)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertTrue(state.isVisible(.bottom))
    }

    func testLeavingARegionStartsTheDelayFromTheTimeOfExit() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.setHovered(.bottom, true, at: 1)
        state.hideExpired(at: 10)
        state.setHovered(.bottom, false, at: 10)
        state.hideExpired(at: 11.49)
        XCTAssertTrue(state.isVisible(.bottom))
        state.hideExpired(at: 11.5)
        XCTAssertFalse(state.isVisible(.bottom))
    }

    func testReturningBeforeTheDelayExpiresCancelsTheOldHideDeadline() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.setHovered(.header, true, at: 1)
        state.setHovered(.header, false, at: 2)
        state.setHovered(.header, true, at: 3.4)
        state.hideExpired(at: 3.5)
        XCTAssertTrue(state.isVisible(.header))
        state.setHovered(.header, false, at: 5)
        state.hideExpired(at: 6.49)
        XCTAssertTrue(state.isVisible(.header))
        state.hideExpired(at: 6.5)
        XCTAssertFalse(state.isVisible(.header))
    }

    func testMovingBetweenRegionsUsesIndependentDeadlines() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.setHovered(.header, true, at: 1)
        state.hideExpired(at: 2)
        state.setHovered(.header, false, at: 3)
        state.setHovered(.bottom, true, at: 3)
        state.hideExpired(at: 4.5)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertTrue(state.isVisible(.bottom))
        XCTAssertNil(state.nextHideTime)
    }

    func testReturningToANormalWindowRestoresBarsAndDiscardsOldDeadlines() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.hideExpired(at: 2)
        state.setHovered(.header, true, at: 3)
        state.setHovered(.header, false, at: 4)
        state.setMode(.windowed, at: 5)
        state.hideExpired(at: 100)
        XCTAssertTrue(state.isVisible(.header))
        XCTAssertTrue(state.isVisible(.bottom))
        XCTAssertNil(state.nextHideTime)
        XCTAssertTrue(state.hovered.isEmpty)
    }

    func testLightboxAndFullscreenStillRevealBothBarsOnPhotoActivity() {
        var state = ChromeAutoHide()
        state.setMode(.immersive, at: 0)
        state.hideExpired(at: 2.6)
        XCTAssertFalse(state.isVisible(.header))
        state.pointerActivity(at: 5)
        XCTAssertTrue(state.isVisible(.header))
        XCTAssertTrue(state.isVisible(.bottom))
        state.pointerActivity(at: 7)
        state.hideExpired(at: 9.5)
        XCTAssertTrue(state.isVisible(.bottom))
        state.hideExpired(at: 9.6)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertFalse(state.isVisible(.bottom))
    }

    func testImmersiveControlsWaitUntilAllHoveredRegionsAreLeft() {
        var state = ChromeAutoHide()
        state.setMode(.immersive, at: 0)
        state.setHovered(.header, true, at: 1)
        state.setHovered(.bottom, true, at: 2)
        state.setHovered(.header, false, at: 3)
        state.hideExpired(at: 10)
        XCTAssertTrue(state.isVisible(.header))
        XCTAssertTrue(state.isVisible(.bottom))
        state.setHovered(.bottom, false, at: 10)
        state.hideExpired(at: 12.6)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertFalse(state.isVisible(.bottom))
    }

    func testReapplyingTheSameModeDoesNotPostponeHiding() {
        var state = ChromeAutoHide()
        state.setMode(.frameless, at: 0)
        state.setMode(.frameless, at: 1.4)
        state.hideExpired(at: 1.5)
        XCTAssertFalse(state.isVisible(.header))
        XCTAssertFalse(state.isVisible(.bottom))
    }
}
