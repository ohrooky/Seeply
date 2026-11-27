import XCTest
#if canImport(SeeplyCore)
@testable import SeeplyCore
#else
@testable import Seeply
#endif

final class CacheAndFormattingTests: XCTestCase {
    func testLeastRecentlyUsedEntryIsEvictedWithinBudget() {
        var cache = CostLRUCache<String, String>(budget: 10)
        cache.insert("A", for: "a", cost: 6)
        cache.insert("B", for: "b", cost: 4)
        XCTAssertEqual(cache.value(for: "a"), "A")
        cache.insert("C", for: "c", cost: 4)
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertEqual(cache.value(for: "a"), "A")
        XCTAssertEqual(cache.value(for: "c"), "C")
        XCTAssertEqual(cache.totalCost, 10)
    }

    func testOversizedImageIsNotCachedAndReplacementAdjustsCost() {
        var cache = CostLRUCache<String, Int>(budget: 10)
        cache.insert(1, for: "a", cost: 6)
        cache.insert(2, for: "a", cost: 3)
        XCTAssertEqual(cache.totalCost, 3)
        cache.insert(3, for: "large", cost: 11)
        XCTAssertEqual(cache.count, 1)
        cache.removeAll()
        XCTAssertEqual(cache.totalCost, 0)
    }

    func testRejectedReplacementsKeepTheOldValueAndItsCost() {
        var cache = CostLRUCache<String, String>(budget: 10)
        cache.insert("original", for: "image", cost: 6)
        cache.insert("too large", for: "image", cost: 11)
        XCTAssertEqual(cache.value(for: "image"), "original")
        XCTAssertEqual(cache.totalCost, 6)
        cache.insert("invalid cost", for: "image", cost: -1)
        XCTAssertEqual(cache.value(for: "image"), "original")
        XCTAssertEqual(cache.totalCost, 6)
    }

    func testBudgetComparisonDoesNotOverflowAtIntMax() {
        var cache = CostLRUCache<String, Int>(budget: Int.max)
        cache.insert(1, for: "a", cost: Int.max - 1)
        cache.insert(2, for: "b", cost: 1)
        cache.insert(3, for: "c", cost: 1)
        XCTAssertNil(cache.value(for: "a"))
        XCTAssertEqual(cache.value(for: "b"), 2)
        XCTAssertEqual(cache.value(for: "c"), 3)
        XCTAssertEqual(cache.totalCost, 2)
    }

    func testExposureAndApertureFormatting() {
        XCTAssertEqual(MetadataFormatter.exposure(0.004), "1/250 s")
        XCTAssertEqual(MetadataFormatter.exposure(1.6), "1.6 s")
        XCTAssertEqual(MetadataFormatter.exposure(0.8), "0.8 s")
        XCTAssertEqual(MetadataFormatter.aperture(1.4), "ƒ/1.4")
        XCTAssertEqual(MetadataFormatter.focalLength(35), "35 mm")
        XCTAssertEqual(MetadataFormatter.bias(0.33), "+0.33 EV")
        XCTAssertEqual(MetadataFormatter.decimal(10), "10")
    }

    func testMissingOrInvalidValuesAreNotInvented() {
        XCTAssertEqual(MetadataFormatter.aperture(nil), "—")
        XCTAssertEqual(MetadataFormatter.exposure(0), "—")
        XCTAssertEqual(MetadataFormatter.exposure(.nan), "—")
        XCTAssertEqual(MetadataFormatter.focalLength(-1), "—")
        XCTAssertEqual(MetadataFormatter.captureDate(nil, offset: nil), "—")
        XCTAssertEqual(MetadataFormatter.captureDate("   ", offset: nil), "—")
        XCTAssertEqual(MetadataFormatter.exposure(Double.leastNonzeroMagnitude), "0 s")
    }

    func testExifTimezoneIsPreservedOnlyWhenPresent() {
        XCTAssertEqual(MetadataFormatter.captureDate("2026:01:02 03:04:05", offset: nil), "2026-01-02  03:04:05")
        XCTAssertEqual(MetadataFormatter.captureDate("2026:01:02 03:04:05", offset: "+09:00"), "2026-01-02  03:04:05  +09:00")
    }
}
