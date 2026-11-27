import Foundation

/// Extension groups are explicit so enabling "other" cannot re-enable an
/// unchecked known format. Actual decoding support is still decided by ImageIO.
enum ImageFileType: String, CaseIterable, Identifiable, Sendable {
    case jpeg, png, bmp, tiff, heif, gif, webp, avif, jpeg2000
    case dng, arw, cr2, cr3, nef, raf, orf, rw2, pef, srw, otherRaw, other
    var id: String { rawValue }

    var extensions: Set<String> {
        switch self {
        case .jpeg: return ["jpg", "jpeg", "jpe"]
        case .png: return ["png", "apng"]
        case .bmp: return ["bmp", "dib"]
        case .tiff: return ["tif", "tiff"]
        case .heif: return ["heic", "heif", "hif"]
        case .gif: return ["gif"]
        case .webp: return ["webp"]
        case .avif: return ["avif"]
        case .jpeg2000: return ["jp2", "j2k", "jpf", "jpx", "jpm", "mj2"]
        case .dng: return ["dng"]
        case .arw: return ["arw"]
        case .cr2: return ["cr2"]
        case .cr3: return ["cr3"]
        case .nef: return ["nef"]
        case .raf: return ["raf"]
        case .orf: return ["orf"]
        case .rw2: return ["rw2"]
        case .pef: return ["pef"]
        case .srw: return ["srw"]
        case .otherRaw: return ["raw", "crw", "nrw", "sr2", "srf", "rwl", "ptx", "x3f", "mos", "mef", "mrw", "3fr", "fff", "iiq", "kdc", "dcr", "erf", "cap", "eip", "bay"]
        case .other: return []
        }
    }

    var title: DisplayText {
        switch self {
        case .jpeg: return .literal("JPG / JPEG")
        case .png: return .literal("PNG")
        case .bmp: return .literal("BMP")
        case .tiff: return .literal("TIFF / TIF")
        case .heif: return .literal("HEIC / HEIF")
        case .gif: return .literal("GIF")
        case .webp: return .literal("WebP")
        case .avif: return .literal("AVIF")
        case .jpeg2000: return .literal("JPEG 2000")
        case .otherRaw: return .key("Other RAW")
        case .other: return .key("Other supported formats")
        default: return .literal(rawValue.uppercased())
        }
    }

    var isRAW: Bool {
        switch self {
        case .dng, .arw, .cr2, .cr3, .nef, .raf, .orf, .rw2, .pef, .srw, .otherRaw: return true
        default: return false
        }
    }

    static func matching(extension fileExtension: String) -> Self? {
        let ext = fileExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return allCases.first { $0.extensions.contains(ext) } ?? .other
    }
}

struct FilteredImageURLs: Equatable, Sendable {
    let urls: [URL]
    let selectedIndex: Int?
}

struct ImageFileFilter: Equatable, Sendable {
    var enabled: Set<ImageFileType>
    static let all = Self(enabled: Set(ImageFileType.allCases))
    static let none = Self(enabled: [])
    static let common = Self(enabled: Set(ImageFileType.allCases.filter { !$0.isRAW && $0 != .other }))
    static let raw = Self(enabled: Set(ImageFileType.allCases.filter(\.isRAW)))

    init(enabled: Set<ImageFileType>) { self.enabled = enabled }
    init(storedTypes: [String]?) {
        // nil means no saved preference; [] deliberately means select none.
        enabled = storedTypes.map { Set($0.compactMap(ImageFileType.init(rawValue:))) } ?? Self.all.enabled
    }
    var storedTypes: [String] { enabled.map(\.rawValue).sorted() }

    func allows(_ url: URL) -> Bool {
        guard let type = ImageFileType.matching(extension: url.pathExtension) else { return false }
        return enabled.contains(type)
    }

    func selection(from source: [URL], preferredURL: URL?) -> FilteredImageURLs {
        let included = source.enumerated().filter { allows($0.element) }
        guard !included.isEmpty else { return FilteredImageURLs(urls: [], selectedIndex: nil) }
        let preferred = preferredURL?.standardizedFileURL
        let sourceIndex = preferred.flatMap { url in source.firstIndex { $0.standardizedFileURL == url } }
        let selected: Int
        if let exact = included.firstIndex(where: { $0.element.standardizedFileURL == preferred }) {
            selected = exact
        } else if let sourceIndex {
            // Prefer the next remaining photo; at the end, use the previous one.
            selected = included.firstIndex { $0.offset >= sourceIndex } ?? included.count - 1
        } else { selected = 0 }
        return FilteredImageURLs(urls: included.map(\.element), selectedIndex: selected)
    }
}
