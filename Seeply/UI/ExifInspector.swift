import SwiftUI

@MainActor
struct ExifInspector: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    @ObservedObject var session: ViewerSession
    @State private var showRaw = false
    @State private var copied = false
    @State private var copyFeedbackID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Photo Info")).font(.system(size: 14, weight: .medium))
                    Text("DETAILS & EXIF").font(.system(size: 8, weight: .medium)).tracking(1.8).foregroundStyle(Theme.secondary)
                }
                Spacer()
                IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: L10n.text("Copy Photo Details")) {
                    if let metadata = session.metadata {
                        Theme.copy(metadata.copyText(language: L10n.language))
                        copied = true
                        copyFeedbackID = UUID()
                    }
                }.disabled(session.metadata == nil)
                IconButton(symbol: "xmark", help: L10n.text("Hide Info · I")) { session.showInspector = false }
            }.padding(18)
            Theme.line.frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let metadata = session.metadata {
                        exposureCards(metadata)
                        ForEach(metadata.sections) { section in sectionView(section) }
                        DisclosureGroup(isExpanded: $showRaw) {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(metadata.rawSections) { section in sectionView(section) }
                            }.padding(.top, 14)
                        } label: {
                            Text(L10n.text("All Metadata")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }.tint(Theme.secondary)
                    } else if session.readingMetadata {
                        HStack(spacing: 10) { ProgressView().controlSize(.small); Text(L10n.text("Reading details…")) }
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.vertical, 24)
                    } else {
                        Text(L10n.resolve(session.metadataError ?? .key("Open an image to see its details.")))
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.vertical, 24)
                    }
                }.padding(18)
            }
        }
        .foregroundStyle(Theme.text)
        .frame(width: 300)
        .modifier(PanelSurface())
        .task(id: copyFeedbackID) {
            guard copyFeedbackID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            copied = false
        }
        .onChange(of: session.current?.revision) { _, _ in copied = false; copyFeedbackID = nil }
        .onDisappear { copied = false; copyFeedbackID = nil }
    }

    private func exposureCards(_ metadata: ImageMetadata) -> some View {
        HStack(spacing: 6) {
            exposureCard(L10n.text("Aperture"), MetadataFormatter.aperture(metadata.aperture))
            exposureCard(L10n.text("Shutter"), MetadataFormatter.exposure(metadata.exposure).replacingOccurrences(of: " s", with: ""))
            exposureCard(L10n.text("ISO"), metadata.iso.map(String.init) ?? "—")
        }
    }

    private func exposureCard(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private func sectionView(_ section: MetadataSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.resolve(section.title)).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent.opacity(0.75))
            ForEach(section.entries) { field in
                HStack(alignment: .top, spacing: 12) {
                    Text(L10n.resolve(field.label)).foregroundStyle(Theme.secondary).frame(width: 65, alignment: .leading)
                    Text(L10n.resolve(field.value)).foregroundStyle(Theme.text.opacity(0.87)).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .contextMenu { Button(L10n.text("Copy")) { Theme.copy(L10n.resolve(field.value)) } }
                }.font(.system(size: 11)).lineSpacing(4)
            }
        }
    }
}
