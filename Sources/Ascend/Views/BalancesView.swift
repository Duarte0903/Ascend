import SwiftUI
import SwiftData

struct BalancesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]
    /// Settings are edited on other screens now, so this view has to watch
    /// them: without a query on the object, a change elsewhere leaves these
    /// figures stale until the screen is left and re-entered.
    @Query private var storedSettings: [AppSettings]

    private var settings: AppSettings {
        storedSettings.first ?? SeedData.settings(in: context)
    }

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    @AppStorage("dateRange") private var rangeRaw = DateRangeFilter.all.rawValue

    private var range: DateRangeFilter {
        DateRangeFilter(rawValue: rangeRaw) ?? .all
    }

    /// Windowed for display only. Change and savings rate are still computed
    /// against the record that actually preceded each row.
    private var derived: [DerivedRecord] {
        range.apply(to: allDerived, now: Date())
    }

    /// Years with records in them, so the filter never offers an empty one.
    /// Taken from the dates themselves: deriving a whole ledger to read the
    /// years off it was work for nothing.
    private var availableYears: [Int] {
        DateRangeFilter.years(in: records.map(\.date))
    }

    private var allDerived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: settings,
            expenses: expenseItems))
    }

    var body: some View {
        FillingScreen {
            Callout(text: "Boxed cells are yours to fill. Everything shaded to the right is calculated and updates as you type.")

            if records.isEmpty {
                ContentUnavailableView("No records yet",
                                       systemImage: "tablecells",
                                       description: Text("Add your first record to start tracking."))
                    .frame(height: 300)
            } else {
                // Derived once per pass and handed down. Every mention of it
                // used to rebuild the ledger from scratch.
                let rows = derived
                if rows.isEmpty {
                    NoResultsInRange(range: range) { rangeRaw = DateRangeFilter.all.rawValue }
                } else {
                    table(rows)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                DateRangePicker(selection: Binding(
                    get: { range }, set: { rangeRaw = $0.rawValue }),
                                years: availableYears)
                Button("Duplicate Last", systemImage: "doc.on.doc") { duplicateLast() }
                    .disabled(records.isEmpty)
                Button("Add Record", systemImage: "plus") { addRecord() }
                    .keyboardShortcut("n")
            }
        }
    }

    /// Rows are HStacks rather than GridRows on purpose. SwiftUI applies a
    /// modifier put on a GridRow to each of its cells, so a row background
    /// painted that way stops at every cell boundary and a hover handler fires
    /// an exit each time the pointer crosses one. Every column here has an
    /// explicit width, so Grid was doing no alignment work worth that cost.
    private func table(_ rows: [DerivedRecord]) -> some View {
        // Measured once, not once per cell: it depends on the account names
        // and nothing else, and measuring text is the most expensive thing
        // this screen does.
        let width = accountColumnWidth
        let columns = activeAccounts
        // One pass instead of a linear scan per row.
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow(columns, width: width)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if let record = byID[row.id] {
                        BalanceRow(row: row, record: record, columns: columns,
                                   columnWidth: width)
                    }
                    if index < rows.count - 1 { Divider().opacity(0.6) }
                }
            }
            .padding(Theme.cardPadding)
        }
        // A ScrollView is greedy on both axes, so a horizontal one still takes
        // every pixel of height it is offered and centres its rows in the void.
        // This one scrolls sideways only; its height is whatever the rows need.
        .fixedSize(horizontal: false, vertical: true)
        .ftCard(padding: 0)
    }

    /// Account columns are as wide as the longest account name needs, so names
    /// are simply never truncated. The table already scrolls sideways, so the
    /// only cost is a little scroll distance — and nothing has to be revealed on
    /// hover, because nothing is hidden.
    private var accountColumnWidth: CGFloat {
        let font = Theme.tableHeaderNSFont
        let widest = activeAccounts.reduce(CGFloat(0)) { widest, account in
            let size = (account.name as NSString)
                .size(withAttributes: [.font: font])
            // Tracking adds spacing after every character; leaving it out of the
            // measurement is what made headings clip.
            let tracked = size.width + CGFloat(account.name.count) * Theme.tableHeaderTracking
            return max(widest, tracked)
        }
        // icon + spacing + text, with a little breathing room, never narrower
        // than a money field and capped so one silly name cannot dominate.
        let needed = Theme.Size.iconInline + 6 + widest.rounded(.up) + 10
        return min(max(Theme.Size.field, needed), 260)
    }

    private func headerRow(_ columns: [Account], width accountColumnWidth: CGFloat) -> some View {
        HStack(spacing: 14) {
            Text("Date").frame(width: Theme.Size.field, alignment: .leading)
            ForEach(columns) { account in
                HStack(spacing: 6) {
                    AccountIcon(account, size: Theme.Size.iconInline)
                    Text(account.name).lineLimit(1)
                }
                .frame(width: accountColumnWidth, alignment: .trailing)
                // Only useful for the rare name long enough to hit the cap.
                .help(account.note.isEmpty
                      ? account.name
                      : "\(account.name) — \(account.note)")
            }
            Text("Total").frame(width: Theme.Size.field, alignment: .trailing)
            Text("Usable").frame(width: Theme.Size.field, alignment: .trailing)
            Text("Change").frame(width: Theme.Size.field, alignment: .trailing)
            Text("Change %").frame(width: Theme.Size.fieldSmall, alignment: .trailing)
            Text("Savings rate").frame(width: Theme.Size.fieldSmall, alignment: .trailing)
            Color.clear.frame(width: Theme.Size.iconButton)
            Spacer(minLength: 0)
        }
        .font(.tableHeader)
        .tracking(Theme.tableHeaderTracking)
        .foregroundStyle(Color.ftInkSecondary)
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }


    private func addRecord() {
        let record = BalanceRecord(date: Date())
        context.insert(record)
        for account in activeAccounts { record.setAmount(0, for: account.id) }
        try? context.save()
    }

    private func duplicateLast() {
        guard let last = records.max(by: { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) })
        else { return }
        let record = BalanceRecord(date: Date())
        context.insert(record)
        for account in activeAccounts {
            record.setAmount(last.amount(for: account.id), for: account.id)
        }
        try? context.save()
    }
}

/// One row of the table, as its own view.
///
/// Hovering used to be state on the whole screen, so moving the pointer
/// across the table rebuilt every row — each with its own date picker and a
/// money field per account. Owning the highlight here means only the row
/// under the pointer is redrawn.
private struct BalanceRow: View {
    @Environment(\.modelContext) private var context
    let row: DerivedRecord
    let record: BalanceRecord
    let columns: [Account]
    let columnWidth: CGFloat

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            DatePicker("", selection: Binding(
                get: { record.date },
                set: { record.date = $0; try? context.save() }),
                displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Dates.pickerLocale)
                .datePickerStyle(.field)
                .frame(width: Theme.Size.field)

            ForEach(columns) { account in
                MoneyField(value: Binding(
                    get: { record.amount(for: account.id) },
                    set: { record.setAmount($0, for: account.id); try? context.save() }),
                    width: columnWidth)
            }

            DerivedText(text: Money.currency(row.total), width: Theme.Size.field,
                        emphasis: true)
            DerivedText(text: Money.currency(row.usable), width: Theme.Size.field)
            DerivedText(text: signed(row.changeAmount), width: Theme.Size.field,
                        tint: tint(for: row.changeAmount))
            DerivedText(text: signed(row.changePercent, percent: true),
                        width: Theme.Size.fieldSmall,
                        tint: tint(for: row.changePercent))
            DerivedText(text: Money.percent(row.savingsRate), width: Theme.Size.fieldSmall,
                        tint: (row.savingsRate ?? 0) > 0 ? .ftPositive : nil)

            Button {
                context.delete(record)
                try? context.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Color.ftNegative
                                              : Color.ftInkTertiary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Delete this record")
            .frame(width: Theme.Size.iconButton)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(hovering ? Color.ftSurfaceAlt : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func signed(_ value: Double?, percent: Bool = false) -> String {
        guard let value else { return Money.dash }
        let text = percent ? Money.percent(value) : Money.currency(value)
        return value > 0 ? "+" + text : text
    }

    private func tint(for value: Double?) -> Color? {
        guard let value, value != 0 else { return nil }
        return value > 0 ? .ftPositive : .ftNegative
    }
}
