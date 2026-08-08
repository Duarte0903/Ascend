import SwiftUI
import AppKit

/// Design tokens for the whole app. Every colour, radius and type ramp lives
/// here so the seven screens stay consistent and a change lands everywhere.
enum Theme {
    static let cardRadius: CGFloat = 14
    static let tileRadius: CGFloat = 12
    static let fieldRadius: CGFloat = 7
    static let cardPadding: CGFloat = 18
    static let screenPadding: CGFloat = 22
    static let gap: CGFloat = 16

    /// Default palette offered to new accounts, in order.
    static let accountPalette = ["#1F6E8C", "#7A5EA6", "#C2703D", "#A34A5E",
                                 "#3E7C59", "#8C6239", "#5B6C9B", "#96566F"]
}

extension Color {
    /// A colour that resolves per appearance, so light and dark each get a
    /// considered value rather than a naive inversion.
    static func adaptive(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    static let ftCanvas         = adaptive(light: "#FBFCFD", dark: "#14181F")
    static let ftSurface        = adaptive(light: "#FFFFFF", dark: "#1B2029")
    static let ftSurfaceAlt     = adaptive(light: "#F5F7FA", dark: "#212734")
    static let ftHairline       = adaptive(light: "#E1E6ED", dark: "#2A313D")
    static let ftHairlineStrong = adaptive(light: "#CFD6E0", dark: "#3A4350")
    static let ftInk            = adaptive(light: "#0E1420", dark: "#EDF1F6")
    static let ftInkSecondary   = adaptive(light: "#4A5464", dark: "#A6B0BF")
    static let ftInkTertiary    = adaptive(light: "#7C8797", dark: "#78838F")
    static let ftAccent         = adaptive(light: "#1F6E8C", dark: "#5AB2D0")
    static let ftPositive       = adaptive(light: "#177D5B", dark: "#4FBF92")
    static let ftNegative       = adaptive(light: "#B3341F", dark: "#E5715A")

    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }

    var hexString: String {
        let native = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X",
                      Int(round(native.redComponent * 255)),
                      Int(round(native.greenComponent * 255)),
                      Int(round(native.blueComponent * 255)))
    }
}

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Font {
    /// Figures use SF Pro Rounded throughout — the app's numeric voice.
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Card surface

private struct CardSurface: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.ftSurface,
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.ftHairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.055), radius: 12, y: 4)
    }
}

extension View {
    func ftCard(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

// MARK: - Small type roles

/// Uppercase micro-label used above hero figures and section titles.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.ftInkTertiary)
    }
}
