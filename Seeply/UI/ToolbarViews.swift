import SwiftUI

@MainActor
struct ViewerHeader: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    @ObservedObject var session: ViewerSession
    @ObservedObject var viewport: ViewportController
    var floating = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            contents(compact: false)
            contents(compact: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ViewerLayoutMetrics.headerHeight)
        .background(floating ? Color.clear : Theme.chrome)
        .overlay(alignment: .bottom) { if !floating { Theme.line.frame(height: 1) } }
    }

    private func contents(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 12) {
            if !floating { Color.clear.frame(width: 64) }
            if floating {
                IconButton(symbol: "xmark", help: L10n.text("Close Window · ⌘W")) { session.onClose?() }
            }
            if !compact {
                Text("Seeply").font(.system(size: 18, weight: .medium, design: .rounded)).tracking(1)
                    .foregroundStyle(Theme.text)
                Hairline()
                Text(session.current?.name ?? L10n.text("IMAGE VIEWER"))
                    .font(.system(size: session.current == nil ? 9 : 11, weight: .medium))
                    .tracking(session.current == nil ? 2 : 0)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .leading)
                    .overlay { WindowDragHandle() }
            } else {
                Text(session.current?.name ?? "Seeply")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .overlay { WindowDragHandle() }
            }
            Spacer(minLength: 6)
            if !compact {
                IconButton(symbol: "folder", help: L10n.text("Open Images · ⌘O")) { session.onOpen?(false) }
                Hairline()
            }
            HStack(spacing: 0) {
                IconButton(symbol: "chevron.left", help: L10n.text("Previous Image · ←")) { session.navigate(-1) }
                IconButton(symbol: "chevron.right", help: L10n.text("Next Image · →")) { session.navigate(1) }
            }.disabled(session.items.count < 2)
            if !compact {
                Hairline()
                Button { viewport.fit() } label: {
                    HStack(spacing: 5) {
                        Text(viewport.isFitted ? "FIT" : viewport.percentLabel)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10))
                    }
                    .foregroundStyle(viewport.isFitted ? Theme.accent : Theme.text)
                    .frame(minWidth: 53, minHeight: 30)
                }.buttonStyle(.plain).help(L10n.text("Fit Image to Window · 0"))
                Hairline()
                IconButton(symbol: "rectangle.on.rectangle", help: "Lightbox · L", active: session.isLightbox) {
                    session.onLightbox?()
                }
            }
            IconButton(symbol: "info.circle", help: L10n.text("Photo Info · I"), active: session.showInspector) { session.toggleInspector() }
            ViewerOptionsMenu(session: session, viewport: viewport)
        }
        .padding(.horizontal, floating ? 8 : 14)
        .frame(minWidth: compact ? 240 : 660, maxWidth: .infinity)
    }
}

@MainActor
struct ViewerOptionsMenu: View {
    @ObservedObject var session: ViewerSession
    @ObservedObject var viewport: ViewportController
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        Menu {
            Button(L10n.text("Open Images…")) { session.onOpen?(false) }
            Button(L10n.text("Open Folder…")) { session.onOpen?(true) }
            Divider()
            Button(L10n.text("Fit Image to Window    0")) { viewport.fit() }
            Button(L10n.text("Actual Pixels (100%)    1")) { viewport.actualSize() }
            Button(L10n.text("Fit Window to Image    W")) { session.onWindowFit?() }.disabled(session.image == nil || session.isFullscreen)
            Button(L10n.text("Rotate Clockwise    R")) { session.rotate() }.disabled(session.image == nil)
            Divider()
            Toggle("Lightbox    L", isOn: Binding(get: { session.isLightbox }, set: { _ in session.onLightbox?() }))
            Toggle("Frameless    B", isOn: Binding(get: { session.isFrameless }, set: { _ in session.onFrameless?() }))
            Button(L10n.text("Toggle Full Screen    F")) { session.onFullscreen?() }
            Divider()
            Toggle(L10n.text("Filmstrip    T"), isOn: $session.showFilmstrip)
            Toggle(L10n.text("Contact Sheet    G"), isOn: $session.showGrid)
            Toggle(L10n.text("Quick EXIF    E"), isOn: $preferences.showSummary)
            Toggle(L10n.text("Color Palette    P"), isOn: $preferences.showPalette)
            Divider()
            Button(L10n.text("Show in Finder")) { session.revealInFinder() }.disabled(session.current == nil)
            Button(L10n.text("Copy Displayed Image")) { session.copyImage() }.disabled(session.image == nil)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.7))
                .frame(width: 26, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.text("More Options"))
    }
}

@MainActor
struct ViewerFooter: View {
    @ObservedObject private var localizationPreferences = Preferences.shared
    @ObservedObject var session: ViewerSession
    @ObservedObject var viewport: ViewportController
    var floating = false

    var body: some View {
        HStack(spacing: 12) {
            if session.needsFolderAccess {
                Button { session.onOpen?(true) } label: {
                    Label(L10n.text("Browse This Folder"), systemImage: "folder.badge.plus")
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                Hairline()
            }
            Text(session.counter).monospacedDigit()
            if let image = session.image {
                Text("\(Int(image.sourcePixels.width)) × \(Int(image.sourcePixels.height))")
                if image.resolutionLimited {
                    Image(systemName: "viewfinder").help(L10n.text("Decoding resolution is limited for this large image to control memory use."))
                }
            }
            Spacer(minLength: 4)
            if session.image != nil {
                if !viewport.isFitted { Text(viewport.percentLabel).foregroundStyle(Theme.accent) }
                if session.isWindowFitted { Text("WINDOW FIT").tracking(1).foregroundStyle(Theme.accent.opacity(0.7)) }
            }
            if !floating { Text(L10n.text("← → Navigate")).foregroundStyle(Theme.secondary.opacity(0.6)) }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, floating ? 12 : 20)
        .frame(height: ViewerLayoutMetrics.footerHeight)
        .background(floating ? Color.clear : Theme.chrome)
    }
}
