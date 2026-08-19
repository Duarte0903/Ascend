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

    /// The one place control sizes are decided.
    ///
    /// Table columns reuse the same widths as the fields that sit in them, so a
    /// header, its input rows and its total line up without per-screen fiddling.
    /// Every standard field also shares padding, which is what makes fields in
    /// one row the same height.
    enum Size {
        /// Money and other number inputs, and the derived columns beside them.
        static let field: CGFloat = 112
        /// Percentages and compact figures.
        static let fieldSmall: CGFloat = 96
        /// Menu pickers — wide enough for a category or frequency name.
        static let picker: CGFloat = 136
        /// Inline, editable names.
        static let name: CGFloat = 200
        /// Text fields inside a sheet, where there is more room.
        static let nameWide: CGFloat = 240
        static let description: CGFloat = 320
        static let heroField: CGFloat = 200
        /// Toggle and checkbox columns.
        static let control: CGFloat = 56
        /// Borderless icon buttons: delete, reorder.
        static let iconButton: CGFloat = 24
        /// Legend and colour swatches.
        static let dot: CGFloat = 9
        /// The colour stripe down the side of an account card.
        static let stripe: CGFloat = 4
        /// Account icons. Three deliberate scales — every icon at a given scale
        /// is the same size, whether it is a custom image or a default symbol.
        static let detailValue: CGFloat = 320  // editable cell in a detail table
        static let avatar: CGFloat = 48        // profile picture, Profile tab
        static let iconLarge: CGFloat = 40     // account cards
        static let iconMedium: CGFloat = 20    // archived list
        static let iconInline: CGFloat = 16    // table headers
        /// The narrow companion column beside a card.
        static let sidePanel: CGFloat = 330
        static let sheetNarrow: CGFloat = 480
        static let sheetWide: CGFloat = 620

        static let fieldPaddingH: CGFloat = 9
        static let fieldPaddingV: CGFloat = 5
    }
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

    /// Column headings. Defined once here because column widths are measured
    /// from this exact font — if the two drift apart, headings clip.
    static let tableHeader = Font.system(size: Theme.tableHeaderSize, weight: .semibold)
}

extension Theme {
    /// Table headings. Big enough to read as a heading rather than fine print.
    static let tableHeaderSize: CGFloat = 12.5
    static let tableHeaderTracking: CGFloat = 0.2
    /// The AppKit equivalent, for measuring text width.
    static var tableHeaderNSFont: NSFont {
        NSFont.systemFont(ofSize: tableHeaderSize, weight: .semibold)
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

// MARK: - Screen scaffold

/// A screen whose content fills the pane instead of sitting at its natural
/// height with a void underneath. It still scrolls when the content is taller
/// than the window, so small windows keep working.
///
/// Give whichever card should absorb the leftover height `.fillsHeight()`.
struct FillingScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    content
                }
                .padding(Theme.screenPadding)
                .frame(minWidth: geometry.size.width,
                       minHeight: geometry.size.height,
                       alignment: .topLeading)
            }
        }
    }
}

extension View {
    /// Absorbs whatever vertical space the screen has left over.
    func fillsHeight(minimum: CGFloat = 240) -> some View {
        frame(minHeight: minimum, maxHeight: .infinity)
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
