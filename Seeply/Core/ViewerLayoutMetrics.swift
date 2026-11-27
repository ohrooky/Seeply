import Foundation

enum ViewerLayoutMetrics {
    static let headerHeight: CGFloat = 40
    static let footerHeight: CGFloat = 28
    static let filmstripHeight: CGFloat = 92
    static let canvasPadding: CGFloat = 16

    static func chromeHeight(immersive: Bool, filmstrip: Bool, imageCount: Int) -> CGFloat {
        immersive ? 0 : headerHeight + footerHeight + (filmstrip && imageCount > 1 ? filmstripHeight : 0)
    }
}
