import SwiftUI
import AppKit

/// Decides how an account is shown when it has no custom image.
///
/// The symbol is derived from the account's own flags rather than its category
/// name, so renaming a type — or inventing a new one — never leaves an account
/// with a misleading icon.
enum AccountIconStyle {
    static func defaultSymbol(includeInUsable: Bool,
                              countsAsSavings: Bool,
                              expectedAnnualReturn: Double) -> String {
        if !includeInUsable { return "creditcard" }           // vouchers, food cards
        if countsAsSavings && expectedAnnualReturn > 0 {
            return "chart.line.uptrend.xyaxis"                // invested
        }
        if countsAsSavings { return "banknote" }              // set aside
        return "building.columns"                             // everyday banking
    }

    /// Longest edge of a stored icon. Large enough for a crisp 44pt view on a
    /// Retina display, small enough that a backup stays a sensible size.
    static let maximumPixelSize: CGFloat = 256

    /// Downscales and re-encodes as PNG. A dropped-in logo can be several
    /// megabytes; storing that raw would bloat the store and every backup.
    static func thumbnailData(from image: NSImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maximumPixelSize / longest)
        let target = NSSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    static func thumbnailData(fromFileAt url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return thumbnailData(from: image)
    }
}

/// An account's icon: its custom image if it has one, otherwise a symbol tinted
/// with the account's colour.
struct AccountIcon: View {
    let iconData: Data?
    let colorHex: String
    let includeInUsable: Bool
    let countsAsSavings: Bool
    let expectedAnnualReturn: Double
    var size: CGFloat = 34

    private var tint: Color { Color(hex: colorHex) }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
    }

    var body: some View {
        // One ZStack with a single fixed frame, so a custom image and a default
        // symbol occupy exactly the same square. Sizing each branch separately
        // lets them disagree.
        ZStack {
            if let iconData, let image = NSImage(data: iconData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                tint.opacity(0.16)
                // Fit each glyph to the same box rather than setting a font
                // size. Font size fixes cap-height, so symbols with different
                // aspect ratios — a wide chart versus a squarer building —
                // come out looking like different sizes.
                Image(systemName: AccountIconStyle.defaultSymbol(
                    includeInUsable: includeInUsable,
                    countsAsSavings: countsAsSavings,
                    expectedAnnualReturn: expectedAnnualReturn))
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .frame(width: size * 0.56, height: size * 0.56)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.ftHairline, lineWidth: 1))
        .contentShape(shape)
        // Incompressible: in a tight row — a table header with a long account
        // name — SwiftUI will otherwise squeeze a fixed frame to make the text
        // fit, and the icons come out different sizes.
        .fixedSize()
    }
}

extension AccountIcon {
    /// Convenience for the common case of rendering a stored account.
    init(_ account: Account, size: CGFloat = 34) {
        self.init(iconData: account.iconData,
                  colorHex: account.colorHex,
                  includeInUsable: account.includeInUsable,
                  countsAsSavings: account.countsAsSavings,
                  expectedAnnualReturn: account.expectedAnnualReturn,
                  size: size)
    }
}
