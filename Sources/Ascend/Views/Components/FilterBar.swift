import SwiftUI

/// The time window, as a custom segmented control. Shared across Dashboard,
/// Balances and Trends via one stored preference, so switching screens keeps
/// your context.
///
/// The stock `.segmented` picker is the one control in the app that ignores the
/// design system — different corner radius, different type, its own greys. This
/// matches the cards and fields, and slides the selection rather than jumping.
struct DateRangePicker: View {
    @Binding var selection: DateRangeFilter

    @Namespace private var selectionPill
    @State private var hovered: DateRangeFilter?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DateRangeFilter.allCases) { range in
                segment(range)
            }
        }
        .padding(3)
        .background(Color.ftSurfaceAlt, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.ftHairline, lineWidth: 1))
        .help("Limit these screens to a time window")
    }

    private func segment(_ range: DateRangeFilter) -> some View {
        let isSelected = range == selection
        return Button {
            withAnimation(.snappy(duration: 0.18)) { selection = range }
        } label: {
            Text(range.shortLabel)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color.ftInkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minWidth: 34)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.ftAccent)
                            .matchedGeometryEffect(id: "selected-range", in: selectionPill)
                    } else if hovered == range {
                        Capsule().fill(Color.ftInkTertiary.opacity(0.16))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = range }
            else if hovered == range { hovered = nil }
        }
        // The short label is all that fits; the tooltip says it in full.
        .help(range.label)
    }
}

/// Which accounts to plot. Defaults to all, and an empty selection means all
/// rather than an empty chart — a filter that can hide everything is a trap.
struct AccountFilterMenu: View {
    let accounts: [Account]
    @Binding var hidden: Set<UUID>

    private var shownCount: Int { accounts.count - hidden.count }

    var body: some View {
        Menu {
            Button("Show all") { hidden.removeAll() }
                .disabled(hidden.isEmpty)
            Divider()
            ForEach(accounts) { account in
                Button {
                    toggle(account)
                } label: {
                    HStack {
                        Text(account.name)
                        if !hidden.contains(account.id) { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold))
                Text(shownCount == accounts.count
                     ? "All accounts"
                     : "\(shownCount) of \(accounts.count)")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(shownCount == accounts.count
                             ? Color.ftInkSecondary : Color.ftAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.ftSurfaceAlt, in: Capsule())
            .overlay(Capsule().strokeBorder(shownCount == accounts.count
                                            ? Color.ftHairline
                                            : Color.ftAccent.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which accounts appear in these charts")
    }

    private func toggle(_ account: Account) {
        if hidden.contains(account.id) {
            hidden.remove(account.id)
        } else if shownCount > 1 {
            // Never let the last visible account be hidden.
            hidden.insert(account.id)
        }
    }
}

/// Shown when a filter legitimately matches nothing, so an empty screen always
/// explains itself and offers the way out.
struct NoResultsInRange: View {
    let range: DateRangeFilter
    var onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(Color.ftInkTertiary)
            Text("No records in \(range.label.lowercased())")
                .font(.system(size: 14, weight: .medium))
            Text("Widen the period to see your history.")
                .font(.system(size: 12))
                .foregroundStyle(Color.ftInkTertiary)
            Button("Show all time", action: onReset)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
