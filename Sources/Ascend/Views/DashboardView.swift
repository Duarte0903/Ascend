import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]

    @AppStorage("dateRange") private var rangeRaw = DateRangeFilter.all.rawValue

    private var range: DateRangeFilter {
        DateRangeFilter(rawValue: rangeRaw) ?? .all
    }

    /// Derived over the full history, then windowed — so each record's change
    /// stays relative to its real predecessor.
    private var derived: [DerivedRecord] {
        range.apply(to: allDerived, now: Date())
    }

    private var allDerived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context),
            expenses: expenseItems))
    }

    private var metrics: DashboardMetrics { DashboardMetrics.compute(records: derived) }

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    var body: some View {
        FillingScreen {
            if allDerived.isEmpty {
                ContentUnavailableView("No records yet",
                                       systemImage: "tablecells",
                                       description: Text("Add your first record on the Balances screen."))
                    .frame(maxWidth: .infinity)
                    .fillsHeight()
            } else if derived.isEmpty {
                NoResultsInRange(range: range) { rangeRaw = DateRangeFilter.all.rawValue }
            } else {
                hero
                metricGrid
                charts.fillsHeight(minimum: 260)
            }
        }
        .toolbar {
            DateRangePicker(selection: Binding(
                get: { range }, set: { rangeRaw = $0.rawValue }))
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Current net worth")
                HeroFigure(value: Money.currency(metrics.currentNetWorth))
                    .contentTransition(.numericText())
                    .padding(.top, 2)
                HStack(spacing: 8) {
                    DeltaPill.amount(metrics.latestChangeAmount,
                                     formatted: Money.currency(metrics.latestChangeAmount))
                    DeltaPill.amount(metrics.latestChangePercent,
                                     formatted: Money.percent(metrics.latestChangePercent))
                    if let date = derived.dropLast().last?.date {
                        Text("since \(date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                }
                .padding(.top, 9)
            }
            Spacer(minLength: 12)
            sparkline.frame(maxWidth: 460, minHeight: 150)
        }
        .ftCard(padding: 20)
    }

    private var sparkline: some View {
        Chart {
            ForEach(derived) { row in
                AreaMark(x: .value("Date", row.date), y: .value("Net worth", row.total))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.ftAccent.opacity(0.28), Color.ftAccent.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.linear)
            }
            ForEach(derived) { row in
                LineMark(x: .value("Date", row.date), y: .value("Net worth", row.total))
                    .foregroundStyle(Color.ftAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
            }
            if let last = derived.last {
                PointMark(x: .value("Date", last.date), y: .value("Net worth", last.total))
                    .foregroundStyle(Color.ftAccent)
                    .symbolSize(90)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartPlotStyle { $0.background(.clear) }
    }

    // MARK: - Metrics

    private var metricGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(title: "Usable cash",
                       value: Money.currency(metrics.usableCash),
                       caption: usableCaption)
            MetricTile(title: "Total growth",
                       value: signed(metrics.totalGrowth),
                       caption: "Since first record",
                       valueColor: (metrics.totalGrowth ?? 0) < 0 ? .ftNegative : .ftPositive)
            MetricTile(title: "Best month",
                       value: Money.currency(metrics.bestChange),
                       caption: bestMonthCaption)
            MetricTile(title: "Avg monthly change",
                       value: Money.currency(metrics.averageChange),
                       caption: changeCountCaption)
            MetricTile(title: "Avg savings rate",
                       value: Money.percent(metrics.averageSavingsRate),
                       caption: "Of previous total")
            MetricTile(title: "Records tracked",
                       value: "\(metrics.recordCount)",
                       caption: rangeCaption)
        }
    }

    private var usableCaption: String? {
        let excluded = accounts.filter { !$0.isArchived && !$0.includeInUsable }
        guard !excluded.isEmpty else { return nil }
        return "Excludes " + excluded.map(\.name).joined(separator: ", ")
    }

    private var bestMonthCaption: String? {
        guard let best = derived.filter({ $0.changeAmount != nil })
            .max(by: { ($0.changeAmount ?? 0) < ($1.changeAmount ?? 0) }) else { return nil }
        return best.date.formatted(.dateTime.day().month(.wide))
    }

    private var changeCountCaption: String? {
        let count = derived.filter { $0.changeAmount != nil }.count
        return count == 0 ? nil : "Across \(count) change\(count == 1 ? "" : "s")"
    }

    private var rangeCaption: String? {
        guard let first = derived.first?.date, let last = derived.last?.date else { return nil }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func signed(_ value: Double?) -> String {
        guard let value else { return Money.dash }
        return (value > 0 ? "+" : "") + Money.currency(value)
    }

    // MARK: - Charts

    private var charts: some View {
        HStack(alignment: .top, spacing: Theme.gap) {
            CardSection("Net worth vs usable cash",
                        subtitle: "All accounts, and the same excluding restricted ones") {
                Chart {
                    ForEach(derived) { row in
                        AreaMark(x: .value("Date", row.date), y: .value("Amount", row.total))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.ftAccent.opacity(0.22), Color.ftAccent.opacity(0.01)],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.linear)
                    }
                    ForEach(derived) { row in
                        LineMark(x: .value("Date", row.date), y: .value("Amount", row.total))
                            .foregroundStyle(by: .value("Series", "Total"))
                            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                    ForEach(derived) { row in
                        LineMark(x: .value("Date", row.date), y: .value("Amount", row.usable))
                            .foregroundStyle(by: .value("Series", "Usable"))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .interpolationMethod(.linear)
                    }
                    if let last = derived.last {
                        PointMark(x: .value("Date", last.date), y: .value("Amount", last.total))
                            .foregroundStyle(Color.ftAccent).symbolSize(70)
                        PointMark(x: .value("Date", last.date), y: .value("Amount", last.usable))
                            .foregroundStyle(Color(hex: Theme.accountPalette[2])).symbolSize(70)
                    }
                }
                .chartForegroundStyleScale([
                    "Total": Color.ftAccent,
                    "Usable": Color(hex: Theme.accountPalette[2]),
                ])
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { compactAxis }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .frame(maxHeight: .infinity)
            }
            .fillsHeight(minimum: 260)

            CardSection("Change per record",
                        subtitle: "Movement between consecutive entries") {
                Chart(derived.filter { $0.changeAmount != nil }) { row in
                    BarMark(x: .value("Date", row.date, unit: .day),
                            y: .value("Change", row.changeAmount ?? 0),
                            width: .fixed(26))
                        .foregroundStyle(LinearGradient(
                            colors: (row.changeAmount ?? 0) < 0
                                ? [Color.ftNegative, Color.ftNegative.opacity(0.6)]
                                : [Color.ftPositive, Color.ftPositive.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom))
                        .cornerRadius(5)
                }
                .chartYAxis { compactAxis }
                .frame(maxHeight: .infinity)
            }
            .fillsHeight(minimum: 260)
        }
    }

    private var compactAxis: some AxisContent {
        AxisMarks(position: .leading) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .foregroundStyle(Color.ftHairline)
            AxisValueLabel()
                .font(.system(size: 10))
                .foregroundStyle(Color.ftInkTertiary)
        }
    }
}
