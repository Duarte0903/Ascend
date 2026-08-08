import SwiftUI

/// An editable amount. Anything the user can set gets this treatment — a
/// visible border, hover feedback and a focus ring — so it never reads like a
/// calculated value.
struct MoneyField: View {
    @Binding var value: Double
    var decimals: Int = 2
    var width: CGFloat = 108
    var font: Font = .figure(13, weight: .medium)
    /// Rendered inside the field's box, so a unit never breaks column alignment.
    var suffix: String?

    @FocusState private var focused: Bool
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
    }

    private var border: Color {
        if focused { return .ftAccent }
        return hovering ? .ftInkTertiary : .ftHairlineStrong
    }

    /// Edits are buffered here and committed on Enter or focus loss. Binding
    /// straight to the store would save on every keystroke, refresh the query,
    /// and reformat the text mid-typing — which reads as the field fighting you.
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(Color.ftInk)
                .focused($focused)
                .onSubmit { commit() }
            if let suffix {
                Text(suffix)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
            }
        }
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
        .onAppear { text = NumberText.string(from: value, decimals: decimals) }
        .onChange(of: value) { _, new in
            // Only follow the model when the user isn't mid-edit.
            if !focused { text = NumberText.string(from: new, decimals: decimals) }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                // Select-all on entry so typing replaces rather than appends.
                DispatchQueue.main.async { NSApp?.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            } else {
                commit()
            }
        }
    }

    private func commit() {
        if let parsed = NumberText.double(from: text) {
            value = parsed
            text = NumberText.string(from: parsed, decimals: decimals)
        } else {
            // Unparseable input reverts rather than silently becoming zero.
            text = NumberText.string(from: value, decimals: decimals)
        }
    }
}

/// Parsing and display for editable figures. Accepts a comma or a dot as the
/// decimal separator, and tolerates spaces and a stray € or %.
enum NumberText {
    static func string(from value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func double(from text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}

/// An editable text label that still reads as editable — used for account names.
/// Commits on Enter or focus loss, so a half-typed name is never validated.
struct NameField: View {
    let name: String
    var width: CGFloat = 200
    var onCommit: (String) -> Void

    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var text: String = ""

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
    }

    var body: some View {
        TextField("Name", text: $text)
            .onSubmit { commitIfChanged() }
            .onAppear { text = name }
            .onChange(of: name) { _, new in if !focused { text = new } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commitIfChanged() } }
            .textFieldStyle(.plain)
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundStyle(Color.ftInk)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, alignment: .leading)
            .background(focused || hovering ? Color.ftSurfaceAlt : .clear, in: shape)
            .overlay(shape.strokeBorder(
                focused ? Color.ftAccent : (hovering ? Color.ftHairlineStrong : .clear),
                lineWidth: focused ? 1.5 : 1))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.13), value: focused)
            .animation(.easeOut(duration: 0.13), value: hovering)
    }

    private func commitIfChanged() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != name else { return }
        onCommit(trimmed)
        text = name
    }
}

/// A quiet, wide note field. Reads as secondary text until you interact with it,
/// so a description never competes with the account's name or balance.
struct DescriptionField: View {
    let note: String
    var width: CGFloat = 320
    var onCommit: (String) -> Void

    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var text: String = ""

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
    }

    var body: some View {
        TextField("Add a description…", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(focused ? Color.ftInk : Color.ftInkSecondary)
            .focused($focused)
            .onSubmit { commitIfChanged() }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, alignment: .leading)
            .background(focused || hovering ? Color.ftSurfaceAlt : .clear, in: shape)
            .overlay(shape.strokeBorder(
                focused ? Color.ftAccent : (hovering ? Color.ftHairlineStrong : .clear),
                lineWidth: focused ? 1.5 : 1))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.13), value: focused)
            .animation(.easeOut(duration: 0.13), value: hovering)
            .onAppear { text = note }
            .onChange(of: note) { _, new in if !focused { text = new } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commitIfChanged() } }
    }

    private func commitIfChanged() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != note else { return }
        onCommit(trimmed)
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

    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.figure(13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.ftInk)
            .focused($focused)
            .onSubmit { commit() }
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
            .onAppear { text = "\(value)" }
            .onChange(of: value) { _, new in if !focused { text = "\(new)" } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        if let parsed = NumberText.double(from: text) {
            value = min(max(Int(parsed), range.lowerBound), range.upperBound)
        }
        text = "\(value)"
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

    @State private var text: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.figure(42))
                .monospacedDigit()
                .foregroundStyle(Color.ftInk)
                .focused($focused)
                .onSubmit { commit() }
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
                .onAppear { text = NumberText.string(from: value, decimals: 0) }
                .onChange(of: value) { _, new in
                    if !focused { text = NumberText.string(from: new, decimals: 0) }
                }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }

            Text(suffix)
                .font(.figure(30, weight: .medium))
                .foregroundStyle(Color.ftInkTertiary)
        }
    }

    private func commit() {
        if let parsed = NumberText.double(from: text) { value = parsed }
        text = NumberText.string(from: value, decimals: 0)
    }
}
