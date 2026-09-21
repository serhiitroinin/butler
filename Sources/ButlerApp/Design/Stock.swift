import SwiftUI

/// The one paper tone of the window, its ink, and its single accent.
enum Stock {
    static let paper = dynamic(light: 0xF3F0E8, dark: 0x1F1F1D)
    static let sidebar = dynamic(light: 0xECE8DE, dark: 0x1A1A18)
    static let ink = dynamic(light: 0x1E1C18, dark: 0xEDE9E1)
    static let accent = dynamic(light: 0x5E6B4E, dark: 0x8A9A76)
    /// The accent as a surface under light text: the selected sidebar row, the
    /// active segment, and the olive buttons. In dark the accent itself is too
    /// bright to sit under text, so the fill is a deeper olive.
    static let fill = dynamic(light: 0x5E6B4E, dark: 0x5A684C)
    static let onFill = dynamic(light: 0xFBFAF6, dark: 0xF1EEE6)
    static let onAccent = dynamic(light: 0xFBFAF6, dark: 0x171715)
    static let red = dynamic(light: 0xA4483C, dark: 0xD0857A)
    static let slate = dynamic(light: 0x4F6272, dark: 0x9DB0C0)
    static let hairline = dynamicAlpha(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.10))
    static let wash = dynamicAlpha(light: (0x1E1C18, 0.07), dark: (0xEDE9E1, 0.09))

    static var secondary: Color { ink.opacity(0.6) }
    static var tertiary: Color { ink.opacity(0.4) }

    static let paperNS = nsDynamic(light: 0xF3F0E8, dark: 0x1F1F1D)
    static let accentNS = nsDynamic(light: 0x5E6B4E, dark: 0x8A9A76)
    static let inkNS = nsDynamic(light: 0x1E1C18, dark: 0xEDE9E1)

    static func nsDynamic(light: Int, dark: Int, lightAlpha: Double = 1, darkAlpha: Double = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }

    static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: nsDynamic(light: light, dark: dark))
    }

    static func dynamicAlpha(light: (Int, Double), dark: (Int, Double)) -> Color {
        Color(nsColor: nsDynamic(light: light.0, dark: dark.0, lightAlpha: light.1, darkAlpha: dark.1))
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: Double = 1) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The measures of the proposal page.
enum Layout {
    static let rowHeight: CGFloat = 22
    static let margin: CGFloat = 20
    static let checkColumn: CGFloat = 14
    static let pathColumn: CGFloat = 250
    static let kindColumn: CGFloat = 128
    static let sizeColumn: CGFloat = 64
    static let markColumn: CGFloat = 62
}

/// The only rule in the window: one pixel of ink at ten per cent.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Stock.hairline)
            .frame(height: 1)
    }
}

extension View {
    /// The content stock. The window itself is the same colour, so this only
    /// matters where a system view would paint its own background.
    func onPaper() -> some View {
        background(Stock.paper.ignoresSafeArea())
    }
}
