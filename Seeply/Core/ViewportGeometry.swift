import Foundation

/// All zoom values express image pixels per display pixel: 1 is a true 100% view.
enum ViewportGeometry {
    static let minimumZoom: CGFloat = 0.002
    static let maximumZoom: CGFloat = 32

    static func rotatedSize(_ size: CGSize, quarterTurns: Int) -> CGSize {
        quarterTurns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    }

    static func fitZoom(imagePixels: CGSize, viewport: CGSize, backingScale: CGFloat,
                        padding: CGFloat, allowUpscaling: Bool) -> CGFloat {
        guard imagePixels.width > 0, imagePixels.height > 0,
              viewport.width > 0, viewport.height > 0, backingScale > 0 else { return 1 }
        let width = max(1, viewport.width - padding * 2) * backingScale
        let height = max(1, viewport.height - padding * 2) * backingScale
        let fit = min(width / imagePixels.width, height / imagePixels.height)
        return min(maximumZoom, max(minimumZoom, allowUpscaling ? fit : min(1, fit)))
    }

    static func clampedPan(_ pan: CGSize, imagePixels: CGSize, viewport: CGSize,
                           zoom: CGFloat, backingScale: CGFloat) -> CGSize {
        let scale = max(1, backingScale)
        let limitX = max(0, (imagePixels.width * zoom / scale - viewport.width) / 2)
        let limitY = max(0, (imagePixels.height * zoom / scale - viewport.height) / 2)
        return CGSize(width: min(limitX, max(-limitX, pan.width)),
                      height: min(limitY, max(-limitY, pan.height)))
    }

    /// Keeps the image point beneath the cursor stationary before edge clamping.
    static func anchoredPan(_ pan: CGSize, anchor: CGPoint, viewport: CGSize,
                            oldZoom: CGFloat, newZoom: CGFloat) -> CGSize {
        guard oldZoom > 0 else { return .zero }
        let dx = anchor.x - viewport.width / 2
        let dy = anchor.y - viewport.height / 2
        let ratio = newZoom / oldZoom
        return CGSize(width: dx - (dx - pan.width) * ratio,
                      height: dy - (dy - pan.height) * ratio)
    }

    static func fittedWindow(imagePixels: CGSize, zoom: CGFloat, backingScale: CGFloat,
                             chromeHeight: CGFloat, visibleFrame: CGRect,
                             currentFrame: CGRect) -> CGRect {
        let scale = max(1, backingScale)
        let ideal = CGSize(width: max(360, imagePixels.width * zoom / scale),
                           height: max(240, imagePixels.height * zoom / scale + chromeHeight))
        // Window Fit changes only the window. Oversized images remain at their
        // requested zoom and can be panned inside the screen-limited viewport.
        let size = CGSize(width: min(visibleFrame.width, ideal.width),
                          height: min(visibleFrame.height, ideal.height))
        let x = min(visibleFrame.maxX - size.width,
                    max(visibleFrame.minX, currentFrame.midX - size.width / 2))
        let y = min(visibleFrame.maxY - size.height,
                    max(visibleFrame.minY, currentFrame.midY - size.height / 2))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
