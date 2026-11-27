import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    private var localeSubscription: AnyCancellable?
    @Published private(set) var systemLanguages: [String]
    @Published var language: LanguagePreference { didSet { defaults.set(language.rawValue, forKey: "interfaceLanguage") } }
    var effectiveLanguage: InterfaceLanguage { language.resolved(preferredLanguages: systemLanguages) }
    @Published var fileTypes: ImageFileFilter { didSet { defaults.set(fileTypes.storedTypes, forKey: "enabledImageFileTypes") } }
    enum SettingsTab: Hashable { case general, fileTypes }
    @Published var settingsTab: SettingsTab = .general

    @Published var allowUpscaling: Bool { didSet { defaults.set(allowUpscaling, forKey: "allowUpscaling") } }
    @Published var showSummary: Bool { didSet { defaults.set(showSummary, forKey: "showSummary") } }
    @Published var showPalette: Bool { didSet { defaults.set(showPalette, forKey: "showPalette") } }
    @Published var loopNavigation: Bool { didSet { defaults.set(loopNavigation, forKey: "loopNavigation") } }
    @Published var rememberZoom: Bool { didSet { defaults.set(rememberZoom, forKey: "rememberZoom") } }
    @Published var background: Background { didSet { defaults.set(background.rawValue, forKey: "background") } }

    enum Background: String, CaseIterable, Identifiable {
        case graphite, black, paper
        var id: String { rawValue }
        @MainActor var title: String {
            switch self { case .graphite: return L10n.text("Graphite"); case .black: return L10n.text("Black"); case .paper: return L10n.text("Paper") }
        }
    }

    private init() {
        defaults.register(defaults: ["allowUpscaling": false, "showSummary": true, "showPalette": false,
                                     "interfaceLanguage": LanguagePreference.system.rawValue,
                                     "enabledImageFileTypes": ImageFileFilter.all.storedTypes,
                                     "loopNavigation": true, "rememberZoom": false,
                                     "background": Background.graphite.rawValue])
        systemLanguages = Locale.preferredLanguages
        language = LanguagePreference(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .system
        fileTypes = ImageFileFilter(storedTypes: defaults.stringArray(forKey: "enabledImageFileTypes"))
        allowUpscaling = defaults.bool(forKey: "allowUpscaling")
        showSummary = defaults.bool(forKey: "showSummary")
        showPalette = defaults.bool(forKey: "showPalette")
        loopNavigation = defaults.bool(forKey: "loopNavigation")
        rememberZoom = defaults.bool(forKey: "rememberZoom")
        background = Background(rawValue: defaults.string(forKey: "background") ?? "") ?? .graphite
        localeSubscription = NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.systemLanguages = Locale.preferredLanguages }
    }
}
