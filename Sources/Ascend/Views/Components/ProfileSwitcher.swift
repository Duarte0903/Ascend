import SwiftUI
import AppKit

/// A profile's picture if it has one, otherwise its symbol on its colour.
/// One frame and one clip for both cases, so every badge is the same size
/// whichever it is.
struct ProfileBadge: View {
    let profile: Profile
    var size: CGFloat = Theme.Size.iconLarge

    var body: some View {
        ZStack {
            // Always present, so the stack has a member that takes whatever
            // size it is given. Without one, the stack's ideal size is the
            // picture's own — 256px — and that leaks out past the frame.
            Color(hex: profile.colorHex)

            if let data = profile.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    // Pinned here as well as on the stack: `scaledToFill`
                    // reports a size larger than what it was offered, and that
                    // figure is what the surrounding layout would otherwise use.
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Image(systemName: profile.symbol)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: size * 0.46, height: size * 0.46)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .fixedSize()
    }
}

/// Sits above the sidebar so which books you are looking at is never a guess.
///
/// A button and a popover rather than a `Menu`: macOS hands a menu's label to
/// AppKit, and a bitmap image inside it is drawn at its natural size with the
/// SwiftUI frame and clip shape dropped — a 256px square where a small round
/// avatar belongs. Everything here stays in SwiftUI, so the badge renders the
/// same as it does everywhere else.
struct ProfileSwitcher: View {
    @Environment(ProfileStore.self) private var store
    @Binding var showingNew: Bool
    @Binding var showingManager: Bool

    @State private var hovered = false
    @State private var listOpen = false
    @State private var hoveredRow: UUID?

    private var badgeSize: CGFloat { Theme.Size.iconMedium + 6 }

    var body: some View {
        Button {
            listOpen.toggle()
        } label: {
            HStack(spacing: 9) {
                ProfileBadge(profile: store.registry.active, size: badgeSize)
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("Profile")
                    Text(store.registry.active.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ftInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.ftInkTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovered ? Color.ftInkTertiary.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Switch between profiles, or create one")
        .popover(isPresented: $listOpen, arrowEdge: .bottom) { picker }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.registry.profiles) { profile in
                row(profile)
            }
            Divider().padding(.vertical, 5)
            action("New Profile…", icon: "plus") { showingNew = true }
            action("Manage Profiles…", icon: "slider.horizontal.3") { showingManager = true }
        }
        .padding(7)
        .frame(width: 264)
    }

    private func row(_ profile: Profile) -> some View {
        let isActive = profile.id == store.registry.activeID
        return Button {
            store.activate(profile.id)
            listOpen = false
        } label: {
            HStack(spacing: 10) {
                ProfileBadge(profile: profile, size: badgeSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text(profile.name)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Color.ftInk)
                        .lineLimit(1)
                    if !profile.summary.isEmpty {
                        Text(profile.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.ftAccent)
                    .opacity(isActive ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hoveredRow == profile.id ? Color.ftInkTertiary.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredRow = profile.id }
            else if hoveredRow == profile.id { hoveredRow = nil }
        }
    }

    private func action(_ title: String, icon: String, run: @escaping () -> Void) -> some View {
        Button {
            listOpen = false
            // Let this popover finish dismissing before the next one is
            // anchored to the same view, which otherwise silently fails to open.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: run)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.ftInkSecondary)
                    .frame(width: badgeSize)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ftInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hoveredRow?.uuidString == title ? Color.ftInkTertiary.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shared by the create sheet and the manager, so a profile looks the same
/// wherever you edit it.
struct ProfileAppearancePicker: View {
    @Binding var colorHex: String
    @Binding var symbol: String
    var kind: ProfileKind = .person

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.iconButton + 3),
                                         spacing: 7, alignment: .leading)],
                      alignment: .leading, spacing: 7) {
                ForEach(Theme.accountPalette, id: \.self) { hex in
                    Button { colorHex = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: Theme.Size.iconButton - 4,
                                   height: Theme.Size.iconButton - 4)
                            .overlay(Circle().strokeBorder(
                                Color.ftInk.opacity(colorHex == hex ? 0.55 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            // Wraps rather than overflowing, so the card reflows with the window.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.iconButton + 7),
                                         spacing: 7, alignment: .leading)],
                      alignment: .leading, spacing: 7) {
                ForEach(kind.symbols, id: \.self) { option in
                    Button { symbol = option } label: {
                        Image(systemName: option)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(symbol == option ? Color.white : Color.ftInkSecondary)
                            .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
                            .background(symbol == option ? Color(hex: colorHex) : Color.ftSurfaceAlt,
                                        in: Circle())
                            .overlay(Circle().strokeBorder(Color.ftHairline,
                                                           lineWidth: symbol == option ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
