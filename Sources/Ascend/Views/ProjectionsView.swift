import SwiftUI
import SwiftData
import Charts

struct ProjectionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]

    private var settings: AppSettings { SeedData.settings(in: context) }
    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var projection: Projection {
        let input = PortfolioStore.input(accounts: accounts, records: records, settings: settings, expenses: expenseItems)
        return ProjectionEngine.project(input,
                                        records: LedgerEngine.derive(input),
                                        from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                if !projection.assumptions.hasLeftoverDestination {
                    Callout(text: "No account is set to receive the monthly leftover, so the surplus isn't being allocated. Pick one on the Accounts screen.",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .orange)
                }

                HStack(alignment: .top, spacing: Theme.gap) {
                    assumptionsCard
                    outlookCard
                }

                if projection.months.isEmpty {
                    ContentUnavailableView("Nothing to project yet",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Add a record on the Balances screen."))
                        .frame(height: 240)
                } else {
                    forecastChart
                    monthTable
                }
            }
            .padding(Theme.screenPadding)
        }
    }

    // MARK: - Assumptions

    private var assumptionsCard: some View {
        CardSection("Assumptions", subtitle: "Grey rows are worked out from the others") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 11) {
                GridRow {
                    Text("Monthly net income").font(.system(size: 12.5))
                    MoneyField(value: Binding(
                        get: { settings.monthlyNetIncome },
                        set: { settings.monthlyNetIncome = max(0, $0); try? context.save() }),
                        decimals: 2)
                }
                GridRow {
                    Text("Monthly expenses")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.ftInkTertiary)
                    DerivedText(text: Money.currency(projection.assumptions.maxMonthlyExpenses),
                                width: Theme.Size.field)
                }
                GridRow {
                    Text("Projection horizon (months)").font(.system(size: 12.5))
                    IntField(value: Binding(
                        get: { settings.projectionHorizonMonths },
                        set: { settings.projectionHorizonMonths = $0; try? context.save() }))
                }

                Divider().gridCellUnsizedAxes(.horizontal).padding(.vertical, 2)

                derivedRow("Total invested / month",
                           Money.currency(projection.assumptions.totalInvestedPerMonth))
                derivedRow(leftoverLabel,
                           Money.currency(projection.assumptions.leftoverPerMonth))
                derivedRow("Savings rate of income",
                           Money.percent(projection.assumptions.savingsRateOfIncome))
            }

            if !projection.assumptions.monthlyExpensesByAccount.isEmpty {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow("Paid out of")
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        ForEach(activeAccounts) { account in
                            if let amount = projection.assumptions
                                .monthlyExpensesByAccount[account.id], amount > 0 {
                                GridRow {
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Color(hex: account.colorHex))
                                            .frame(width: Theme.Size.dot, height: Theme.Size.dot)
                                        Text(account.name).font(.system(size: 12.5))
                                    }
                                    DerivedText(text: Money.currency(amount, decimals: 2),
                                                width: Theme.Size.field)
                                }
                            }
                        }
                    }
                    if projection.assumptions.unassignedMonthlyExpenses > 0 {
                        Text("\(Money.currency(projection.assumptions.unassignedMonthlyExpenses)) has no account set, so it comes out of the main one.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly expenses is the total of your **Expenses** screen, and each one is taken out of the account that pays it. Contributions and expected returns live on **Accounts**.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if projection.assumptions.maxMonthlyExpenses == 0 {
                    Text("No expenses logged yet, so a month currently costs nothing.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var leftoverLabel: String {
        if let name = activeAccounts.first(where: \.isLeftoverDestination)?.name {
            return "Leftover → \(name)"
        }
        return "Leftover / month"
    }

    private func derivedRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ftInkTertiary)
            DerivedText(text: value, width: Theme.Size.field)
        }
    }

    // MARK: - Outlook

    private var outlookCard: some View {
        CardSection("Outlook") {
            // The tiles share the card's height with the assumptions card
            // beside them, rather than the card stopping short of it.
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    MetricTile(title: "In 1 year",
                               value: Money.currency(projection.netWorth(atMonth: 12)))
                        .frame(maxHeight: .infinity)
                    MetricTile(title: "In 3 years",
                               value: Money.currency(projection.netWorth(atMonth: 36)))
                        .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    MetricTile(title: "In 5 years",
                               value: Money.currency(projection.netWorth(atMonth: 60)))
                        .frame(maxHeight: .infinity)
                    MetricTile(title: "Months to goal",
                               value: projection.monthsToGoal.map(String.init) ?? Money.dash,
                               caption: goalDateCaption,
                               valueColor: projection.monthsToGoal == nil
                                   ? .ftInkTertiary : .ftPositive)
                }
                .fixedSize(horizontal: false, vertical: true)
                if let horizon = projection.months.last {
                    MetricTile(title: "At horizon (\(settings.projectionHorizonMonths) mo)",
                               value: Money.currency(horizon.netWorth),
                               caption: horizon.date.formatted(.dateTime.month(.abbreviated).year()))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: Theme.Size.sidePanel)
        .frame(maxHeight: .infinity)
    }

    private var goalDateCaption: String? {
        guard let months = projection.monthsToGoal,
              let month = projection.months.first(where: { $0.month == months })
        else { return "Not reached within the horizon" }
        return month.date.formatted(.dateTime.month(.abbreviated).year())
    }

    // MARK: - Forecast

    private var forecastChart: some View {
        CardSection("Projected net worth", subtitle: forecastSubtitle) {
            Chart {
                ForEach(projection.months) { month in
                    AreaMark(x: .value("Month", month.month),
                             y: .value("Net worth", month.netWorth))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.ftAccent.opacity(0.24), Color.ftAccent.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                ForEach(projection.months) { month in
                    LineMark(x: .value("Month", month.month),
                             y: .value("Net worth", month.netWorth))
                        .foregroundStyle(Color.ftAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Target", settings.targetNetWorth))
                    .foregroundStyle(Color.ftInkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target \(Money.currency(settings.targetNetWorth))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                if let months = projection.monthsToGoal,
                   let crossing = projection.months.first(where: { $0.month == months }) {
                    PointMark(x: .value("Month", crossing.month),
                              y: .value("Net worth", crossing.netWorth))
                        .foregroundStyle(Color.ftPositive)
                        .symbolSize(110)
                        .annotation(position: .bottom) {
                            Text("month \(months)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.ftPositive)
                        }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.ftHairline)
                    AxisValueLabel().font(.system(size: 10))
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.ftHairline)
                    AxisValueLabel().font(.system(size: 10))
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
            .frame(height: 250)
        }
    }

    private var forecastSubtitle: String {
        let horizon = settings.projectionHorizonMonths
        if let months = projection.monthsToGoal {
            return "\(horizon) months, crossing \(Money.currency(settings.targetNetWorth)) at month \(months)"
        }
        return "\(horizon) months — target not reached within the horizon"
    }

    // MARK: - Month table

    private var monthTable: some View {
        CardSection("Month by month") {
            ScrollView(.vertical) {
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 7) {
                    GridRow {
                        Text("Month").frame(width: Theme.Size.control, alignment: .leading)
                        Text("Date").frame(width: Theme.Size.fieldSmall, alignment: .leading)
                        ForEach(activeAccounts) {
                            Text($0.name).frame(width: Theme.Size.field, alignment: .trailing)
                        }
                        Text("Net worth").frame(width: Theme.Size.field, alignment: .trailing)
                        Text("Usable").frame(width: Theme.Size.field, alignment: .trailing)
                        Spacer(minLength: 0)
                    }
                    .font(.tableHeader)
                    .tracking(Theme.tableHeaderTracking)
                    .foregroundStyle(Color.ftInkSecondary)

                    Divider().gridCellUnsizedAxes(.horizontal)

                    ForEach(projection.months) { month in
                        GridRow {
                            Text("\(month.month)")
                                .frame(width: Theme.Size.control, alignment: .leading)
                                .foregroundStyle(Color.ftInkTertiary)
                            Text(month.date, format: .dateTime.month(.abbreviated).year())
                                .frame(width: Theme.Size.fieldSmall, alignment: .leading)
                                .foregroundStyle(Color.ftInkSecondary)
                            ForEach(activeAccounts) { account in
                                Text(Money.currency(month.balances[account.id] ?? 0))
                                    .frame(width: Theme.Size.field, alignment: .trailing)
                                    .foregroundStyle(Color.ftInkSecondary)
                            }
                            Text(Money.currency(month.netWorth))
                                .frame(width: Theme.Size.field, alignment: .trailing)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.ftInk)
                            Text(Money.currency(month.usable))
                                .frame(width: Theme.Size.field, alignment: .trailing)
                                .foregroundStyle(Color.ftInkSecondary)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 11.5, design: .rounded))
                        .monospacedDigit()
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }
}
