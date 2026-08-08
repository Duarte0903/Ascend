import SwiftUI
import SwiftData
import Charts

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var settings: AppSettings { SeedData.settings(in: context) }

    private var dashboard: DashboardMetrics {
        DashboardMetrics.compute(records: LedgerEngine.derive(
            PortfolioStore.input(accounts: accounts, records: records, settings: settings)))
    }

    private var goal: GoalMetrics {
        GoalMetrics.compute(target: settings.targetNetWorth, dashboard: dashboard)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                targetCard
                tiles
                progressCard
            }
            .padding(20)
        }
    }

    private var targetCard: some View {
        CardSection("Target") {
            HStack {
                Text("Target Net Worth")
                Spacer()
                TextField("", value: Binding(
                    get: { settings.targetNetWorth },
                    set: { settings.targetNetWorth = max(0, $0); try? context.save() }),
                    format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Text("€")
            }
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            KPITile(title: "Current Net Worth", value: Money.currency(goal.current))
            KPITile(title: "Remaining to Goal", value: Money.currency(goal.remaining))
            KPITile(title: "Progress", value: Money.percent(goal.progress),
                    tint: (goal.progress ?? 0) >= 1 ? .green : .primary)
            KPITile(title: "Avg Change per Record",
                    value: Money.currency(dashboard.averageChange))
            KPITile(title: "Est. Records to Goal",
                    value: goal.estimatedRecordsToGoal.map(String.init) ?? Money.dash,
                    caption: goal.estimatedRecordsToGoal == nil
                        ? "Needs a positive average change" : nil)
        }
    }

    private var progressCard: some View {
        CardSection("Goal Progress") {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: min(max(goal.progress ?? 0, 0), 1))
                    .progressViewStyle(.linear)
                Chart {
                    BarMark(x: .value("Amount", goal.current),
                            y: .value("Goal", "Progress"))
                        .foregroundStyle(by: .value("Part", "Progress"))
                    BarMark(x: .value("Amount", goal.remaining),
                            y: .value("Goal", "Progress"))
                        .foregroundStyle(by: .value("Part", "Remaining"))
                }
                .chartForegroundStyleScale(range: [Color.green, Color.gray.opacity(0.35)])
                .frame(height: 90)
                HStack(spacing: 16) {
                    Label("Progress \(Money.currency(goal.current))",
                          systemImage: "square.fill").foregroundStyle(.green)
                    Label("Remaining \(Money.currency(goal.remaining))",
                          systemImage: "square.fill").foregroundStyle(.gray)
                }
                .font(.caption)
            }
        }
    }
}
