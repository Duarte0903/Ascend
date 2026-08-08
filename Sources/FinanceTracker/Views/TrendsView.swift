import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context)))
    }

    private var accountColors: [Color] { activeAccounts.map { Color(hex: $0.colorHex) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if derived.isEmpty {
                    ContentUnavailableView("Nothing to chart yet",
                                           systemImage: "chart.xyaxis.line",
                                           description: Text("Add records on the Balances screen."))
                        .frame(height: 300)
                } else {
                    stackedChart
                    comparisonChart
                    growthChart
                    savingsChart
                }
            }
            .padding(20)
        }
    }

    private var stackedChart: some View {
        CardSection("Account Balances Over Time (stacked)") {
            Chart {
                ForEach(derived) { row in
                    ForEach(activeAccounts) { account in
                        AreaMark(x: .value("Date", row.date),
                                 y: .value("Amount", row.amount(for: account.id)))
                            .foregroundStyle(by: .value("Account", account.name))
                    }
                }
            }
            .chartForegroundStyleScale(range: accountColors)
            .frame(height: 240)
        }
    }

    private var comparisonChart: some View {
        CardSection("Account Comparison") {
            Chart {
                ForEach(derived) { row in
                    ForEach(activeAccounts) { account in
                        LineMark(x: .value("Date", row.date),
                                 y: .value("Amount", row.amount(for: account.id)))
                            .foregroundStyle(by: .value("Account", account.name))
                            .symbol(by: .value("Account", account.name))
                    }
                }
            }
            .chartForegroundStyleScale(range: accountColors)
            .frame(height: 240)
        }
    }

    private var growthChart: some View {
        CardSection("Growth Rate per Record") {
            Chart(derived.filter { $0.changePercent != nil }) { row in
                LineMark(x: .value("Date", row.date),
                         y: .value("Change %", (row.changePercent ?? 0) * 100))
                    .symbol(.circle)
            }
            .chartYAxis {
                AxisMarks(format: FloatingPointFormatStyle<Double>.number
                    .precision(.fractionLength(1)))
            }
            .frame(height: 200)
        }
    }

    private var savingsChart: some View {
        CardSection("Savings Rate per Record") {
            Chart(derived.filter { $0.savingsRate != nil }) { row in
                BarMark(x: .value("Date", row.date, unit: .day),
                        y: .value("Savings Rate", (row.savingsRate ?? 0) * 100))
                    .foregroundStyle(.teal)
            }
            .chartYAxis {
                AxisMarks(format: FloatingPointFormatStyle<Double>.number
                    .precision(.fractionLength(1)))
            }
            .frame(height: 200)
        }
    }
}
