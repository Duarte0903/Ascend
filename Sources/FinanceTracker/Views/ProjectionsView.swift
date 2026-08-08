import SwiftUI
import SwiftData
import Charts

struct ProjectionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var settings: AppSettings { SeedData.settings(in: context) }
    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var projection: Projection {
        let input = PortfolioStore.input(accounts: accounts, records: records, settings: settings)
        return ProjectionEngine.project(input,
                                        records: LedgerEngine.derive(input),
                                        from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !projection.assumptions.hasLeftoverDestination {
                    Label("No leftover destination is set, so the monthly surplus is not being allocated. Pick one on the Accounts screen.",
                          systemImage: "exclamationmark.triangle.fill")
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(alignment: .top, spacing: 16) {
                    assumptionsCard
                    outlookCard
                }

                if projection.months.isEmpty {
                    ContentUnavailableView("Nothing to project yet",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Add a record on the Balances screen."))
                        .frame(height: 220)
                } else {
                    forecastChart
                    monthTable
                }
            }
            .padding(20)
        }
    }

    private var assumptionsCard: some View {
        CardSection("Assumptions", subtitle: "Grey rows are derived from the others.") {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Monthly Net Income")
                        numberField(Binding(
                            get: { settings.monthlyNetIncome },
                            set: { settings.monthlyNetIncome = $0; try? context.save() }))
                    }
                    GridRow {
                        Text("Max Monthly Expenses")
                        numberField(Binding(
                            get: { settings.maxMonthlyExpenses },
                            set: { settings.maxMonthlyExpenses = $0; try? context.save() }))
                    }
                    GridRow {
                        Text("Projection Horizon (months)")
                        TextField("", value: Binding(
                            get: { settings.projectionHorizonMonths },
                            set: { settings.projectionHorizonMonths = max(1, min(600, $0))
                                   try? context.save() }),
                            format: .number)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    derivedRow("Total Invested / month",
                               Money.currency(projection.assumptions.totalInvestedPerMonth))
                    derivedRow("Leftover / month",
                               Money.currency(projection.assumptions.leftoverPerMonth))
                    derivedRow("Savings Rate (of income)",
                               Money.percent(projection.assumptions.savingsRateOfIncome))
                }
                Text("Per-account contributions and expected returns live on the Accounts screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var outlookCard: some View {
        CardSection("Outlook") {
            VStack(spacing: 12) {
                KPITile(title: "Projected in 1 Year",
                        value: Money.currency(projection.netWorth(atMonth: 12)))
                KPITile(title: "Projected in 3 Years",
                        value: Money.currency(projection.netWorth(atMonth: 36)))
                KPITile(title: "Projected in 5 Years",
                        value: Money.currency(projection.netWorth(atMonth: 60)))
                KPITile(title: "At Horizon (\(settings.projectionHorizonMonths) mo)",
                        value: Money.currency(projection.months.last?.netWorth))
                KPITile(title: "Months to Goal",
                        value: projection.monthsToGoal.map(String.init) ?? Money.dash,
                        caption: projection.monthsToGoal == nil
                            ? "Not reached within the horizon" : nil)
            }
        }
        .frame(width: 260)
    }

    private var forecastChart: some View {
        CardSection("Projected Net Worth") {
            Chart {
                ForEach(projection.months) { month in
                    LineMark(x: .value("Month", month.month),
                             y: .value("Net Worth", month.netWorth))
                }
                RuleMark(y: .value("Target", settings.targetNetWorth))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target \(Money.currency(settings.targetNetWorth))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYAxis {
                AxisMarks(format: FloatingPointFormatStyle<Double>.number
                    .notation(.compactName))
            }
            .frame(height: 250)
        }
    }

    private var monthTable: some View {
        CardSection("Month by Month") {
            ScrollView(.vertical) {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Month").gridColumnAlignment(.leading)
                        Text("Date").gridColumnAlignment(.leading)
                        ForEach(activeAccounts) { Text($0.name) }
                        Text("Net Worth")
                        Text("Usable")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(projection.months) { month in
                        GridRow {
                            Text("\(month.month)").gridColumnAlignment(.leading)
                            Text(month.date, format: .dateTime.month(.abbreviated).year())
                                .gridColumnAlignment(.leading)
                            ForEach(activeAccounts) { account in
                                Text(Money.currency(month.balances[account.id] ?? 0))
                            }
                            Text(Money.currency(month.netWorth)).fontWeight(.medium)
                            Text(Money.currency(month.usable))
                        }
                        .font(.system(.caption, design: .rounded))
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private func numberField(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0)))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
    }

    private func derivedRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
        }
    }
}
