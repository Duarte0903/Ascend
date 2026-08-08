import SwiftUI

/// A secondary metric. Deliberately smaller than a hero figure so the screen
/// has a clear first read.
struct MetricTile: View {
    let title: String
    let value: String
    var caption: String?
    var valueColor: Color = .ftInk

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.ftInkTertiary)
                .lineLimit(1)
            Text(value)
                .font(.figure(23))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ftInkTertiary)
                    .lineLimit(1)
            }
        }
        // maxHeight must be applied *before* the padding and background: the
        // background sizes itself to whatever it is attached to, so stretching
        // the tile from outside grows an invisible wrapper and centres the card
        // inside it, leaving the visible boxes different heights.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.ftSurface,
                    in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(Color.ftHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

/// Encodes direction in shape and colour, not just sign, so a gain or a loss
/// reads at a glance.
struct DeltaPill: View {
    enum Direction { case up, down, flat }

    let text: String
    let direction: Direction

    private var tint: Color {
        switch direction {
        case .up: .ftPositive
        case .down: .ftNegative
        case .flat: .ftInkSecondary
        }
    }

    private var glyph: String? {
        switch direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: nil
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let glyph {
                Image(systemName: glyph).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.figure(12.5, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(tint.opacity(0.13), in: Capsule())
    }

    /// Builds a pill from a signed amount, or a neutral one when undefined.
    static func amount(_ value: Double?, formatted: String) -> DeltaPill {
        guard let value else { return DeltaPill(text: formatted, direction: .flat) }
        if value > 0 { return DeltaPill(text: "+" + formatted, direction: .up) }
        if value < 0 { return DeltaPill(text: formatted, direction: .down) }
        return DeltaPill(text: formatted, direction: .flat)
    }
}

/// The dominant number on a screen.
struct HeroFigure: View {
    let value: String
    var size: CGFloat = 56

    var body: some View {
        Text(value)
            .font(.figure(size, weight: .semibold))
            .monospacedDigit()
            .kerning(-0.8)
            .foregroundStyle(Color.ftInk)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
