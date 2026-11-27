import AppKit
import Combine

@MainActor
final class ViewportController: ObservableObject {
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var pan: CGSize = .zero
    @Published private(set) var quarterTurns = 0
    @Published private(set) var isFitted = true
    private(set) var imagePixels: CGSize = .zero
    private(set) var viewportSize: CGSize = .zero
    private(set) var backingScale: CGFloat = 2
    var padding: CGFloat = ViewerLayoutMetrics.canvasPadding
    var onResolutionNeeded: ((CGFloat) -> Void)?
    var allowUpscaling: Bool { Preferences.shared.allowUpscaling }
    var rotatedPixels: CGSize { ViewportGeometry.rotatedSize(imagePixels, quarterTurns: quarterTurns) }
    var percentLabel: String { "\(Int((zoom * 100).rounded()))%" }

    func setImage(_ pixels: CGSize, reset: Bool) {
        imagePixels = pixels
        quarterTurns = 0
        pan = .zero
        if reset {
            fit()
        } else if isFitted { fit() } else { constrainPan() }
    }

    func setViewport(_ size: CGSize, scale: CGFloat) {
        guard size != viewportSize || scale != backingScale else { return }
        viewportSize = size
        backingScale = max(1, scale)
        if isFitted { fit() } else { constrainPan(); onResolutionNeeded?(zoom) }
    }

    func fit() {
        isFitted = true
        zoom = ViewportGeometry.fitZoom(imagePixels: rotatedPixels, viewport: viewportSize,
                                        backingScale: backingScale, padding: padding, allowUpscaling: allowUpscaling)
        pan = .zero
        onResolutionNeeded?(zoom)
    }

    func actualSize(at anchor: CGPoint? = nil) { setZoom(1, anchor: anchor) }

    func setZoom(_ newValue: CGFloat, anchor: CGPoint? = nil) {
        guard newValue.isFinite else { return }
        let next = min(ViewportGeometry.maximumZoom, max(ViewportGeometry.minimumZoom, newValue))
        let center = anchor ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        pan = ViewportGeometry.anchoredPan(pan, anchor: center, viewport: viewportSize, oldZoom: zoom, newZoom: next)
        zoom = next
        isFitted = false
        constrainPan()
        onResolutionNeeded?(zoom)
    }

    func translate(x: CGFloat, y: CGFloat) {
        pan = CGSize(width: pan.width + x, height: pan.height + y)
        constrainPan()
    }

    func rotate() {
        quarterTurns = (quarterTurns + 1) % 4
        pan = .zero
        if isFitted { fit() } else { constrainPan() }
    }

    private func constrainPan() {
        let next = ViewportGeometry.clampedPan(pan, imagePixels: rotatedPixels, viewport: viewportSize,
                                               zoom: zoom, backingScale: backingScale)
        if pan != next { pan = next }
    }
}
