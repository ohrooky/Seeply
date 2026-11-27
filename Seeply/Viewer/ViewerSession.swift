import AppKit
import Combine

@MainActor
final class ViewerSession: ObservableObject {
    let id = UUID()
    let viewport = ViewportController()
    @Published private(set) var items: [ImageItem] = []
    @Published private(set) var index = 0
    @Published private(set) var image: DecodedImage?
    @Published private(set) var metadata: ImageMetadata?
    @Published private(set) var palette: PhotoPalette?
    @Published private(set) var loadingPalette = false
    @Published private(set) var paletteError: DisplayText?
    @Published private(set) var loading = false
    @Published private(set) var readingMetadata = false
    @Published private(set) var isOpening = false
    @Published var errorMessage: DisplayText?
    @Published private(set) var metadataError: DisplayText?
    @Published private(set) var folder: URL?
    @Published private(set) var needsFolderAccess = false
    @Published var showInspector = false { didSet { if showInspector { loadMetadata() } } }
    @Published var showFilmstrip = true { didSet { if isWindowFitted { onImageChanged?() } } }
    @Published var showGrid = false
    @Published var isLightbox = false { didSet { updateChromeMode() } }
    @Published var isFrameless = false { didSet { updateChromeMode() } }
    @Published var isFullscreen = false { didSet { updateChromeMode() } }
    @Published var isWindowFitted = false
    @Published private(set) var chrome = ChromeAutoHide()
    var onWindowFit: (() -> Void)?
    var onImageChanged: (() -> Void)?
    var onTitleChanged: ((String) -> Void)?
    var onOpen: ((Bool) -> Void)?
    var onEscape: (() -> Void)?
    var onFrameless: (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onLightbox: (() -> Void)?
    var onClose: (() -> Void)?
    var onDemo: (() -> Void)?
    var onFileTypeSettings: (() -> Void)?

    private var loadTask: Task<Void, Never>?
    private var upgradeTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var paletteTask: Task<Void, Never>?
    private var paletteID = UUID()
    private var prefetchTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var hideControlsTask: Task<Void, Never>?
    private var fileTypesSubscription: AnyCancellable?
    // A path/attribute inventory, never a decoding queue. Retain its access
    // leases so re-enabling a type also works after the visible list is empty.
    private var sourceItems: [ImageItem] = []
    private var selectionAnchor: URL?
    private var openID = UUID()
    private var loadID = UUID()
    private var metadataID = UUID()
    private var resolutionRequest = 0
    private var isClosed = false

    var current: ImageItem? { items.indices.contains(index) ? items[index] : nil }
    var isImmersive: Bool { isLightbox || isFrameless || isFullscreen }
    var counter: String { items.isEmpty ? "" : "\(index + 1) / \(items.count)" }
    var isFilteredEmpty: Bool { !sourceItems.isEmpty && items.isEmpty }

    init() {
        viewport.onResolutionNeeded = { [weak self] zoom in self?.requestResolution(zoom) }
        fileTypesSubscription = Preferences.shared.$fileTypes.removeDuplicates().dropFirst().sink { [weak self] filter in
            self?.applyFileTypes(filter)
        }
    }

    func open(_ urls: [URL], selected: URL? = nil) {
        guard !isClosed else { return }
        openTask?.cancel()
        let request = UUID()
        openID = request
        isOpening = true
        openTask = Task { [weak self] in
            do {
                let selection = try await FileAccess.open(urls, selectedURL: selected)
                try Task.checkCancellation()
                guard let self, self.openID == request, !self.isClosed else { return }
                self.sourceItems = selection.items
                self.folder = selection.folder
                self.needsFolderAccess = selection.needsFolderAccess
                self.selectionAnchor = selection.selectedURL
                self.showGrid = false
                self.isOpening = false
                // Read the latest filter after the asynchronous directory scan.
                self.applyFileTypes(Preferences.shared.fileTypes, preserveCurrent: false)
            } catch is CancellationError { }
            catch {
                guard let self, self.openID == request, !self.isClosed, !Task.isCancelled else { return }
                self.isOpening = false
                self.errorMessage = .error(error)
            }
        }
    }

    private func applyFileTypes(_ filter: ImageFileFilter, preserveCurrent: Bool = true) {
        guard !isClosed else { return }
        let previous = current
        let hadFilmstrip = showFilmstrip && items.count > 1
        let preferred = preserveCurrent ? previous?.url ?? selectionAnchor : selectionAnchor
        let selection = filter.selection(from: sourceItems.map(\.url), preferredURL: preferred)
        let included = Set(selection.urls)
        prefetchTask?.cancel()
        prefetchTask = nil
        items = sourceItems.filter { included.contains($0.url) }
        index = selection.selectedIndex ?? 0
        if items.count < 2 { showGrid = false }
        errorMessage = nil
        guard let item = current else {
            clearDisplayedImage()
            onTitleChanged?("")
            return
        }
        if preserveCurrent, item == previous, image != nil || loading {
            // Keep decoded pixels, EXIF, rotation, zoom and pan intact.
            if isWindowFitted, hadFilmstrip != (showFilmstrip && items.count > 1) { onImageChanged?() }
            if image != nil { prefetchNeighbors(dimension: resolutionRequest) }
        } else { select(index) }
    }

    private func clearDisplayedImage() {
        loadTask?.cancel(); upgradeTask?.cancel(); metadataTask?.cancel(); prefetchTask?.cancel()
        loadID = UUID()
        metadataID = UUID()
        resetPalette()
        image = nil
        metadata = nil
        metadataError = nil
        readingMetadata = false
        loading = false
        resolutionRequest = 0
    }

    func select(_ newIndex: Int) {
        guard items.indices.contains(newIndex) else { return }
        loadTask?.cancel(); upgradeTask?.cancel(); metadataTask?.cancel(); prefetchTask?.cancel()
        resetPalette()
        index = newIndex
        let item = items[newIndex]
        selectionAnchor = item.url
        let request = UUID()
        loadID = request
        image = nil
        metadata = nil
        metadataError = nil
        readingMetadata = false
        loading = true
        errorMessage = nil
        resolutionRequest = 0
        onTitleChanged?(item.name)
        revealControls()
        if showInspector || Preferences.shared.showSummary { loadMetadata() }
        let previewDimension = min(4096, max(1536, Int(max(viewport.viewportSize.width, viewport.viewportSize.height) * viewport.backingScale)))
        loadTask = Task { [weak self] in
            do {
                let decoded = try await ImagePipeline.shared.image(for: item, dimension: previewDimension)
                try Task.checkCancellation()
                guard let self, self.loadID == request else { return }
                self.image = decoded
                self.resolutionRequest = decoded.requestedDimension
                self.updatePaletteVisibility()
                self.viewport.setImage(decoded.sourcePixels, reset: !Preferences.shared.rememberZoom)
                self.onImageChanged?()
                self.loading = false
                self.prefetchNeighbors(dimension: previewDimension)
            } catch is CancellationError { }
            catch {
                guard let self, self.loadID == request, !Task.isCancelled else { return }
                self.loading = false
                self.errorMessage = .error(error)
            }
        }
    }

    func navigate(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = index + delta
        if Preferences.shared.loopNavigation {
            select((next % items.count + items.count) % items.count)
        } else if items.indices.contains(next) { select(next) }
    }

    func loadMetadata() {
        guard let item = current, metadata == nil else { return }
        metadataTask?.cancel()
        let request = UUID()
        metadataID = request
        readingMetadata = true
        metadataError = nil
        metadataTask = Task { [weak self] in
            do {
                let result = try await MetadataService.shared.metadata(for: item)
                try Task.checkCancellation()
                guard let self, self.metadataID == request else { return }
                self.metadata = result
                self.readingMetadata = false
            } catch is CancellationError { }
            catch {
                guard let self, self.metadataID == request, !Task.isCancelled else { return }
                self.readingMetadata = false
                self.metadataError = .error(error)
            }
        }
    }

    func updatePaletteVisibility() {
        guard Preferences.shared.showPalette else { resetPalette(); return }
        guard let item = current, let preview = image, palette == nil, !loadingPalette else { return }
        let request = UUID()
        paletteID = request
        loadingPalette = true
        paletteError = nil
        paletteTask = Task { [weak self] in
            do {
                let result = try await PaletteService.shared.palette(for: item, preview: preview)
                try Task.checkCancellation()
                guard let self, self.paletteID == request else { return }
                self.palette = result
                self.loadingPalette = false
            } catch is CancellationError { }
            catch {
                guard let self, self.paletteID == request, !Task.isCancelled else { return }
                self.loadingPalette = false
                self.paletteError = .error(error)
            }
        }
    }

    private func resetPalette() {
        paletteTask?.cancel()
        paletteTask = nil
        paletteID = UUID()
        palette = nil
        loadingPalette = false
        paletteError = nil
    }

    func requestResolution(_ zoom: CGFloat) {
        guard let image, let item = current else { return }
        let needed = Int(ceil(max(image.sourcePixels.width, image.sourcePixels.height) * min(1, zoom)))
        guard needed > resolutionRequest + 256 else { return }
        upgradeTask?.cancel()
        let request = loadID
        upgradeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                let decoded = try await ImagePipeline.shared.image(for: item, dimension: needed)
                try Task.checkCancellation()
                guard let self, self.loadID == request else { return }
                self.image = decoded
                self.resolutionRequest = decoded.requestedDimension
            } catch { /* Keep the valid preview if a higher-resolution decode fails. */ }
        }
    }

    private func prefetchNeighbors(dimension: Int) {
        let neighbors = [index + 1, index - 1].filter { items.indices.contains($0) }.map { items[$0] }
        prefetchTask = Task {
            for item in neighbors {
                guard !Task.isCancelled else { break }
                _ = try? await ImagePipeline.shared.image(for: item, dimension: dimension, prefetch: true)
            }
        }
    }

    func revealControls() {
        guard chrome.mode == .immersive else { return }
        updateChrome { state, now in state.pointerActivity(at: now) }
    }

    private func updateChromeMode() {
        let mode: ChromeAutoHide.Mode = isFrameless ? .frameless : (isImmersive ? .immersive : .windowed)
        updateChrome { state, now in state.setMode(mode, at: now) }
    }

    func setChromeHovered(_ region: ChromeRegion, _ hovered: Bool) {
        updateChrome { state, now in state.setHovered(region, hovered, at: now) }
    }

    private func updateChrome(_ change: (inout ChromeAutoHide, TimeInterval) -> Void) {
        guard !isClosed else { return }
        var next = chrome
        change(&next, ProcessInfo.processInfo.systemUptime)
        if next != chrome { chrome = next }
        scheduleChromeHide()
    }

    private func scheduleChromeHide() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
        guard !isClosed, let deadline = chrome.nextHideTime else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        hideControlsTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.updateChrome { state, now in state.hideExpired(at: now) }
        }
    }

    func toggleInspector() { showInspector.toggle(); revealControls() }

    func rotate() {
        viewport.rotate()
        if isWindowFitted { onImageChanged?() }
    }

    func refresh() {
        let preferred = current?.url ?? selectionAnchor
        if let folder, !needsFolderAccess { open([folder], selected: preferred) }
        else { open(sourceItems.map(\.url), selected: preferred) }
    }

    func revealInFinder() {
        if let url = current?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func copyImage() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image.image, size: .zero)])
    }

    func close() {
        isClosed = true
        fileTypesSubscription?.cancel()
        resetPalette()
        loadTask?.cancel(); upgradeTask?.cancel(); metadataTask?.cancel()
        prefetchTask?.cancel(); openTask?.cancel(); hideControlsTask?.cancel()
        image = nil
        items = []
        sourceItems = []
    }
}
