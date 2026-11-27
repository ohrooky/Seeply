import SwiftUI

@MainActor
struct FileTypeSettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    private let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3)

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Button(L10n.text("Select All")) { preferences.fileTypes = .all }
                    Button(L10n.text("Select None")) { preferences.fileTypes = .none }
                    Spacer(minLength: 4)
                    Button(L10n.text("Common Images")) { preferences.fileTypes = .common }
                    Button(L10n.text("RAW Only")) { preferences.fileTypes = .raw }
                }.controlSize(.small)
                Text(L10n.text("{count} of {total} types selected", [
                    "count": String(preferences.fileTypes.enabled.count), "total": String(ImageFileType.allCases.count)]))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section(L10n.text("Common Images")) {
                typeGrid(ImageFileType.allCases.filter { !$0.isRAW && $0 != .other })
            }
            Section("RAW") {
                typeGrid(ImageFileType.allCases.filter(\.isRAW))
            }
            Section {
                typeToggle(.other)
                Text(L10n.text("Format support depends on macOS."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section {
                Text(L10n.text("Only selected formats are included when opening files or browsing folders."))
                Text(L10n.text("Changes apply to all open windows and are saved automatically."))
                if preferences.fileTypes.enabled.isEmpty {
                    Text(L10n.text("No file types selected.")).foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func typeGrid(_ types: [ImageFileType]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(types) { type in typeToggle(type) }
        }.padding(.vertical, 4)
    }

    private func typeToggle(_ type: ImageFileType) -> some View {
        Toggle(L10n.resolve(type.title), isOn: Binding(
            get: { preferences.fileTypes.enabled.contains(type) },
            set: { enabled in
                var filter = preferences.fileTypes
                if enabled { filter.enabled.insert(type) } else { filter.enabled.remove(type) }
                preferences.fileTypes = filter
            }))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .help(type == .other ? L10n.text("Additional image formats supported by macOS.") : type.extensions.sorted().map { "." + $0 }.joined(separator: ", "))
    }
}

@MainActor
struct FilteredEmptyState: View {
    @ObservedObject var session: ViewerSession
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Theme.accent)
            Text(L10n.text("No images match your file types"))
                .font(.system(size: 19, weight: .light)).foregroundStyle(Theme.text)
            Text(L10n.text(preferences.fileTypes.enabled.isEmpty ? "No file types selected." : "Choose different file types in Settings to continue browsing."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack(spacing: 12) {
                Button(L10n.text("File Type Settings…")) { session.onFileTypeSettings?() }
                    .buttonStyle(.borderedProminent)
                Button(L10n.text("Show All Types")) { preferences.fileTypes = .all }
                    .buttonStyle(.bordered)
            }.padding(.top, 4)
        }
        .multilineTextAlignment(.center).padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}
