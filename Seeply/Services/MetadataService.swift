import Foundation
import ImageIO

actor MetadataService {
    static let shared = MetadataService()
    private var cache = CostLRUCache<String, ImageMetadata>(budget: 256)
    private var cacheGeneration: UInt64 = 0
    private let worker = WorkQueue(name: "app.seeply.metadata", concurrency: 1, qos: .userInitiated)

    func metadata(for item: ImageItem) async throws -> ImageMetadata {
        try Task.checkCancellation()
        if let cached = cache.value(for: item.revision) { return cached }
        let generation = cacheGeneration
        let result = try await worker.run { try Self.read(item) }
        try Task.checkCancellation()
        if generation == cacheGeneration { cache.insert(result, for: item.revision, cost: 1) }
        return result
    }

    func clear() { cacheGeneration &+= 1; cache.removeAll() }

    static func read(_ item: ImageItem) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ViewerError.unreadable(item.name) }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let p = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] ?? [:]
        let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let aux = p[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gps = p[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        func text(_ dict: [String: Any], _ key: CFString) -> String? {
            guard let value = dict[key as String] as? String, !value.isEmpty else { return nil }
            return value
        }
        func number(_ dict: [String: Any], _ key: CFString) -> Double? {
            (dict[key as String] as? NSNumber)?.doubleValue
        }
        func entry(_ label: String, _ value: String?) -> MetadataEntry {
            MetadataEntry(label: .key(label), value: .literal(value ?? "—"))
        }
        let make = text(tiff, kCGImagePropertyTIFFMake)
        let model = text(tiff, kCGImagePropertyTIFFModel)
        let camera: String?
        if let make, let model {
            camera = model.lowercased().hasPrefix(make.lowercased()) ? model : "\(make) \(model)"
        } else { camera = model ?? make }
        let lens = text(exif, kCGImagePropertyExifLensModel) ?? text(aux, kCGImagePropertyExifAuxLensModel)
        let aperture = number(exif, kCGImagePropertyExifFNumber)
        let exposure = number(exif, kCGImagePropertyExifExposureTime)
        let focal = number(exif, kCGImagePropertyExifFocalLength)
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.intValue
            ?? (exif[kCGImagePropertyExifISOSpeed as String] as? NSNumber)?.intValue
        let date = MetadataFormatter.captureDate(text(exif, kCGImagePropertyExifDateTimeOriginal),
                                                 offset: text(exif, kCGImagePropertyExifOffsetTimeOriginal))
        let wb = number(exif, kCGImagePropertyExifWhiteBalance).map { DisplayText.key($0 == 0 ? "Auto" : "Manual") }
        let flash = number(exif, kCGImagePropertyExifFlash).map { DisplayText.key(Int($0) & 1 == 1 ? "Fired" : "Did not fire") }
        let meteringNames = [0: "Unspecified", 1: "Average", 2: "Center-weighted", 3: "Spot", 4: "Multi-spot", 5: "Multi-segment", 6: "Partial", 255: "Other"]
        let metering = number(exif, kCGImagePropertyExifMeteringMode).map { value -> DisplayText in
            if let key = meteringNames[Int(value)] { return .key(key) }
            return .key("Mode {mode}", ["mode": String(Int(value))])
        }
        let width = number(p, kCGImagePropertyPixelWidth) ?? 0
        let height = number(p, kCGImagePropertyPixelHeight) ?? 0
        let orientation = Int(number(p, kCGImagePropertyOrientation) ?? 1)
        let transpose = [5, 6, 7, 8].contains(orientation)
        let dimensions = "\(Int(transpose ? height : width)) × \(Int(transpose ? width : height))"
        let size = MetadataFormatter.fileSize(Int64(item.fileSize))
        let type = CGImageSourceGetType(source).map { $0 as String } ?? item.url.pathExtension.uppercased()
        let profile = text(p, kCGImagePropertyProfileName) ?? text(p, kCGImagePropertyColorModel)
        var sections = [
            MetadataSection(title: .key("Equipment"), entries: [entry("Camera", camera), entry("Lens", lens)]),
            MetadataSection(title: .key("Capture"), entries: [
                entry("Focal length", MetadataFormatter.focalLength(focal)),
                entry("35mm equiv.", number(exif, kCGImagePropertyExifFocalLenIn35mmFilm).map { MetadataFormatter.focalLength($0) }),
                entry("Aperture", MetadataFormatter.aperture(aperture)),
                entry("Shutter", MetadataFormatter.exposure(exposure)),
                entry("ISO", iso.map(String.init)),
                entry("Exp. comp.", MetadataFormatter.bias(number(exif, kCGImagePropertyExifExposureBiasValue))),
                MetadataEntry(label: .key("White bal."), value: wb ?? .literal("—")),
                MetadataEntry(label: .key("Metering"), value: metering ?? .literal("—")),
                MetadataEntry(label: .key("Flash"), value: flash ?? .literal("—")), entry("Captured", date)
            ]),
            MetadataSection(title: .key("Image & File"), entries: [
                entry("File name", item.name), entry("Dimensions", dimensions + " px"), entry("File size", size),
                entry("Format", type), entry("Color profile", profile),
                entry("Bit depth", number(p, kCGImagePropertyDepth).map { "\(Int($0)) bit" })
            ])
        ]
        if let latitude = number(gps, kCGImagePropertyGPSLatitude),
           let longitude = number(gps, kCGImagePropertyGPSLongitude) {
            let lat = latitude * (text(gps, kCGImagePropertyGPSLatitudeRef) == "S" ? -1 : 1)
            let lon = longitude * (text(gps, kCGImagePropertyGPSLongitudeRef) == "W" ? -1 : 1)
            sections.append(MetadataSection(title: .key("Location"), entries: [
                entry("Latitude", MetadataFormatter.decimal(lat, digits: 6) + "°"),
                entry("Longitude", MetadataFormatter.decimal(lon, digits: 6) + "°")
            ]))
        }
        let raw = p.keys.sorted().compactMap { key -> MetadataSection? in
            guard let dict = p[key] as? [String: Any] else { return nil }
            let fields = dict.keys.sorted().compactMap { field -> MetadataEntry? in
                // MakerNote blobs can be enormous. Keep the inspector readable and bounded.
                guard !(dict[field] is Data), field != "MakerNote" else { return nil }
                return MetadataEntry(label: .literal(field), value: .literal(String(describing: dict[field]!).prefix(1024).description))
            }
            return fields.isEmpty ? nil : MetadataSection(title: .literal(key), entries: fields)
        }
        return ImageMetadata(fileName: item.name, camera: camera, lens: lens, aperture: aperture,
                             exposure: exposure, iso: iso, focalLength: focal, sections: sections, rawSections: raw)
    }
}
