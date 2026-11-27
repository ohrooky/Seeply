import Foundation

enum MetadataFormatter {
    /// SI units keep cached file sizes independent of the system's language.
    static func fileSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        var value = Double(max(0, bytes))
        var index = 0
        while value >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
        return decimal(value, digits: index == 0 ? 0 : 2) + " " + units[index]
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
        return text.contains(".") ? text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) : text
    }

    static func exposure(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        if seconds >= 1 { return "\(decimal(seconds, digits: 2)) s" }
        let denominator = 1 / seconds
        let rounded = denominator.rounded()
        if denominator.isFinite, rounded < Double(Int.max), abs(denominator - rounded) / denominator < 0.015 {
            return "1/\(Int(rounded)) s"
        }
        return "\(decimal(seconds, digits: 4)) s"
    }

    static func aperture(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return "ƒ/\(decimal(value))"
    }

    static func focalLength(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return "\(decimal(value)) mm"
    }

    static func bias(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(value > 0 ? "+" : "")\(decimal(value, digits: 2)) EV"
    }

    static func captureDate(_ raw: String?, offset: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        // Do not invent a timezone for EXIF dates that don't contain one.
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        let date = parts[0].replacingOccurrences(of: ":", with: "-")
        let time = parts.count > 1 ? "  " + parts[1] : ""
        return date + time + (offset.map { "  " + $0 } ?? "")
    }
}
