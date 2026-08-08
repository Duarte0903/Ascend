import SwiftUI
import SwiftData

struct BalancesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    @State private var hoveredRow: UUID?

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context)))
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
                } else {
                    table
                }
            }
            .padding(Theme.screenPadding)
        }
        .toolbar {
            ToolbarItemGroup {
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

    private var headerRow: some View {
        GridRow {
            Text("Date").frame(width: 108, alignment: .leading)
            ForEach(activeAccounts) { account in
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: account.colorHex)).frame(width: 7, height: 7)
                    Text(account.name)
                }
                .frame(width: 112, alignment: .trailing)
            }
            Text("Total").frame(width: 96)
            Text("Usable").frame(width: 96)
            Text("Change").frame(width: 92)
            Text("Change %").frame(width: 82)
            Text("Savings rate").frame(width: 92)
            Color.clear.frame(width: 22)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(Color.ftInkTertiary)
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
                    .frame(width: 108)

                ForEach(activeAccounts) { account in
                    MoneyField(value: Binding(
                        get: { record.amount(for: account.id) },
                        set: { record.setAmount($0, for: account.id); try? context.save() }),
                        width: 112)
                }

                DerivedText(text: Money.currency(row.total), width: 96, emphasis: true)
                DerivedText(text: Money.currency(row.usable), width: 96)
                DerivedText(text: signed(row.changeAmount), width: 92,
                            tint: tint(for: row.changeAmount))
                DerivedText(text: signed(row.changePercent, percent: true), width: 82,
                            tint: tint(for: row.changePercent))
                DerivedText(text: Money.percent(row.savingsRate), width: 92,
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
                .frame(width: 22)
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
