import SwiftUI
import SwiftData
import Charts

struct GoalsView: View {
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

    private var dashboard: DashboardMetrics {
        DashboardMetrics.compute(records: LedgerEngine.derive(
            PortfolioStore.input(accounts: accounts, records: records, settings: settings, expenses: expenseItems)))
    }

    private var goal: GoalMetrics {
        GoalMetrics.compute(target: settings.targetNetWorth, dashboard: dashboard)
    }

    private var targetBinding: Binding<Double> {
        Binding(get: { settings.targetNetWorth },
                set: { settings.targetNetWorth = max(0, $0); try? context.save() })
    }

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records, settings: settings,
            expenses: expenseItems))
    }

    var body: some View {
        FillingScreen {
            hero
            metrics
            if derived.count > 1 {
                progressChart.fillsHeight(minimum: 260)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    /// How the target is actually being approached, which is the question the
    /// rest of the screen only answers as a single number.
    private var progressChart: some View {
        CardSection("Progress over time",
                    subtitle: "Every record against your \(Money.currency(goal.target)) target") {
            Chart {
                ForEach(derived) { row in
                    AreaMark(x: .value("Date", row.date),
                             y: .value("Net worth", row.total))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.ftAccent.opacity(0.22), Color.ftAccent.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                }
                ForEach(derived) { row in
                    LineMark(x: .value("Date", row.date),
                             y: .value("Net worth", row.total))
                        .foregroundStyle(Color.ftAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
                if let last = derived.last {
                    PointMark(x: .value("Date", last.date),
                              y: .value("Net worth", last.total))
                        .foregroundStyle(Color.ftAccent)
                        .symbolSize(80)
                }
                RuleMark(y: .value("Target", goal.target))
                    .foregroundStyle(Color.ftInkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target \(Money.currency(goal.target))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.ftInkTertiary)
                    }
            }
            .chartYScale(domain: 0...max(goal.target, goal.current) * 1.08)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.ftHairline)
                    AxisValueLabel().font(.system(size: 10))
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 10))
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Hero: the number you set leads the screen

    private var hero: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Your target")
                HeroField(value: targetBinding).padding(.top, 4)
                Text("Type a new figure and every number below updates.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .padding(.top, 9)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Progress")
                    Spacer()
                    Text(Money.percent(goal.progress))
                        .font(.figure(34))
                        .monospacedDigit()
                        .foregroundStyle((goal.progress ?? 0) >= 1 ? Color.ftPositive : Color.ftInk)
                        .contentTransition(.numericText())
                }

                progressTrack

                HStack {
                    Text(Money.currency(goal.current))
                        .font(.system(size: 11.5)).monospacedDigit()
                        .foregroundStyle(Color.ftInkSecondary)
                    Spacer()
                    Text(Money.currency(goal.target))
                        .font(.system(size: 11.5)).monospacedDigit()
                        .foregroundStyle(Color.ftInkTertiary)
                }

                HStack(spacing: 10) {
                    if goal.remaining == 0 {
                        DeltaPill(text: "Goal reached", direction: .up)
                    } else {
                        DeltaPill(text: "\(Money.currency(goal.remaining)) to go", direction: .flat)
                    }
                    Text(paceNote)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.ftInkTertiary)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: 420)
        }
        .ftCard(padding: 20)
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            let fraction = min(max(goal.progress ?? 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ftSurfaceAlt)
                    .overlay(Capsule().strokeBorder(Color.ftHairline, lineWidth: 1))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(hex: Theme.accountPalette[0]), Color.ftAccent],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 8 : 0))
            }
            .animation(.easeOut(duration: 0.28), value: fraction)
        }
        .frame(height: 12)
    }

    private var paceNote: String {
        guard goal.remaining > 0 else { return "nothing left to save" }
        guard let records = goal.estimatedRecordsToGoal else {
            return "needs a positive average change to estimate"
        }
        return "about \(records) more record\(records == 1 ? "" : "s") at your current pace"
    }

    // MARK: - Supporting metrics

    /// An HStack rather than an adaptive grid: adaptive sizes a fixed number of
    /// column slots from the minimum width, so four tiles in a six-slot grid
    /// stop two-thirds across. These four always span the full width, matching
    /// the card above them.
    private var metrics: some View {
        // Equal heights: a tile carrying a caption is naturally taller, so every
        // tile stretches to the tallest in the row rather than each sizing to
        // its own content.
        HStack(alignment: .top, spacing: 12) {
            MetricTile(title: "Current net worth", value: Money.currency(goal.current))
            MetricTile(title: "Remaining", value: Money.currency(goal.remaining))
            MetricTile(title: "Avg change per record",
                       value: Money.currency(dashboard.averageChange),
                       caption: changeCountCaption)
            MetricTile(title: "Est. records to goal",
                       value: goal.estimatedRecordsToGoal.map(String.init) ?? Money.dash,
                       caption: goal.estimatedRecordsToGoal == nil
                           ? "Needs a positive average change" : nil)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var changeCountCaption: String? {
        let derived = LedgerEngine.derive(
            PortfolioStore.input(accounts: accounts, records: records, settings: settings, expenses: expenseItems))
        let count = derived.filter { $0.changeAmount != nil }.count
        return count == 0 ? nil : "Across \(count) change\(count == 1 ? "" : "s")"
    }
}
