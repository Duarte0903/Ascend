import SwiftUI
import SwiftData

struct BalancesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]

    @State private var hoveredRow: UUID?

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

    private var allDerived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context),
            expenses: expenseItems))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Callout(text: "Boxed cells are yours to fill. Everything shaded to the right is calculated and updates as you type.")

                if records.isEmpty {
                    ContentUnavailableView("No records yet",
                                           systemImage: "tablecells",
                                           description: Text("Add your first record to start tracking."))
                        .frame(height: 300)
                } else if derived.isEmpty {
                    NoResultsInRange(range: range) { rangeRaw = DateRangeFilter.all.rawValue }
                } else {
                    table
                }
            }
            .padding(Theme.screenPadding)
        }
        .toolbar {
            ToolbarItemGroup {
                DateRangePicker(selection: Binding(
                    get: { range }, set: { rangeRaw = $0.rawValue }))
                Button("Duplicate Last", systemImage: "doc.on.doc") { duplicateLast() }
                    .disabled(records.isEmpty)
                Button("Add Record", systemImage: "plus") { addRecord() }
                    .keyboardShortcut("n")
            }
        }
    }

    private var table: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 0) {
                headerRow
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(derived.enumerated()), id: \.element.id) { index, row in
                    rowView(row)
                    if index < derived.count - 1 {
                        Divider().gridCellUnsizedAxes(.horizontal).opacity(0.6)
                    }
                }
            }
            .padding(Theme.cardPadding)
        }
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

    private var headerRow: some View {
        GridRow {
            Text("Date").frame(width: Theme.Size.field, alignment: .leading)
            ForEach(activeAccounts) { account in
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
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func rowView(_ row: DerivedRecord) -> some View {
        if let record = records.first(where: { $0.id == row.id }) {
            GridRow {
                DatePicker("", selection: Binding(
                    get: { record.date },
                    set: { record.date = $0; try? context.save() }),
                    displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: Theme.Size.field)

                ForEach(activeAccounts) { account in
                    MoneyField(value: Binding(
                        get: { record.amount(for: account.id) },
                        set: { record.setAmount($0, for: account.id); try? context.save() }),
                        width: accountColumnWidth)
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
                        .foregroundStyle(hoveredRow == row.id ? Color.ftNegative : Color.ftInkTertiary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Delete this record")
                .frame(width: Theme.Size.iconButton)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .background(hoveredRow == row.id ? Color.ftSurfaceAlt : .clear)
            .onHover { hoveredRow = $0 ? row.id : (hoveredRow == row.id ? nil : hoveredRow) }
        }
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
