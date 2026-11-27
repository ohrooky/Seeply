import AppKit
import SwiftUI
import Combine

@MainActor
final class ViewerWindow: NSWindow {
    weak var session: ViewerSession?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if session?.handleKey(event) != true { super.keyDown(with: event) }
    }
}

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate, NSOpenSavePanelDelegate {
    let session = ViewerSession()
    var onClosed: ((UUID) -> Void)?
    private var transitioningFullscreen = false
    private var frameBeforeWindowFit: NSRect?
    private var windowFitZoom: CGFloat?
    private var preferencesSubscription: AnyCancellable?
    private var zoomSubscription: AnyCancellable?
    private var fileTypesSubscription: AnyCancellable?

    init() {
        let window = ViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Seeply"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.canvasNSColor
        window.minSize = NSSize(width: 360, height: 240)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: ViewerRootView(session: session, viewport: session.viewport))
        wireActions()
        zoomSubscription = session.viewport.$zoom.dropFirst().sink { [weak self] zoom in
            guard let self, self.session.isWindowFitted, !self.session.loading else { return }
            self.windowFitZoom = zoom
        }
        let preferences = Preferences.shared
        fileTypesSubscription = preferences.$fileTypes.removeDuplicates().dropFirst().sink { [weak self] _ in
            // @Published emits before the stored preference changes.
            DispatchQueue.main.async {
                (self?.window?.attachedSheet as? NSOpenPanel)?.validateVisibleColumns()
            }
        }
        // Language changes only relabel the UI. They must not refit the canvas
        // or restart metadata/palette work for the photo already on screen.
        preferencesSubscription = Publishers.CombineLatest4(preferences.$allowUpscaling, preferences.$showSummary,
                                                            preferences.$showPalette, preferences.$background)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
            }
            .dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.session.viewport.isFitted { self.session.viewport.fit() }
                    if Preferences.shared.showSummary { self.session.loadMetadata() }
                    self.session.updatePaletteVisibility()
                    self.window?.backgroundColor = Theme.canvasNSColor
                }
            }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func wireActions() {
        (window as? ViewerWindow)?.session = session
        session.onWindowFit = { [weak self] in self?.fitWindow() }
        session.onImageChanged = { [weak self] in
            guard let self, self.session.isWindowFitted else { return }
            self.fitWindow(preserveZoom: true)
        }
        session.onTitleChanged = { [weak self] name in
            self?.window?.title = name.isEmpty ? "Seeply" : name + " — Seeply"
            self?.window?.representedURL = self?.session.current?.url
        }
        session.onOpen = { [weak self] folder in self?.openPanel(folder: folder) }
        session.onEscape = { [weak self] in self?.escape() }
        session.onFrameless = { [weak self] in self?.toggleFrameless() }
        session.onFullscreen = { [weak self] in self?.toggleFullscreen() }
        session.onLightbox = { [weak self] in self?.toggleLightbox() }
        session.onClose = { [weak self] in self?.close() }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        if let root = window?.contentView, let canvas = findCanvas(root) { window?.makeFirstResponder(canvas) }
    }

    private func findCanvas(_ view: NSView) -> ImageCanvas? {
        if let canvas = view as? ImageCanvas { return canvas }
        return view.subviews.lazy.compactMap(findCanvas).first
    }

    func openPanel(folder: Bool) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.delegate = self
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = !folder
        panel.allowedContentTypes = folder ? [] : FileAccess.imageTypes
        panel.directoryURL = session.folder
        localize(panel, folder: folder)
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK else { return }
            self?.session.open(panel.urls, selected: folder ? self?.session.current?.url : nil)
        }
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { return true }
        return Preferences.shared.fileTypes.allows(url) && FileAccess.supports(url)
    }

    func openDemo() {
        guard let url = Bundle.main.url(forResource: "Dune", withExtension: "jpg", subdirectory: "Samples") else {
            session.errorMessage = .key("The demo images could not be found. Reinstall the app, or use Open Images to view your own photos.")
            return
        }
        session.open([url.deletingLastPathComponent()], selected: url)
    }

    private func localize(_ panel: NSOpenPanel, folder: Bool) {
        panel.title = L10n.text(folder ? "Open Folder" : "Open Images")
        panel.prompt = L10n.text(folder ? "Open Folder" : "Open Images")
        panel.message = L10n.text(folder ? "Grant access to a folder to browse its images with the arrow keys." : "Select one or more enabled image types.")
    }

    func refreshLocalization() {
        if let panel = window?.attachedSheet as? NSOpenPanel { localize(panel, folder: panel.canChooseDirectories) }
        if let root = window?.contentView { findCanvas(root)?.refreshAccessibilityText() }
    }

    func toggleLightbox() {
        session.isLightbox.toggle()
        updateChrome()
        session.revealControls()
    }

    func toggleFrameless() {
        guard !transitioningFullscreen else { return }
        session.isFrameless.toggle()
        updateChrome()
        session.revealControls()
    }

    func updateChrome() {
        guard let window else { return }
        let savedFrame = window.frame
        if !session.isFullscreen && !transitioningFullscreen {
            window.styleMask = session.isFrameless ? [.borderless, .closable, .miniaturizable, .resizable] :
                [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        }
        window.standardWindowButton(.closeButton)?.isHidden = session.isImmersive
        window.standardWindowButton(.miniaturizeButton)?.isHidden = session.isImmersive
        window.standardWindowButton(.zoomButton)?.isHidden = session.isImmersive
        window.setFrame(savedFrame, display: true)
        session.viewport.padding = session.isWindowFitted ? 0 : ViewerLayoutMetrics.canvasPadding
        if session.viewport.isFitted { session.viewport.fit() }
        if session.isWindowFitted { fitWindow(preserveZoom: true) }
    }

    func toggleFullscreen() {
        guard let window, !transitioningFullscreen else { return }
        if !session.isFullscreen && session.isFrameless {
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        }
        window.toggleFullScreen(nil)
    }

    func fitWindow(preserveZoom: Bool = false) {
        guard let window, session.image != nil, !session.isFullscreen, !transitioningFullscreen,
              let screen = window.screen else { return }
        if !session.isWindowFitted { frameBeforeWindowFit = window.frame }
        if !preserveZoom || windowFitZoom == nil { windowFitZoom = session.viewport.zoom }
        let requestedZoom = windowFitZoom ?? session.viewport.zoom
        session.isWindowFitted = true
        session.viewport.padding = 0
        let chrome = ViewerLayoutMetrics.chromeHeight(immersive: session.isImmersive,
                            filmstrip: session.showFilmstrip, imageCount: session.items.count)
        let nativeChrome = window.frame.height - (window.contentView?.frame.height ?? window.frame.height)
        let target = ViewportGeometry.fittedWindow(imagePixels: session.viewport.rotatedPixels,
            zoom: requestedZoom, backingScale: window.backingScaleFactor,
            chromeHeight: chrome + nativeChrome, visibleFrame: screen.visibleFrame.insetBy(dx: 12, dy: 12),
            currentFrame: window.frame)
        // Lock the requested image scale before AppKit triggers a viewport resize.
        // A screen-sized limit crops the visible area; it must not shrink the image.
        session.viewport.setZoom(requestedZoom)
        window.setFrame(target, display: true)
    }

    func restoreWindow() {
        guard let frame = frameBeforeWindowFit, !session.isFullscreen else { return }
        session.isWindowFitted = false
        session.viewport.padding = ViewerLayoutMetrics.canvasPadding
        window?.setFrame(frame, display: true)
        frameBeforeWindowFit = nil
        windowFitZoom = nil
    }

    func escape() {
        if session.showGrid { session.showGrid = false }
        else if session.showInspector { session.showInspector = false }
        else if session.isLightbox { toggleLightbox() }
        else if session.isFullscreen { toggleFullscreen() }
        else if session.isFrameless { toggleFrameless() }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        session.isWindowFitted = false
        session.viewport.padding = ViewerLayoutMetrics.canvasPadding
    }
    func windowDidBecomeKey(_ notification: Notification) {
        session.revealControls()
        DispatchQueue.main.async { [weak self] in
            guard let self, let root = self.window?.contentView, let canvas = self.findCanvas(root) else { return }
            self.window?.makeFirstResponder(canvas)
        }
    }
    func windowWillEnterFullScreen(_ notification: Notification) { transitioningFullscreen = true }
    func windowDidEnterFullScreen(_ notification: Notification) {
        transitioningFullscreen = false
        session.isFullscreen = true
        updateChrome()
        session.revealControls()
    }
    func windowWillExitFullScreen(_ notification: Notification) { transitioningFullscreen = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        transitioningFullscreen = false
        session.isFullscreen = false
        updateChrome()
        session.revealControls()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { transitioningFullscreen = false; updateChrome() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { transitioningFullscreen = false; updateChrome() }
    func windowWillClose(_ notification: Notification) {
        session.close()
        onClosed?(session.id)
    }
}
