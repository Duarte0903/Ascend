import SwiftUI

/// An editable amount. Anything the user can set gets this treatment — a
/// visible border, hover feedback and a focus ring — so it never reads like a
/// calculated value.
struct MoneyField: View {
    @Binding var value: Double
    var decimals: Int = 2
    var width: CGFloat = 108
    var font: Font = .figure(13, weight: .medium)

    @FocusState private var focused: Bool
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
    }

    private var border: Color {
        if focused { return .ftAccent }
        return hovering ? .ftInkTertiary : .ftHairlineStrong
    }

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(decimals)))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(Color.ftInk)
            .focused($focused)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(width: width)
            .background(Color.ftSurface, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: focused ? 1.5 : 1))
            .overlay(shape.inset(by: -2.5).strokeBorder(
                Color.ftAccent.opacity(focused ? 0.28 : 0), lineWidth: 3))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.13), value: focused)
            .animation(.easeOut(duration: 0.13), value: hovering)
    }
}

/// Same treatment for whole numbers, clamped to a sensible range.
struct IntField: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...600
    var width: CGFloat = 108

    @FocusState private var focused: Bool
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
    }

    var body: some View {
        TextField("", value: Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }),
            format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.figure(13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.ftInk)
            .focused($focused)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(width: width)
            .background(Color.ftSurface, in: shape)
            .overlay(shape.strokeBorder(
                focused ? Color.ftAccent : (hovering ? Color.ftInkTertiary : Color.ftHairlineStrong),
                lineWidth: focused ? 1.5 : 1))
            .overlay(shape.inset(by: -2.5).strokeBorder(
                Color.ftAccent.opacity(focused ? 0.28 : 0), lineWidth: 3))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.13), value: focused)
            .animation(.easeOut(duration: 0.13), value: hovering)
    }
}

/// The counterpart: a calculated value. Flat, quieter, never bordered.
struct DerivedText: View {
    let text: String
    var width: CGFloat?
    var emphasis: Bool = false
    var tint: Color?

    var body: some View {
        Text(text)
            .font(.figure(13, weight: emphasis ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(tint ?? (emphasis ? Color.ftInk : Color.ftInkSecondary))
            .frame(width: width, alignment: .trailing)
    }
}

/// A large editable figure, for the one value that leads a screen.
struct HeroField: View {
    @Binding var value: Double
    var suffix: String = "€"
    var width: CGFloat = 190

    @FocusState private var focused: Bool
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("", value: $value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.figure(42))
                .monospacedDigit()
                .foregroundStyle(Color.ftInk)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .frame(width: width)
                .background(Color.ftSurface, in: shape)
                .overlay(shape.strokeBorder(
                    focused ? Color.ftAccent : (hovering ? Color.ftInkTertiary : Color.ftHairlineStrong),
                    lineWidth: 1.5))
                .overlay(shape.inset(by: -3).strokeBorder(
                    Color.ftAccent.opacity(focused ? 0.26 : 0), lineWidth: 4))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.14), value: focused)
                .animation(.easeOut(duration: 0.14), value: hovering)

            Text(suffix)
                .font(.figure(30, weight: .medium))
                .foregroundStyle(Color.ftInkTertiary)
        }
    }
}
