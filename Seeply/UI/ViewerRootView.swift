import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ViewerRootView: View {
    @ObservedObject var session: ViewerSession
    @ObservedObject var viewport: ViewportController
    @ObservedObject private var preferences = Preferences.shared
    @State private var dropTargeted = false
    @StateObject private var dropLoader = FileDropLoader()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if session.isImmersive {
                canvas
                    .overlay(alignment: .top) { if !session.showGrid { floatingHeader } }
                    .overlay(alignment: .bottom) { if !session.showGrid { floatingBottom } }
            } else {
                VStack(spacing: 0) {
                    ViewerHeader(session: session, viewport: viewport)
                    canvas
                    if session.showFilmstrip && session.items.count > 1 { Filmstrip(session: session) }
                    ViewerFooter(session: session, viewport: viewport)
                }
            }
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .padding(10).background(Theme.accent.opacity(0.035)).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(.container, edges: session.isFullscreen ? [] : .top)
        .environment(\.locale, L10n.locale)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.chrome.isVisible(.header))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.chrome.isVisible(.bottom))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            dropLoader.load(providers) { [weak session] urls in
                guard let session else { return }
                if urls.isEmpty {
                    session.errorMessage = .key("Unable to read the dropped files. Try dropping them again, or choose Open Images.")
                } else {
                    session.open(urls)
                }
            }
        }
        .onDisappear { dropLoader.cancel() }
    }

    private var floatingHeader: some View {
        hoverRegion(.header) {
            ViewerHeader(session: session, viewport: viewport, floating: true)
                .modifier(PanelSurface(radius: 12))
                .padding(.horizontal, 18).padding(.top, 14)
        }
        .frame(height: ViewerLayoutMetrics.headerHeight + 14)
    }

    private var floatingBottom: some View {
        hoverRegion(.bottom) {
            VStack(spacing: 8) {
                if session.showFilmstrip && session.items.count > 1 {
                    Filmstrip(session: session).clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: 640)
                }
                ViewerFooter(session: session, viewport: viewport, floating: true)
                    .modifier(PanelSurface(radius: 8)).frame(maxWidth: 640)
            }.padding(16)
        }
        .frame(height: 32 + ViewerLayoutMetrics.footerHeight +
            (session.showFilmstrip && session.items.count > 1 ? ViewerLayoutMetrics.filmstripHeight + 8 : 0))
    }

    /// Keep an invisible hover surface mounted at each edge. Only its contents
    /// fade: hidden controls cannot take clicks or accessibility focus, while
    /// their regions remain available to reveal them without moving the image.
    private func hoverRegion<Content: View>(_ region: ChromeRegion, @ViewBuilder content: () -> Content) -> some View {
        let visible = session.chrome.isVisible(region)
        return ZStack {
            Color.clear.allowsHitTesting(false)
            content()
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)
        }
        .background { ChromeHoverTracker { session.setChromeHovered(region, $0) } }
    }

    private var canvas: some View {
        ZStack {
            ImageCanvasRepresentable(session: session, viewport: viewport)
                .clipped()
            if session.items.isEmpty && !session.isOpening {
                if session.isFilteredEmpty { FilteredEmptyState(session: session) }
                else { EmptyState(session: session) }
            }
            if session.loading || session.isOpening {
                ProgressView().controlSize(.small).padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let message = session.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 26)).foregroundStyle(Theme.accent)
                    Text(L10n.text("Unable to Open Image")).font(.system(size: 15, weight: .medium))
                    Text(L10n.resolve(message)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                    HStack(spacing: 16) {
                        Button(L10n.text("Close")) { session.errorMessage = nil }
                        Button(L10n.text("Choose Again…")) { session.errorMessage = nil; session.onOpen?(false) }.buttonStyle(.borderedProminent)
                    }
                }.padding(28).modifier(PanelSurface()).foregroundStyle(Theme.text)
            }
            if session.showGrid { ContactSheet(session: session) }
        }
        .overlay(alignment: .bottom) {
            if !session.showGrid {
                VStack(spacing: 8) {
                    if preferences.showPalette && session.image != nil {
                        ColorPaletteBar(session: session).id(session.current?.revision)
                    }
                    if preferences.showSummary, let text = session.metadata?.summary, !text.isEmpty {
                        Text(text).font(.system(size: 10, weight: .regular, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .foregroundStyle(Theme.text.opacity(0.65))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(Color.black.opacity(0.40), in: Capsule())
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, overlayBottomInset)
            }
        }
        .overlay(alignment: .topTrailing) {
            if session.showInspector && !session.showGrid && !session.isFilteredEmpty {
                ExifInspector(session: session)
                    .padding(16).padding(.top, session.isImmersive ? ViewerLayoutMetrics.headerHeight + 14 : 0)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overlayBottomInset: CGFloat {
        guard session.isImmersive && session.chrome.isVisible(.bottom) else { return 12 }
        return 16 + ViewerLayoutMetrics.footerHeight + 12 +
            (session.showFilmstrip && session.items.count > 1 ? ViewerLayoutMetrics.filmstripHeight + 8 : 0)
    }
}

@MainActor
struct EmptyState: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    @ObservedObject var session: ViewerSession
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Theme.accent.opacity(0.035)).frame(width: 98, height: 98)
                Image(systemName: "viewfinder").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Theme.accent.opacity(0.8))
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
            }.padding(.bottom, 30)
            Text(L10n.text("Open a photo.")).font(.system(size: 27, weight: .light)).tracking(2).foregroundStyle(Theme.text)
            Text(L10n.text("Drop a photo or folder and let the image take center stage."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.top, 12)
            HStack(spacing: 12) {
                Button { session.onOpen?(false) } label: {
                    HStack(spacing: 8) { Image(systemName: "plus"); Text(L10n.text("Open Images")) }
                        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 10)
                        .foregroundStyle(Color.black.opacity(0.85)).background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
                Button { session.onOpen?(true) } label: {
                    Text(L10n.text("Open Folder")).font(.system(size: 12)).padding(.horizontal, 17).padding(.vertical, 10)
                        .foregroundStyle(Theme.text.opacity(0.75))
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                }.buttonStyle(.plain)
            }.padding(.top, 30)
            Button(L10n.text("Try the demo images")) { session.onDemo?() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.top, 20)
            HStack(spacing: 24) {
                hint("⌘ O", L10n.text("Open"))
                hint("← →", L10n.text("Navigate"))
                hint("I", L10n.text("Info"))
            }.padding(.top, 60)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line))
            Text(title).font(.system(size: 10)).foregroundStyle(Theme.secondary.opacity(0.65))
        }
    }
}
