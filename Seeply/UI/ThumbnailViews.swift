import AppKit
import SwiftUI

@MainActor
struct ThumbnailCell: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    let item: ImageItem
    let selected: Bool
    var grid = false
    let action: () -> Void
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.025))
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .padding(grid ? 6 : 3)
                    } else {
                        Image(systemName: failed ? "exclamationmark.triangle" : "photo")
                            .font(.system(size: grid ? 24 : 15)).foregroundStyle(Theme.secondary.opacity(0.4))
                    }
                }
                .frame(width: grid ? nil : 72, height: grid ? 150 : 54)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1.5))
                .padding(3)
                if grid {
                    Text(item.name).font(.system(size: 11)).foregroundStyle(selected ? Theme.accent : Theme.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.name)
        .accessibilityLabel(selected ? L10n.text("{name}, current image", ["name": item.name]) : item.name)
        .task(id: item.revision) {
            do {
                let result = try await ImagePipeline.shared.thumbnail(for: item)
                try Task.checkCancellation()
                image = NSImage(cgImage: result.image, size: .zero)
            } catch is CancellationError { }
            catch { failed = true }
        }
        .onDisappear { image = nil }
    }
}

@MainActor
struct Filmstrip: View {
    @ObservedObject var session: ViewerSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        ThumbnailCell(item: item, selected: session.index == index) { session.select(index) }.id(item.id)
                    }
                }.padding(.horizontal, 24).frame(height: ViewerLayoutMetrics.filmstripHeight)
            }
            .onChange(of: session.current?.id) { _, value in
                if let value {
                    if reduceMotion { proxy.scrollTo(value, anchor: .center) }
                    else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) } }
                }
            }
            .onAppear { if let value = session.current?.id { proxy.scrollTo(value, anchor: .center) } }
        }
        .frame(height: ViewerLayoutMetrics.filmstripHeight)
        .background(Theme.chrome.opacity(0.95))
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}

@MainActor
struct ContactSheet: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    @ObservedObject var session: ViewerSession
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Contact Sheet")).font(.system(size: 20, weight: .medium))
                    Text(L10n.imageCount(session.items.count)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                IconButton(symbol: "xmark", help: L10n.text("Back to Image · Esc")) { session.showGrid = false }
            }.padding(28)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 20)], spacing: 28) {
                        ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                            ThumbnailCell(item: item, selected: session.index == index, grid: true) {
                                session.select(index)
                                session.showGrid = false
                            }.id(item.id)
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
                }
                .onAppear { if let id = session.current?.id { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.chrome)
    }
}
