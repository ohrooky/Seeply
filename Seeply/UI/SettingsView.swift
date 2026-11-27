import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @State private var cacheCleared = false
    @State private var isClearing = false
    @State private var clearFeedbackID: UUID?
    @State private var clearTask: Task<Void, Never>?
    private var generalSettings: some View {
        Form {
            Section(L10n.text("General")) {
                Picker(L10n.text("Language"), selection: $preferences.language) {
                    Text(L10n.text("Follow System")).tag(LanguagePreference.system)
                    Text("繁體中文").tag(LanguagePreference.traditionalChinese)
                    Text("English").tag(LanguagePreference.english)
                }
                if preferences.language == .system {
                    Text(L10n.text("Traditional Chinese is used for a Traditional Chinese system; English otherwise."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Section(L10n.text("Viewing")) {
                Picker(L10n.text("Canvas background"), selection: $preferences.background) {
                    ForEach(Preferences.Background.allCases) { Text($0.title).tag($0) }
                }
                Toggle(L10n.text("Allow small images to fill the window"), isOn: $preferences.allowUpscaling)
                Toggle(L10n.text("Keep zoom when changing images"), isOn: $preferences.rememberZoom)
                Toggle(L10n.text("Loop from the last image to the first"), isOn: $preferences.loopNavigation)
                Toggle(L10n.text("Show the EXIF summary"), isOn: $preferences.showSummary)
                Toggle(L10n.text("Show the color palette"), isOn: $preferences.showPalette)
            }
            Section(L10n.text("Cache")) {
                HStack {
                    Text(L10n.text("Image caches are kept in memory only."))
                    Spacer()
                    Button(isClearing ? L10n.text("Clearing…") : (cacheCleared ? L10n.text("Cleared") : L10n.text("Clear Cache"))) {
                        isClearing = true
                        clearFeedbackID = nil
                        cacheCleared = false
                        clearTask = Task { @MainActor in
                            await ImagePipeline.shared.clear()
                            await MetadataService.shared.clear()
                            await PaletteService.shared.clear()
                            guard !Task.isCancelled else { return }
                            isClearing = false
                            cacheCleared = true
                            clearFeedbackID = UUID()
                            clearTask = nil
                        }
                    }.disabled(isClearing)
                }
            }
            Section {
                Text("Seeply 0.1.7 · Swift / AppKit / SwiftUI")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    var body: some View {
        TabView(selection: $preferences.settingsTab) {
            generalSettings
                .tabItem { Label(L10n.text("General"), systemImage: "slider.horizontal.3") }
                .tag(Preferences.SettingsTab.general)
            FileTypeSettingsView()
                .tabItem { Label(L10n.text("File Types"), systemImage: "photo.on.rectangle.angled") }
                .tag(Preferences.SettingsTab.fileTypes)
        }
        .environment(\.locale, L10n.locale)
        .padding(12)
        .frame(width: 540, height: 520)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task(id: clearFeedbackID) {
            guard clearFeedbackID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            cacheCleared = false
        }
        .onDisappear {
            clearTask?.cancel()
            clearTask = nil
            isClearing = false
            cacheCleared = false
            clearFeedbackID = nil
        }
    }
}
