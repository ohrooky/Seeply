import XCTest
#if canImport(SeeplyCore)
@testable import SeeplyCore
#else
@testable import Seeply
#endif

final class ImageFileFilterTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/photos/" + name) }

    func testFirstLaunchIncludesAllTypes() {
        XCTAssertEqual(ImageFileFilter(storedTypes: nil), .all)
        XCTAssertTrue(ImageFileFilter.all.allows(url("photo.dng")))
        XCTAssertTrue(ImageFileFilter.all.allows(url("photo.psd")))
    }

    func testAnExplicitlyEmptyPreferenceStaysEmpty() {
        let filter = ImageFileFilter(storedTypes: [])
        XCTAssertEqual(filter, .none)
        XCTAssertFalse(filter.allows(url("photo.jpg")))
        XCTAssertEqual(ImageFileFilter(storedTypes: filter.storedTypes), .none)
    }

    func testSavedSelectionsRoundTripAndIgnoreUnknownPreferenceKeys() {
        let filter = ImageFileFilter(storedTypes: ["jpeg", "dng", "future-format"])
        XCTAssertEqual(filter.enabled, [.jpeg, .dng])
        XCTAssertEqual(ImageFileFilter(storedTypes: filter.storedTypes), filter)
        XCTAssertEqual(filter.storedTypes, ["dng", "jpeg"])
        XCTAssertFalse(filter.allows(url("photo.png")))
    }

    func testJPEGVariantsAndUppercaseExtensionsShareOneCheckbox() {
        let filter = ImageFileFilter(enabled: [.jpeg])
        for name in ["photo.jpg", "photo.jpeg", "photo.jpe", "相片.JPG", "photo.JpEg"] {
            XCTAssertTrue(filter.allows(url(name)), name)
        }
        XCTAssertFalse(filter.allows(url("photo.dng")))
    }

    func testCommonAliasGroupsAndDNGAreDistinct() {
        let expected: [String: ImageFileType] = ["PNG": .png, "apng": .png, "bmp": .bmp, "dib": .bmp,
            "tif": .tiff, "tiff": .tiff, "heic": .heif, "heif": .heif, "hif": .heif,
            "gif": .gif, "webp": .webp, "avif": .avif, "jp2": .jpeg2000, "DNG": .dng]
        for (ext, type) in expected {
            XCTAssertTrue(ImageFileFilter(enabled: [type]).allows(url("photo." + ext)), ext)
            XCTAssertFalse(ImageFileFilter(enabled: Set(ImageFileType.allCases).subtracting([type])).allows(url("photo." + ext)), ext)
        }
    }

    func testOtherFormatsCannotBypassAnUncheckedKnownFormat() {
        let filter = ImageFileFilter(enabled: [.other])
        XCTAssertTrue(filter.allows(url("photo.psd")))
        for ext in ["jpg", "png", "bmp", "dng", "arw", "cr3", "nef", "sr2"] {
            XCTAssertFalse(filter.allows(url("photo." + ext)), ext)
        }
    }

    func testRAWOnlyIncludesDNGAndCameraRAWButExcludesRenderedImages() {
        for ext in ["dng", "arw", "cr2", "cr3", "nef", "raf", "orf", "rw2", "pef", "srw", "sr2", "nrw"] {
            XCTAssertTrue(ImageFileFilter.raw.allows(url("photo." + ext)), ext)
        }
        for ext in ["jpg", "png", "bmp", "tif", "heic", "psd"] {
            XCTAssertFalse(ImageFileFilter.raw.allows(url("photo." + ext)), ext)
        }
    }

    func testCommonPresetDoesNotIncludeRAW() {
        for ext in ["jpg", "png", "bmp", "tif", "heic", "webp"] {
            XCTAssertTrue(ImageFileFilter.common.allows(url("photo." + ext)), ext)
        }
        XCTAssertFalse(ImageFileFilter.common.allows(url("photo.dng")))
        XCTAssertFalse(ImageFileFilter.common.allows(url("photo.arw")))
    }

    func testFilteringUsesTheFinalExtensionRatherThanANameSubstring() {
        let filter = ImageFileFilter(enabled: [.jpeg])
        XCTAssertFalse(filter.allows(url("jpg-folder/photo.png")))
        XCTAssertFalse(filter.allows(url("photo.jpg.backup")))
        XCTAssertFalse(ImageFileFilter.all.allows(url("photo")))
    }

    func testFilteringPreservesSourceOrderAndTheCurrentPhoto() {
        let source = ["1.jpg", "2.png", "10.jpg", "11.dng"].map(url)
        let selection = ImageFileFilter(enabled: [.jpeg, .dng]).selection(from: source, preferredURL: source[2])
        XCTAssertEqual(selection.urls, [source[0], source[2], source[3]])
        XCTAssertEqual(selection.selectedIndex, 1)
    }

    func testExcludingTheCurrentPhotoSelectsTheNextRemainingPhoto() {
        let source = ["1.png", "2.jpg", "3.png", "4.jpg"].map(url)
        let selection = ImageFileFilter(enabled: [.png]).selection(from: source, preferredURL: source[1])
        XCTAssertEqual(selection.urls, [source[0], source[2]])
        XCTAssertEqual(selection.selectedIndex, 1)
    }

    func testExcludingTheLastPhotoFallsBackToThePreviousRemainingPhoto() {
        let source = ["1.png", "2.jpg", "3.png", "4.jpg"].map(url)
        let selection = ImageFileFilter(enabled: [.png]).selection(from: source, preferredURL: source[3])
        XCTAssertEqual(selection.selectedIndex, 1)
    }

    func testNoMatchesProducesAnEmptyListWithoutAnInvalidSelection() {
        let selection = ImageFileFilter(enabled: [.dng]).selection(from: [url("1.jpg"), url("2.png")], preferredURL: url("1.jpg"))
        XCTAssertEqual(selection.urls, [])
        XCTAssertNil(selection.selectedIndex)
    }

    func testSelectionUsesStandardizedURLsAndFallsBackWhenTheAnchorIsMissing() {
        let source = [url("1.jpg"), url("2.png")]
        let equivalent = URL(fileURLWithPath: "/photos/temporary/../2.png")
        XCTAssertEqual(ImageFileFilter.all.selection(from: source, preferredURL: equivalent).selectedIndex, 1)
        XCTAssertEqual(ImageFileFilter.all.selection(from: source, preferredURL: url("missing.jpg")).selectedIndex, 0)
    }
}
