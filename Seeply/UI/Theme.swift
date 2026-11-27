import AppKit
import SwiftUI

@MainActor
enum Theme {
    static let accent = Color(red: 0.84, green: 0.74, blue: 0.56)
    static let text = Color(white: 0.91)
    static let secondary = Color(white: 0.53)
    static let line = Color.white.opacity(0.075)
    static let chrome = Color(red: 0.096, green: 0.100, blue: 0.111)
    static var canvas: Color { Color(nsColor: canvasNSColor) }
    static var canvasNSColor: NSColor {
        switch Preferences.shared.background {
        case .graphite: return NSColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1)
        case .black: return .black
        case .paper: return NSColor(srgbRed: 0.90, green: 0.89, blue: 0.87, alpha: 1)
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(active ? Theme.accent : Theme.text.opacity(hovering ? 1 : 0.72))
                .frame(width: 30, height: 30)
                .background(active ? Theme.accent.opacity(0.13) : Color.white.opacity(hovering ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

@MainActor
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 16) }
}

@MainActor
struct PanelSurface: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 10)
    }
}
