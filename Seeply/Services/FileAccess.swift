import Foundation
import ImageIO
import UniformTypeIdentifiers

struct BrowseSelection: Sendable {
    /// Supported file paths and attributes only. The session applies the user's
    /// type filter before requesting any image, thumbnail, EXIF or preload work.
    let items: [ImageItem]
    let selectedURL: URL?
    let folder: URL?
    let needsFolderAccess: Bool
}

enum FileAccess {
    static let worker = WorkQueue(name: "app.seeply.files", concurrency: 1, qos: .userInitiated)
    static let imageTypes: [UTType] = {
        let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        let types = identifiers.compactMap { UTType($0) }.filter { $0.conforms(to: .image) }
        // An empty allowedContentTypes array would make NSOpenPanel unrestricted.
        return types.isEmpty ? [.image] : types
    }()

    static func supports(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return imageTypes.contains { type.conforms(to: $0) }
    }

    static func open(_ urls: [URL], selectedURL: URL? = nil) async throws -> BrowseSelection {
        try await worker.run {
            let urls = urls.map(\.standardizedFileURL)
            guard let first = urls.first else { throw ViewerError.emptyFolder }
            let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if urls.count == 1, isFolder {
                let lease = AccessLease(first)
                let items = try contents(of: first, lease: lease)
                guard !items.isEmpty else { throw ViewerError.emptyFolder }
                return BrowseSelection(items: items, selectedURL: selectedURL ?? items.first?.url,
                                       folder: first, needsFolderAccess: false)
            }
            let items = urls.filter(supports).map { ImageItem(url: $0, lease: AccessLease($0)) }
            guard !items.isEmpty else { throw ViewerError.unsupported(first.lastPathComponent) }
            if items.count == 1 {
                let selected = items[0].url
                let parent = selected.deletingLastPathComponent()
                // A Finder-opened file does not imply access to its siblings in a sandbox.
                if let neighbors = try? contents(of: parent, lease: items[0].lease),
                   neighbors.contains(where: { $0.url == selected }) {
                    return BrowseSelection(items: neighbors, selectedURL: selected,
                                           folder: parent, needsFolderAccess: false)
                }
                return BrowseSelection(items: items, selectedURL: selected, folder: parent, needsFolderAccess: true)
            }
            return BrowseSelection(items: sorted(items), selectedURL: selectedURL ?? items.first?.url,
                                   folder: nil, needsFolderAccess: false)
        }
    }

    static func sorted(_ items: [ImageItem]) -> [ImageItem] {
        items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func contents(of folder: URL, lease: AccessLease?) throws -> [ImageItem] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        return sorted(urls.filter {
            supports($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }.map { ImageItem(url: $0, lease: lease) })
    }
}
