import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context)))
    }

    private var metrics: DashboardMetrics { DashboardMetrics.compute(records: derived) }

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if derived.isEmpty {
                    ContentUnavailableView("No records yet",
                                           systemImage: "tablecells",
                                           description: Text("Add your first record on the Balances screen."))
                        .frame(height: 300)
                } else {
                    tiles
                    netWorthChart
                    changeChart
                }
            }
            .padding(20)
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            KPITile(title: "Current Net Worth",
                    value: Money.currency(metrics.currentNetWorth))
            KPITile(title: "Usable Cash",
                    value: Money.currency(metrics.usableCash),
                    caption: "Excludes restricted accounts")
            KPITile(title: "Latest Change (€)",
                    value: Money.currency(metrics.latestChangeAmount),
                    tint: (metrics.latestChangeAmount ?? 0) < 0 ? .red : .green)
            KPITile(title: "Latest Change (%)",
                    value: Money.percent(metrics.latestChangePercent),
                    tint: (metrics.latestChangePercent ?? 0) < 0 ? .red : .green)
            KPITile(title: "Total Growth",
                    value: Money.currency(metrics.totalGrowth),
                    caption: "Since first record")
            KPITile(title: "Best Month",
                    value: Money.currency(metrics.bestChange))
            KPITile(title: "Avg Monthly Change",
                    value: Money.currency(metrics.averageChange))
            KPITile(title: "Records Tracked",
                    value: "\(metrics.recordCount)")
            KPITile(title: "Avg Savings Rate",
                    value: Money.percent(metrics.averageSavingsRate))
        }
    }

    private var netWorthChart: some View {
        CardSection("Net Worth vs Usable Cash") {
            Chart {
                ForEach(derived) { row in
                    LineMark(x: .value("Date", row.date),
                             y: .value("Amount", row.total))
                        .foregroundStyle(by: .value("Series", "Total"))
                        .symbol(.circle)
                }
                ForEach(derived) { row in
                    LineMark(x: .value("Date", row.date),
                             y: .value("Amount", row.usable))
                        .foregroundStyle(by: .value("Series", "Usable"))
                        .symbol(.square)
                }
            }
            .chartYAxis {
                AxisMarks(format: FloatingPointFormatStyle<Double>.number.notation(.compactName))
            }
            .frame(height: 240)
        }
    }

    private var changeChart: some View {
        CardSection("Change per Record") {
            Chart(derived.filter { $0.changeAmount != nil }) { row in
                BarMark(x: .value("Date", row.date, unit: .day),
                        y: .value("Change", row.changeAmount ?? 0))
                    .foregroundStyle((row.changeAmount ?? 0) < 0 ? Color.red : Color.green)
            }
            .frame(height: 200)
        }
    }
}
