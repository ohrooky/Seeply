import AppKit
import SwiftUI

@MainActor
struct ImageCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var session: ViewerSession
    @ObservedObject var viewport: ViewportController
    @ObservedObject var preferences = Preferences.shared

    func makeNSView(context: Context) -> ImageCanvas {
        let view = ImageCanvas()
        view.session = session
        return view
    }

    func updateNSView(_ view: ImageCanvas, context: Context) {
        view.session = session
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

@MainActor
final class ImageCanvas: NSView {
    weak var session: ViewerSession?
    private var tracking: NSTrackingArea?
    private var dragPoint: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // AppKit defaults to no clipping for apps linked against macOS 14+.
        // An oversized 100% image must never draw across sibling controls.
        clipsToBounds = true
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityRole(.image)
        refreshAccessibilityText()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refreshAccessibilityText() {
        setAccessibilityLabel(L10n.text("Image viewing area"))
        setAccessibilityHelp(L10n.text("Arrow keys navigate; 0 fits the image, 1 shows actual pixels, I opens photo info."))
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = session?.isLightbox == true ? NSColor.black : Theme.canvasNSColor
        background.setFill()
        bounds.fill()
        guard let session, let image = session.image,
              let context = NSGraphicsContext.current?.cgContext else { return }
        Self.drawImage(image, in: bounds, viewport: session.viewport, context: context)
    }

    /// The same rendering path is used by the view and the bitmap regression tests.
    /// Clip before any image transforms so zoom, pan and rotation cannot move it.
    static func drawImage(_ image: DecodedImage, in bounds: CGRect,
                          viewport: ViewportController, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds)
        let scale = viewport.zoom / viewport.backingScale
        let width = image.sourcePixels.width * scale
        let height = image.sourcePixels.height * scale
        var center = CGPoint(x: bounds.midX + viewport.pan.width, y: bounds.midY + viewport.pan.height)
        if viewport.zoom >= 1 && abs(viewport.zoom - viewport.zoom.rounded()) < 0.0001 {
            // Align integer zoom levels to physical pixels for sharp 100% inspection.
            let displayed = ViewportGeometry.rotatedSize(CGSize(width: width, height: height), quarterTurns: viewport.quarterTurns)
            center.x = ((center.x - displayed.width / 2) * viewport.backingScale).rounded() / viewport.backingScale + displayed.width / 2
            center.y = ((center.y - displayed.height / 2) * viewport.backingScale).rounded() / viewport.backingScale + displayed.height / 2
        }
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -CGFloat(viewport.quarterTurns) * .pi / 2)
        context.interpolationQuality = viewport.zoom >= 4 ? .none : .high
        context.draw(image.image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
    }

    override func layout() { super.layout(); updateViewportLater() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateViewportLater() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateViewportLater() }

    private func updateViewportLater() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.session?.viewport.setViewport(self.bounds.size, scale: self.window?.backingScaleFactor ?? 2)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        tracking = area
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: session?.image == nil ? .arrow : .openHand)
    }

    override func mouseMoved(with event: NSEvent) { session?.revealControls() }
    override func mouseEntered(with event: NSEvent) { session?.revealControls() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        session?.revealControls()
        guard let session else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, session.image != nil {
            if session.viewport.isFitted { session.viewport.actualSize(at: point) }
            else { session.viewport.fit() }
            return
        }
        if event.modifierFlags.contains(.option) || (session.isFrameless && session.viewport.isFitted) {
            window?.performDrag(with: event)
        } else {
            dragPoint = point
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previous = dragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        session?.viewport.translate(x: point.x - previous.x, y: point.y - previous.y)
        dragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        if dragPoint != nil { NSCursor.pop() }
        dragPoint = nil
    }

    override func magnify(with event: NSEvent) {
        guard let session, session.image != nil else { return }
        session.viewport.setZoom(session.viewport.zoom * (1 + event.magnification),
                                 anchor: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let session, session.image != nil else { return }
        if !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.command) {
            session.viewport.setZoom(session.viewport.zoom * exp(event.scrollingDeltaY * 0.025),
                                     anchor: convert(event.locationInWindow, from: nil))
        } else {
            session.viewport.translate(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
        }
    }

    override func swipe(with event: NSEvent) {
        if event.deltaX != 0 { session?.navigate(event.deltaX > 0 ? -1 : 1) }
    }

    override func keyDown(with event: NSEvent) {
        if session?.handleKey(event) != true { super.keyDown(with: event) }
    }
}

@MainActor
extension ViewerSession {
    /// Also used by NSWindow when a SwiftUI control passes an unhandled key up.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 123: navigate(-1); return true
        case 124: navigate(1); return true
        case 53: onEscape?(); return true
        case 115: select(0); return true
        case 119: select(items.count - 1); return true
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "i": toggleInspector()
        case "e": Preferences.shared.showSummary.toggle()
        case "p": Preferences.shared.showPalette.toggle()
        case "l", " ": onLightbox?()
        case "b": onFrameless?()
        case "w": onWindowFit?()
        case "f": onFullscreen?()
        case "g": if !items.isEmpty { showGrid.toggle() }
        case "t": showFilmstrip.toggle()
        case "r": rotate()
        case "0": viewport.fit()
        case "1": viewport.actualSize()
        case "+", "=": viewport.setZoom(viewport.zoom * 1.25)
        case "-": viewport.setZoom(viewport.zoom / 1.25)
        default: return false
        }
        return true
    }
}

/// A dedicated drag surface so moving a frameless window never steals a photo pan.
@MainActor
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) { }
    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
