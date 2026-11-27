import Foundation

enum ChromeRegion: CaseIterable, Hashable, Sendable {
    case header, bottom
}

/// Visibility and monotonic deadlines are independent of SwiftUI view lifetime.
/// Fading an overlay out never counts as the pointer leaving its hover region.
struct ChromeAutoHide: Equatable, Sendable {
    enum Mode: Equatable, Sendable { case windowed, immersive, frameless }
    static let framelessDelay: TimeInterval = 1.5
    static let immersiveDelay: TimeInterval = 2.6

    private(set) var mode: Mode = .windowed
    private(set) var hovered: Set<ChromeRegion> = []
    private var visible = Set(ChromeRegion.allCases)
    private var deadlines: [ChromeRegion: TimeInterval] = [:]

    var nextHideTime: TimeInterval? { deadlines.values.min() }
    func isVisible(_ region: ChromeRegion) -> Bool { visible.contains(region) }

    mutating func setMode(_ newMode: Mode, at now: TimeInterval) {
        guard mode != newMode else { return }
        mode = newMode
        visible = Set(ChromeRegion.allCases)
        deadlines.removeAll()
        switch mode {
        case .windowed:
            hovered.removeAll()
        case .immersive:
            pointerActivity(at: now)
        case .frameless:
            for region in ChromeRegion.allCases where !hovered.contains(region) {
                deadlines[region] = now + Self.framelessDelay
            }
        }
    }

    /// Lightbox/fullscreen retain their existing reveal-on-activity behavior.
    /// In Frameless, movement, clicks and keyboard navigation over the photo
    /// cannot reveal either bar; only entering that bar's region can do so.
    mutating func pointerActivity(at now: TimeInterval) {
        guard mode == .immersive else { return }
        visible = Set(ChromeRegion.allCases)
        deadlines.removeAll()
        if hovered.isEmpty {
            for region in ChromeRegion.allCases { deadlines[region] = now + Self.immersiveDelay }
        }
    }

    mutating func setHovered(_ region: ChromeRegion, _ inside: Bool, at now: TimeInterval) {
        guard hovered.contains(region) != inside else { return }
        if inside { hovered.insert(region) } else { hovered.remove(region) }
        switch mode {
        case .windowed: break
        case .immersive: pointerActivity(at: now)
        case .frameless:
            if inside {
                visible.insert(region)
                deadlines.removeValue(forKey: region)
            } else if visible.contains(region) {
                deadlines[region] = now + Self.framelessDelay
            }
        }
    }

    mutating func hideExpired(at now: TimeInterval) {
        for region in ChromeRegion.allCases {
            guard let deadline = deadlines[region], now >= deadline else { continue }
            deadlines.removeValue(forKey: region)
            if !hovered.contains(region) { visible.remove(region) }
        }
    }
}
