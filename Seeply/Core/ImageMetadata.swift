import Foundation

struct MetadataEntry: Identifiable, Sendable {
    let label: DisplayText
    let value: DisplayText
    var id: String { label.identifier }
}

struct MetadataSection: Identifiable, Sendable {
    let title: DisplayText
    let entries: [MetadataEntry]
    var id: String { title.identifier }
}

struct ImageMetadata: Sendable {
    let fileName: String
    let camera: String?
    let lens: String?
    let aperture: Double?
    let exposure: Double?
    let iso: Int?
    let focalLength: Double?
    let sections: [MetadataSection]
    let rawSections: [MetadataSection]

    var summary: String {
        [focalLength.map { MetadataFormatter.focalLength($0) },
         aperture.map { MetadataFormatter.aperture($0) },
         exposure.map { MetadataFormatter.exposure($0) },
         iso.map { "ISO \($0)" }].compactMap { $0 }.joined(separator: "  ·  ")
    }

    func copyText(language: InterfaceLanguage) -> String {
        ([fileName] + sections.flatMap { section in
            ["", section.title.resolved(in: language)] + section.entries.map {
                StringCatalog.text("{label}: {value}", language: language,
                    arguments: ["label": $0.label.resolved(in: language), "value": $0.value.resolved(in: language)])
            }
        }).joined(separator: "\n")
    }
}
