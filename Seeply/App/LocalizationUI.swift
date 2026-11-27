import Foundation

@MainActor
enum L10n {
    static var language: InterfaceLanguage { Preferences.shared.effectiveLanguage }
    static var locale: Locale { Locale(identifier: language.rawValue) }
    static func text(_ key: String, _ arguments: [String: String] = [:]) -> String {
        StringCatalog.text(key, language: language, arguments: arguments)
    }
    static func resolve(_ value: DisplayText) -> String { value.resolved(in: language) }
    static func imageCount(_ count: Int) -> String {
        count == 1 ? text("1 image") : text("{count} images", ["count": String(count)])
    }
}
