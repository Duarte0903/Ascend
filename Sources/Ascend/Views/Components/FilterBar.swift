import SwiftUI

/// The time window. Shared across Dashboard, Balances and Trends via one
/// stored preference, so switching screens keeps your context.
///
/// Deliberately a stock picker with no styling of its own. It lives in the
/// toolbar, which the system already renders in its own material — anything
/// painted on top sits *over* that treatment rather than joining it.
struct DateRangePicker: View {
    @Binding var selection: DateRangeFilter
    /// The years that actually appear in the records, newest first. Offering a
    /// year with nothing in it would be a filter guaranteed to show nothing.
    var years: [Int] = []

    private var selectedYear: Int? {
        if case .year(let year) = selection { return year }
        return nil
    }

    var body: some View {
        // The fixed windows stay a segmented control — the stock one, so the
        // toolbar dresses it. Years live in a separate menu because that list
        // grows by one every January and a segmented control cannot.
        Picker("Period", selection: $selection) {
            ForEach(DateRangeFilter.standardCases) { range in
                Text(range.shortLabel).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Limit these screens to a time window")

        if !years.isEmpty {
            Menu {
                ForEach(years, id: \.self) { year in
                    Button {
                        selection = .year(year)
                    } label: {
                        HStack {
                            // `verbatim`: a year is a label, not a quantity,
                            // or it comes out as "2 026".
                            Text(verbatim: String(year))
                            if selectedYear == year { Image(systemName: "checkmark") }
                        }
                    }
                }
                if selectedYear != nil {
                    Divider()
                    Button("All time") { selection = .all }
                }
            } label: {
                if let year = selectedYear {
                    Label(String(year), systemImage: "calendar")
                } else {
                    Label("Year", systemImage: "calendar")
                }
            }
            .help("Show one year's records")
        }
    }
}

/// Which accounts to plot. Defaults to all, and an empty selection means all
/// rather than an empty chart — a filter that can hide everything is a trap.
///
/// Unstyled for the same reason as the picker above: the toolbar dresses it.
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
                  systemImage: "line.3.horizontal.decrease")
        }
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
