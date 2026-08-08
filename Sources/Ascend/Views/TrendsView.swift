import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]

    @AppStorage("dateRange") private var rangeRaw = DateRangeFilter.all.rawValue
    @State private var hiddenAccounts: Set<UUID> = []

    private var range: DateRangeFilter {
        DateRangeFilter(rawValue: rangeRaw) ?? .all
    }

    /// Accounts the charts should plot. Hiding one never changes a stored
    /// figure — Total and Usable keep counting every account.
    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived && !hiddenAccounts.contains($0.id) }
    }

    private var allActiveAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var derived: [DerivedRecord] {
        range.apply(to: allDerived, now: Date())
    }

    private var allDerived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context),
            expenses: expenseItems))
    }

    private var accountColors: [Color] { activeAccounts.map { Color(hex: $0.colorHex) } }

    var body: some View {
        FillingScreen {
            if allDerived.isEmpty {
                ContentUnavailableView("Nothing to chart yet",
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("Add records on the Balances screen."))
                    .frame(maxWidth: .infinity)
                    .fillsHeight()
            } else if derived.isEmpty {
                NoResultsInRange(range: range) { rangeRaw = DateRangeFilter.all.rawValue }
            } else {
                // Two rows of two, each row taking half the leftover height.
                HStack(alignment: .top, spacing: Theme.gap) {
                    stackedChart.fillsHeight(minimum: 230)
                    comparisonChart.fillsHeight(minimum: 230)
                }
                .fillsHeight(minimum: 230)
                HStack(alignment: .top, spacing: Theme.gap) {
                    growthChart.fillsHeight(minimum: 230)
                    savingsChart.fillsHeight(minimum: 230)
                }
                .fillsHeight(minimum: 230)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                AccountFilterMenu(accounts: allActiveAccounts, hidden: $hiddenAccounts)
                DateRangePicker(selection: Binding(
                    get: { range }, set: { rangeRaw = $0.rawValue }))
            }
        }
    }

    private var stackedChart: some View {
        CardSection("Account balances over time", subtitle: "Stacked, every active account") {
            Chart {
                ForEach(derived) { row in
                    ForEach(activeAccounts) { account in
                        AreaMark(x: .value("Date", row.date),
                                 y: .value("Amount", row.amount(for: account.id)),
                                 stacking: .standard)
                            .foregroundStyle(by: .value("Account", account.name))
                            .interpolationMethod(.linear)
                    }
                }
            }
            .chartForegroundStyleScale(range: accountColors)
            .chartYAxis { softAxis }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
            .frame(maxHeight: .infinity)
        }
    }

    private var comparisonChart: some View {
        CardSection("Account comparison", subtitle: "Each account on its own line") {
            Chart {
                ForEach(derived) { row in
                    ForEach(activeAccounts) { account in
                        LineMark(x: .value("Date", row.date),
                                 y: .value("Amount", row.amount(for: account.id)))
                            .foregroundStyle(by: .value("Account", account.name))
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                }
            }
            .chartForegroundStyleScale(range: accountColors)
            .chartYAxis { softAxis }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
            .frame(maxHeight: .infinity)
        }
    }

    private var growthChart: some View {
        CardSection("Growth rate per record", subtitle: "Percentage change between entries") {
            Chart(derived.filter { $0.changePercent != nil }) { row in
                LineMark(x: .value("Date", row.date),
                         y: .value("Change", (row.changePercent ?? 0) * 100))
                    .foregroundStyle(Color.ftAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                PointMark(x: .value("Date", row.date),
                          y: .value("Change", (row.changePercent ?? 0) * 100))
                    .foregroundStyle(Color.ftAccent)
                    .symbolSize(55)
            }
            .chartYAxis { softAxis }
            .frame(maxHeight: .infinity)
        }
    }

    private var savingsChart: some View {
        CardSection("Savings rate per record", subtitle: savingsSubtitle) {
            Chart(derived.filter { $0.savingsRate != nil }) { row in
                BarMark(x: .value("Date", row.date, unit: .day),
                        y: .value("Savings rate", (row.savingsRate ?? 0) * 100),
                        width: .fixed(26))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: Theme.accountPalette[1]),
                                 Color(hex: Theme.accountPalette[1]).opacity(0.55)],
                        startPoint: .top, endPoint: .bottom))
                    .cornerRadius(5)
            }
            .chartYAxis { softAxis }
            .frame(maxHeight: .infinity)
        }
    }

    private var savingsSubtitle: String {
        let names = activeAccounts.filter(\.countsAsSavings).map(\.name)
        guard !names.isEmpty else { return "No accounts are flagged as savings" }
        return "Money moved into " + names.joined(separator: " and ")
    }

    private var softAxis: some AxisContent {
        AxisMarks(position: .leading) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .foregroundStyle(Color.ftHairline)
            AxisValueLabel().font(.system(size: 10))
                .foregroundStyle(Color.ftInkTertiary)
        }
    }
}
