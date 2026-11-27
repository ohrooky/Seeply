import SwiftUI

@MainActor
struct ColorPaletteBar: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    @ObservedObject var session: ViewerSession
    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.text("Palette")).font(.system(size: 9)).foregroundStyle(Theme.secondary)
            if let palette = session.palette, !palette.colors.isEmpty {
                HStack(spacing: 4) {
                    ForEach(palette.colors) { PaletteSwatch(color: $0) }
                }
            } else if session.loadingPalette {
                ProgressView().controlSize(.mini)
                Text(L10n.text("Analyzing…")).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            } else {
                Text(session.paletteError == nil ? L10n.text("No colors to display") : L10n.text("Currently unavailable"))
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    .help(L10n.resolve(session.paletteError ?? .literal("")))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .modifier(PanelSurface(radius: 8))
        .contextMenu {
            Button(L10n.text("Copy All Color Codes")) {
                if let palette = session.palette { Theme.copy(palette.colors.map(\.hex).joined(separator: " ")) }
            }.disabled(session.palette == nil)
            Button(L10n.text("Hide Color Palette")) { Preferences.shared.showPalette = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Photo color palette"))
    }
}

@MainActor
private struct PaletteSwatch: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    let color: PaletteColor
    @State private var copied = false
    @State private var feedbackID: UUID?
    private var light: Bool { Double(color.red) * 0.2126 + Double(color.green) * 0.7152 + Double(color.blue) * 0.0722 > 150 }
    var body: some View {
        Button {
            Theme.copy(color.hex)
            copied = true
            feedbackID = UUID()
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255,
                            blue: Double(color.blue) / 255, opacity: 1))
                .frame(width: 34, height: 17)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.14)))
                .overlay {
                    if copied {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(light ? Color.black.opacity(0.8) : Color.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(copied ? L10n.text("Copied {hex}", ["hex": color.hex]) : L10n.text("{hex} · ~{percent}% · Click to copy", ["hex": color.hex, "percent": String(Int((color.fraction * 100).rounded()))]))
        .accessibilityLabel(L10n.text("{hex}, click to copy color code", ["hex": color.hex]))
        .task(id: feedbackID) {
            guard feedbackID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
