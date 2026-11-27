import XCTest
import AppKit
@testable import Seeply

@MainActor
final class FileTypeSessionTests: XCTestCase {
    private enum WaitError: Error { case timedOut }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition() {
            guard clock.now < deadline else { XCTFail("The browsing operation did not finish"); throw WaitError.timedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Seeply-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func copy(_ fixture: String, ext: String, to folder: URL, name: String) throws -> URL {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: fixture, withExtension: ext, subdirectory: "Fixtures"))
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    func testCorruptedJPEGIsSkippedWhenExcludedAndKeepsAnErrorWhenIncluded() async throws {
        let folder = try makeFolder()
        let saved = Preferences.shared.fileTypes
        let session = ViewerSession()
        defer { session.close(); Preferences.shared.fileTypes = saved; try? FileManager.default.removeItem(at: folder) }
        try copy("broken", ext: "jpg", to: folder, name: "a.jpg")
        try copy("plain", ext: "png", to: folder, name: "b.PNG")
        Preferences.shared.fileTypes = ImageFileFilter(enabled: [.png])
        session.open([folder])
        try await waitUntil { !session.isOpening && !session.loading && session.image != nil }
        XCTAssertEqual(session.items.map(\.name), ["b.PNG"])
        XCTAssertNil(session.errorMessage)
        Preferences.shared.fileTypes = .all
        session.select(0)
        try await waitUntil { !session.loading && session.errorMessage != nil }
        Preferences.shared.fileTypes = ImageFileFilter(enabled: [.jpeg])
        try await waitUntil { !session.loading && session.errorMessage != nil }
    }

    func testChangingTheFilterPreservesAnIncludedPhotoAndItsViewport() async throws {
        let folder = try makeFolder()
        let saved = Preferences.shared.fileTypes
        let session = ViewerSession()
        defer { session.close(); Preferences.shared.fileTypes = saved; try? FileManager.default.removeItem(at: folder) }
        let selected = try copy("orientation6", ext: "jpg", to: folder, name: "a.jpg")
        try copy("plain", ext: "png", to: folder, name: "b.png")
        Preferences.shared.fileTypes = .all
        session.open([folder], selected: selected)
        try await waitUntil { !session.loading && session.image != nil }
        let pixels = try XCTUnwrap(session.image?.image)
        session.viewport.setViewport(CGSize(width: 20, height: 20), scale: 2)
        session.viewport.setZoom(4)
        session.viewport.rotate()
        session.viewport.translate(x: 10, y: 5)
        let pan = session.viewport.pan
        XCTAssertNotEqual(pan, .zero)
        Preferences.shared.fileTypes = ImageFileFilter(enabled: [.jpeg])
        XCTAssertEqual(session.items.map(\.name), ["a.jpg"])
        XCTAssertTrue(session.image?.image === pixels)
        XCTAssertEqual(session.viewport.zoom, 4)
        XCTAssertEqual(session.viewport.pan, pan)
        XCTAssertEqual(session.viewport.quarterTurns, 1)
    }

    func testExcludingTheCurrentPhotoThenAllTypesCanRecoverWithoutReopening() async throws {
        let folder = try makeFolder()
        let saved = Preferences.shared.fileTypes
        let session = ViewerSession()
        defer { session.close(); Preferences.shared.fileTypes = saved; try? FileManager.default.removeItem(at: folder) }
        let selected = try copy("orientation6", ext: "jpg", to: folder, name: "a.jpg")
        try copy("plain", ext: "png", to: folder, name: "b.png")
        Preferences.shared.fileTypes = .all
        session.open([folder], selected: selected)
        try await waitUntil { !session.loading && session.image != nil }
        Preferences.shared.fileTypes = ImageFileFilter(enabled: [.png])
        XCTAssertEqual(session.current?.name, "b.png")
        Preferences.shared.fileTypes = .none
        XCTAssertTrue(session.items.isEmpty)
        XCTAssertTrue(session.isFilteredEmpty)
        XCTAssertNil(session.image)
        Preferences.shared.fileTypes = .all
        try await waitUntil { !session.loading && session.image != nil }
        XCTAssertEqual(session.items.count, 2)
        XCTAssertEqual(session.current?.name, "b.png")
        XCTAssertNil(session.errorMessage)
    }

    func testLatestFilterWinsDuringOpenAndRefreshRetainsExcludedExplicitFiles() async throws {
        let folder = try makeFolder()
        let saved = Preferences.shared.fileTypes
        let session = ViewerSession()
        defer { session.close(); Preferences.shared.fileTypes = saved; try? FileManager.default.removeItem(at: folder) }
        let urls = [try copy("orientation6", ext: "jpg", to: folder, name: "a.jpg"),
                    try copy("plain", ext: "png", to: folder, name: "b.png"),
                    try copy("orientation6", ext: "jpg", to: folder, name: "c.jpg")]
        Preferences.shared.fileTypes = ImageFileFilter(enabled: [.jpeg])
        session.open(urls)
        Preferences.shared.fileTypes = ImageFileFilter(enabled: [.png])
        try await waitUntil { !session.isOpening && session.items.count == 1 }
        XCTAssertEqual(session.current?.name, "b.png")
        XCTAssertNil(session.folder)
        Preferences.shared.fileTypes = ImageFileFilter(enabled: [.jpeg])
        session.refresh()
        try await waitUntil { !session.isOpening && session.items.count == 2 }
        Preferences.shared.fileTypes = .all
        XCTAssertEqual(session.items.map(\.name), ["a.jpg", "b.png", "c.jpg"])
    }
}
