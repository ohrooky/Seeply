import Foundation
import CoreGraphics

/// Keeps a user-granted URL alive until any background readers have finished.
final class AccessLease: @unchecked Sendable {
    let url: URL
    private let started: Bool
    init(_ url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }
    deinit { if started { url.stopAccessingSecurityScopedResource() } }
}

struct ImageItem: Identifiable, Hashable, Sendable {
    let url: URL
    let modified: Date
    let fileSize: Int
    let lease: AccessLease?
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var revision: String { "\(url.path)|\(modified.timeIntervalSince1970)|\(fileSize)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.revision == rhs.revision }
    func hash(into hasher: inout Hasher) { hasher.combine(revision) }

    init(url: URL, lease: AccessLease? = nil) {
        self.url = url.standardizedFileURL
        self.lease = lease
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        modified = values?.contentModificationDate ?? .distantPast
        fileSize = values?.fileSize ?? 0
    }
}

struct DecodedImage: @unchecked Sendable {
    let image: CGImage
    /// Dimensions after EXIF orientation; independent of preview resolution.
    let sourcePixels: CGSize
    let requestedDimension: Int
    let resolutionLimited: Bool
    var cost: Int { image.bytesPerRow * image.height }
}

enum ViewerError: PresentableError {
    case unsupported(String)
    case unreadable(String)
    case emptyFolder

    var displayText: DisplayText {
        switch self {
        case .unsupported(let name): return .key("Unable to decode “{name}”. This format may be unsupported by this version of macOS, or the file may be damaged.", ["name": name])
        case .unreadable(let name): return .key("Unable to read “{name}”. Check that it still exists and grant access to its folder again.", ["name": name])
        case .emptyFolder: return .key("This folder contains no images that can be displayed.")
        }
    }
}
