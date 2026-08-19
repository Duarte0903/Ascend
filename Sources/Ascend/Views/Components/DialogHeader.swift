import SwiftUI

/// Title, optional explanation, and a close button, for every dialog in the app.
///
/// The close button carries the cancel shortcut, so Escape closes the dialog
/// too — a dialog you can only leave by finding the right button is a trap.
struct DialogHeader: View {
    let title: String
    var subtitle: String?
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ftInkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            CloseButton(action: onClose)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

/// The dismiss affordance every dialog shares. Carries the cancel shortcut, so
/// wiring one of these in is also what makes Escape work.
struct CloseButton: View {
    var action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovered ? Color.ftInk : Color.ftInkSecondary)
                .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
                .background(hovered ? Color.ftInkTertiary.opacity(0.18) : Color.ftSurfaceAlt,
                            in: Circle())
                .overlay(Circle().strokeBorder(Color.ftHairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hovered = $0 }
        .help("Close")
    }
}
