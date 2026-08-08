import SwiftUI

/// Toolbar control for the time window. Shared across Dashboard, Balances and
/// Trends via one stored preference, so switching screens keeps your context.
struct DateRangePicker: View {
    @Binding var selection: DateRangeFilter

    var body: some View {
        Picker("Period", selection: $selection) {
            ForEach(DateRangeFilter.allCases) { range in
                Text(range.shortLabel).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("Limit these screens to a time window")
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
            Label(shownCount == accounts.count
                  ? "All accounts"
                  : "\(shownCount) of \(accounts.count)",
                  systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
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
