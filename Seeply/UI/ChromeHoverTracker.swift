import AppKit
import SwiftUI

/// Tracks an edge without becoming a mouse-down target over the photo or EXIF.
@MainActor
struct ChromeHoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView(frame: .zero)
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
        view.synchronizePointerLater()
    }

    static func dismantleNSView(_ view: TrackingView, coordinator: ()) {
        view.onHover?(false)
        view.onHover = nil
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        private var tracking: NSTrackingArea?
        private var hovered = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            // An explicit rect continues tracking while the visible controls
            // overlap this background view. It never participates in hit tests.
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                      owner: self, userInfo: nil)
            tracking = area
            addTrackingArea(area)
            synchronizePointerLater()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            synchronizePointerLater()
        }

        override func mouseEntered(with event: NSEvent) { synchronizePointer() }
        override func mouseExited(with event: NSEvent) { synchronizePointer() }

        func synchronizePointerLater() {
            // Layout/SwiftUI updates may attach a region beneath a stationary
            // pointer. Defer the published state change until layout completes.
            DispatchQueue.main.async { [weak self] in self?.synchronizePointer() }
        }

        private func synchronizePointer() {
            let inside: Bool
            if let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor {
                inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
            } else { inside = false }
            // Panning a photo across an edge does not pop a bar over the drag.
            guard !inside || NSEvent.pressedMouseButtons == 0 else { return }
            guard hovered != inside else { return }
            hovered = inside
            onHover?(inside)
        }
    }
}
