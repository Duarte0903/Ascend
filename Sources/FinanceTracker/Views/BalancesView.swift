import SwiftUI
import SwiftData

struct BalancesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if records.isEmpty {
                ContentUnavailableView("No records yet",
                                       systemImage: "tablecells",
                                       description: Text("Add your first record to start tracking."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                        headerRow
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(derived) { row in
                            rowView(row)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Editable columns are boxed; derived columns are grey and update automatically.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Duplicate Last", systemImage: "doc.on.doc") { duplicateLast() }
                .disabled(records.isEmpty)
            Button("Add Record", systemImage: "plus") { addRecord() }
                .keyboardShortcut("n")
        }
        .padding(16)
    }

    private var headerRow: some View {
        GridRow {
            Text("Date").frame(width: 110, alignment: .leading)
            ForEach(activeAccounts) { account in
                Text(account.name).frame(width: 110, alignment: .trailing)
            }
            Text("Total").frame(width: 100)
            Text("Usable").frame(width: 100)
            Text("Change").frame(width: 90)
            Text("Change %").frame(width: 80)
            Text("Savings Rate").frame(width: 90)
            Color.clear.frame(width: 24)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
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
                    .frame(width: 110)

                ForEach(activeAccounts) { account in
                    TextField("", value: Binding(
                        get: { record.amount(for: account.id) },
                        set: { record.setAmount($0, for: account.id); try? context.save() }),
                        format: .number.precision(.fractionLength(2)))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }

                derivedCell(Money.currency(row.total), width: 100)
                derivedCell(Money.currency(row.usable), width: 100)
                derivedCell(Money.currency(row.changeAmount), width: 90,
                            tint: (row.changeAmount ?? 0) < 0 ? .red : .primary)
                derivedCell(Money.percent(row.changePercent), width: 80)
                derivedCell(Money.percent(row.savingsRate), width: 90)

                Button {
                    context.delete(record)
                    try? context.save()
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete this record")
                .frame(width: 24)
            }
        }
    }

    private func derivedCell(_ text: String, width: CGFloat, tint: Color = .primary) -> some View {
        Text(text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: width, alignment: .trailing)
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
