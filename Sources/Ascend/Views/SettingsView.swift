import SwiftUI
import SwiftData

/// Preferences that shape the app rather than the money in it.
struct SettingsView: View {
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(HiddenSections.key) private var hiddenRaw = ""
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue

    private var kind: ProfileKind { profiles.registry.active.kind }
    private var country: String { profiles.registry.active.countryCode }

    private var hidden: Set<AppSection> { HiddenSections.decode(hiddenRaw) }

    private var groups: [(label: String, items: [AppSection])] {
        AppSection.hideableGroups(for: kind, in: country)
    }

    private var hiddenCount: Int {
        groups.flatMap(\.items).filter { hidden.contains($0) }.count
    }

    var body: some View {
        FillingScreen {
            Callout(text: "Hiding a screen only takes it out of the sidebar. Nothing is deleted, and the figures on it keep counting — a hidden Expenses screen still feeds Projections.")

            HStack(alignment: .top, spacing: Theme.gap) {
                sidebarCard
                VStack(spacing: Theme.gap) {
                    appearanceCard
                    currencyCard
                    Spacer(minLength: 0)
                }
                .frame(width: Theme.Size.sidePanelWide)
            }
            .fillsHeight(minimum: 240)
        }
    }

    // MARK: - Which screens show

    private var sidebarCard: some View {
        CardSection("Sidebar", subtitle: sidebarSubtitle) {
            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 18, verticalSpacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.element.label) { index, group in
                    if index > 0 {
                        Divider().gridCellUnsizedAxes(.horizontal).padding(.vertical, 2)
                    }
                    GridRow {
                        Eyebrow(group.label)
                        Color.clear.frame(height: 1)
                    }
                    ForEach(group.items) { section in
                        GridRow {
                            HStack(spacing: 8) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.ftInkTertiary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(section.title)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Color.ftInk)
                                    Text(section.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.ftInkTertiary)
                                        .lineLimit(1)
                                }
                            }
                            Toggle("", isOn: Binding(
                                get: { !hidden.contains(section) },
                                set: { setShown($0, section) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }

            if hiddenCount > 0 {
                Button("Show every screen") { hiddenRaw = "" }
                    .controlSize(.small)
            }

            Text("Dashboard and Settings are always shown: one is where every screen falls back to, the other is the only way of bringing anything back.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.ftInkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fillingHeight()
    }

    private var sidebarSubtitle: String {
        let total = groups.flatMap(\.items).count
        guard hiddenCount > 0 else { return "Every screen is showing" }
        return "\(hiddenCount) of \(total) hidden"
    }

    private func setShown(_ shown: Bool, _ section: AppSection) {
        var updated = hidden
        if shown { updated.remove(section) } else { updated.insert(section) }
        hiddenRaw = HiddenSections.encode(updated)
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        CardSection("Appearance", subtitle: "Also under View ▸ Appearance") {
            Picker("", selection: Binding(
                get: { AppearanceSetting(rawValue: appearanceRaw) ?? .system },
                set: { appearanceRaw = $0.rawValue; $0.apply() })) {
                ForEach(AppearanceSetting.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Follows macOS unless you pick one. The choice applies to every profile.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.ftInkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Currency

    /// Per profile, unlike everything else here: one set of books can be kept
    /// in euros and another in pounds, so the subtitle names which.
    private var currencyCard: some View {
        CardSection("Currency",
                    subtitle: "How money is shown in \(profiles.registry.active.name)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6,
                                         alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(Money.commonSymbols, id: \.self) { option in
                    currencyChip(option)
                }
            }
            Text("Every figure in this profile is shown with this symbol. Other profiles keep their own.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.ftInkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func currencyChip(_ option: String) -> some View {
        let active = profiles.registry.active
        let isSelected = active.currencySymbol == option
        return Button {
            profiles.update(active.id) { $0.currencySymbol = option }
        } label: {
            Text(option)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color.ftInkSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.ftAccent : Color.ftSurfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Color.ftHairline,
                                                lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
