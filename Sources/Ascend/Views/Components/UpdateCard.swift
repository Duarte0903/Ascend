import SwiftUI

/// The "a newer Ascend exists" toast at the top centre of the window.
///
/// It drops in as a small round badge with the download icon, pauses, then
/// unfolds sideways into the full strip. The button hands over to Sparkle's
/// Install window, which is where the user actually agrees to anything; the
/// × hides the toast until the next check.
struct UpdateCard: View {
    let update: AvailableUpdate
    let install: () -> Void
    let dismiss: () -> Void

    @State private var expanded = false

    static let width: CGFloat = 360
    private static let badge: CGFloat = 40
    private static let inset: CGFloat = 12
    /// How long the badge sits alone before unfolding.
    private static let pause: Duration = .milliseconds(700)

    var body: some View {
        content
            // The inner layout is always the full strip, so nothing reflows
            // while the container grows around it; the clip does the reveal.
            .frame(width: Self.width - Self.inset * 2, alignment: .leading)
            .padding(Self.inset)
            .frame(width: expanded ? Self.width : Self.badge,
                   height: expanded ? nil : Self.badge,
                   alignment: .topLeading)
            // A solid accent circle first; the fill fades to the card surface
            // as it opens and the hairline appears with it.
            .background(expanded ? Color.ftSurface : Color.ftAccent)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.ftHairlineStrong.opacity(expanded ? 1 : 0)))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .task {
                try? await Task.sleep(for: Self.pause)
                withAnimation(.spring(duration: 0.55, bounce: 0.22)) { expanded = true }
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: expanded ? Theme.tileRadius : Self.badge / 2,
                         style: .continuous)
    }

    private var content: some View {
        HStack(spacing: 10) {
            // 16pt inside 12pt padding puts its centre at 20 — the middle of
            // the 40pt badge — so it does not jump when the strip opens.
            icon.symbolEffect(.bounce, value: expanded)
            VStack(alignment: .leading, spacing: 1) {
                Text("Update available")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.ftInk)
                Text("Ascend \(update.version) is ready to install.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Update…", action: install)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ftInkTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Not now")
        }
        .opacity(expanded ? 1 : 0)
        .overlay(alignment: .leading) {
            // The badge's own arrow, white on the accent circle, sitting
            // exactly where the strip's icon will be.
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .opacity(expanded ? 0 : 1)
                .scaleEffect(expanded ? 0.4 : 1)
        }
    }

    private var icon: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.ftAccent)
            .frame(width: 16, height: 16)
    }
}
