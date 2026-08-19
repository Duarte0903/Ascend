import SwiftUI
import SwiftData
import Charts

struct InvestmentsView: View {
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
    @State private var showingManager = false

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records, settings: settings,
            expenses: expenseItems))
    }

    private var metrics: InvestmentMetrics {
        let input = PortfolioStore.input(accounts: accounts, records: records,
                                         settings: settings, expenses: expenseItems)
        return InvestmentMetrics.compute(accounts: input.accounts,
                                         records: LedgerEngine.derive(input),
                                         target: settings.investmentReturnTarget)
    }

    private var trackedAccounts: [Account] {
        accounts.filter { !$0.isArchived && $0.isTrackedInvestment }
    }

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    /// Accounts that clearly earn something but are not being tracked. Without
    /// surfacing these, an account quietly sits outside the totals and the
    /// screen looks wrong for a reason that is nowhere on it.
    private var untrackedEarners: [Account] {
        accounts.filter { !$0.isArchived && !$0.isTrackedInvestment
                          && $0.expectedAnnualReturn > 0
                          && $0.investmentTracking != .excluded }
    }

    var body: some View {
        FillingScreen {
            if !untrackedEarners.isEmpty { untrackedNotice }

            if trackedAccounts.isEmpty {
                ContentUnavailableView(
                    "Nothing tracked yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Accounts counting toward your savings rate appear here automatically, or add one yourself from Manage Accounts."))
                    .frame(maxWidth: .infinity)
                    .fillsHeight()
            } else {
                hero
                holdingsTable
                if derived.count > 1 { valueChart.fillsHeight(minimum: 260) }
                else { Spacer(minLength: 0) }
            }
        }
        .toolbar {
            Button("Manage Accounts…", systemImage: "slider.horizontal.3") {
                showingManager = true
            }
            .help("Choose which accounts appear here")
            .popover(isPresented: $showingManager, arrowEdge: .bottom) {
                managerSheet
            }
        }
    }

    /// Full control, one row per account: follow the automatic rule, or force
    /// it in or out.
    private var managerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogHeader(title: "Tracked Accounts",
                         subtitle: "Automatic follows your savings-rate flag. Override it here without changing that flag or any other screen.") {
                showingManager = false
            }

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(activeAccounts.enumerated()), id: \.element.id) { index, account in
                        HStack(spacing: 12) {
                            AccountIcon(account, size: Theme.Size.iconMedium)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name).font(.system(size: 13, weight: .medium))
                                Text(account.investmentTracking
                                        .explanation(countsAsSavings: account.countsAsSavings))
                                    .font(.system(size: 11))
                                    .foregroundStyle(account.isTrackedInvestment
                                                     ? Color.ftInkTertiary : Color.ftInkTertiary)
                            }
                            Spacer(minLength: 12)
                            Picker("", selection: Binding(
                                get: { account.investmentTracking },
                                set: { account.investmentTracking = $0; try? context.save() })) {
                                ForEach(InvestmentTracking.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(width: Theme.Size.picker)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)

                        if index < activeAccounts.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(height: 260)
            .background(Color.ftSurface)

            Divider()

            HStack {
                Text("\(trackedAccounts.count) of \(activeAccounts.count) tracked")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                Spacer()
                Button("Done") { showingManager = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: Theme.Size.sheetNarrow)
        .background(Color.ftCanvas)
    }

    private var untrackedNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Callout(text: "These accounts earn a return but aren't tracked here. Adding one only affects this screen — your savings rate is left alone.",
                    systemImage: "exclamationmark.circle")

            ForEach(untrackedEarners) { account in
                HStack(spacing: 10) {
                    AccountIcon(account, size: Theme.Size.iconMedium)
                    Text(account.name).font(.system(size: 12.5, weight: .medium))
                    Text("\(Money.percent(account.expectedAnnualReturn)) expected")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ftInkTertiary)
                    Spacer()
                    Button("Track this") {
                        account.investmentTracking = .included
                        try? context.save()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(Color.ftSurface,
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Color.ftHairline, lineWidth: 1))
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(metrics.comparingAnnualised ? "Return per year" : "Return so far")
                HeroFigure(value: Money.percent(metrics.comparingAnnualised
                                                ? metrics.annualisedReturn
                                                : metrics.overallReturn))
                    .contentTransition(.numericText())
                    .padding(.top, 2)
                HStack(spacing: 8) {
                    DeltaPill.amount(metrics.totalProfit,
                                     formatted: Money.currency(metrics.totalProfit))
                    Text(verdict)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.ftInkTertiary)
                }
                .padding(.top, 9)
                Text(historyNote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Target return")
                    Spacer()
                    MoneyField(value: Binding(
                        get: { settings.investmentReturnTarget * 100 },
                        set: { settings.investmentReturnTarget = $0 / 100
                               try? context.save() }),
                        decimals: 2, width: Theme.Size.fieldSmall, suffix: "%")
                }
                Text("Beat this and your investments are growing faster than your benchmark — inflation, say.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    GridRow {
                        Text("Invested").font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkTertiary)
                        DerivedText(text: Money.currency(metrics.totalInvested),
                                    width: Theme.Size.field)
                    }
                    GridRow {
                        Text("Current value").font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkTertiary)
                        DerivedText(text: Money.currency(metrics.totalValue),
                                    width: Theme.Size.field, emphasis: true)
                    }
                    GridRow {
                        Text("Total return").font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkTertiary)
                        DerivedText(text: Money.percent(metrics.overallReturn),
                                    width: Theme.Size.field,
                                    tint: metrics.overallReturn.map(tint) ?? nil)
                    }
                    GridRow {
                        Text("Per year").font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkTertiary)
                        DerivedText(text: Money.percent(metrics.annualisedReturn),
                                    width: Theme.Size.field,
                                    tint: metrics.annualisedReturn.map(tint) ?? nil)
                    }
                    GridRow {
                        Text(metrics.meetsTarget ? "Above target by" : "Short of target by")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkTertiary)
                        DerivedText(text: Money.currency(abs(metrics.amountToTarget)),
                                    width: Theme.Size.field,
                                    tint: metrics.meetsTarget ? .ftPositive : .ftNegative)
                    }
                }
            }
            .frame(maxWidth: 420)
        }
        .ftCard(padding: 20)
    }

    private var verdict: String {
        guard metrics.overallReturn != nil else {
            return "record what you have put in to see a return"
        }
        let target = Money.percent(metrics.target)
        return metrics.meetsTarget
            ? "ahead of your \(target) a year target"
            : "behind your \(target) a year target"
    }

    /// Says plainly which number is on screen and why, so a total return is
    /// never mistaken for an annual one.
    private var historyNote: String {
        guard let since = metrics.trackedSince, let years = metrics.years else {
            return "Log a couple of records and this can be measured over time."
        }
        let from = since.formatted(.dateTime.month(.abbreviated).year())
        if metrics.comparingAnnualised {
            return "Per year, from \(String(format: "%.1f", years)) years of records since \(from)."
        }
        return "Total since \(from) — under a year of records, so it cannot be stated per year yet. Your \(Money.percent(metrics.target)) target is an annual rate."
    }

    // MARK: - Holdings

    private var holdingsTable: some View {
        CardSection("Holdings",
                    subtitle: "Amount invested is yours to keep up to date; value is the latest balance you logged") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                GridRow {
                    Text("Account").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Invested").frame(width: Theme.Size.field, alignment: .trailing)
                    Text("Value").frame(width: Theme.Size.field, alignment: .trailing)
                    Text("Profit").frame(width: Theme.Size.field, alignment: .trailing)
                    Text("Return").frame(width: Theme.Size.fieldSmall, alignment: .trailing)
                    Text("Per year").frame(width: Theme.Size.fieldSmall, alignment: .trailing)
                    Text("Share").frame(width: Theme.Size.fieldSmall, alignment: .trailing)
                }
                .font(.tableHeader)
                .tracking(Theme.tableHeaderTracking)
                .foregroundStyle(Color.ftInkSecondary)
                .padding(.bottom, 8)

                Divider().gridCellUnsizedAxes(.horizontal)

                ForEach(Array(metrics.holdings.enumerated()), id: \.element.id) { index, holding in
                    holdingRow(holding)
                    if index < metrics.holdings.count - 1 {
                        Divider().gridCellUnsizedAxes(.horizontal).opacity(0.6)
                    }
                }

                Divider().gridCellUnsizedAxes(.horizontal)

                GridRow {
                    Text("Total").font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DerivedText(text: Money.currency(metrics.totalInvested),
                                width: Theme.Size.field, emphasis: true)
                    DerivedText(text: Money.currency(metrics.totalValue),
                                width: Theme.Size.field, emphasis: true)
                    DerivedText(text: signed(metrics.totalProfit),
                                width: Theme.Size.field, emphasis: true,
                                tint: tint(metrics.totalProfit))
                    DerivedText(text: Money.percent(metrics.overallReturn),
                                width: Theme.Size.fieldSmall, emphasis: true,
                                tint: metrics.overallReturn.map(tint) ?? nil)
                    DerivedText(text: Money.percent(metrics.annualisedReturn),
                                width: Theme.Size.fieldSmall, emphasis: true,
                                tint: metrics.annualisedReturn.map(tint) ?? nil)
                    DerivedText(text: Money.percent(1.0),
                                width: Theme.Size.fieldSmall, emphasis: true)
                }
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func holdingRow(_ holding: InvestmentHolding) -> some View {
        if let account = accounts.first(where: { $0.id == holding.accountID }) {
            GridRow {
                HStack(spacing: 8) {
                    AccountIcon(account, size: Theme.Size.iconInline)
                    Text(account.name).font(.system(size: 12.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MoneyField(value: Binding(
                    get: { account.amountInvested },
                    set: { account.amountInvested = max(0, $0); try? context.save() }))

                DerivedText(text: Money.currency(holding.value), width: Theme.Size.field)
                DerivedText(text: signed(holding.profit), width: Theme.Size.field,
                            tint: tint(holding.profit))
                DerivedText(text: Money.percent(holding.returnRate),
                            width: Theme.Size.fieldSmall,
                            tint: holding.returnRate.map(tint) ?? nil)
                DerivedText(text: Money.percent(holding.annualisedReturn),
                            width: Theme.Size.fieldSmall,
                            tint: holding.annualisedReturn.map(tint) ?? nil)
                DerivedText(text: Money.percent(holding.share),
                            width: Theme.Size.fieldSmall)
            }
            .padding(.vertical, 5)
            .contextMenu {
                Button("Stop tracking this account") {
                    account.investmentTracking = .excluded
                    try? context.save()
                }
            }
        }
    }

    private func signed(_ value: Double) -> String {
        value > 0 ? "+" + Money.currency(value) : Money.currency(value)
    }

    private func tint(_ value: Double) -> Color? {
        value == 0 ? nil : (value > 0 ? .ftPositive : .ftNegative)
    }

    // MARK: - Value over time

    private var valueChart: some View {
        CardSection("Tracked value over time",
                    subtitle: "Combined balance of your investments, against what you have put in") {
            Chart {
                ForEach(derived) { row in
                    let value = trackedAccounts.reduce(0) { $0 + row.amount(for: $1.id) }
                    AreaMark(x: .value("Date", row.date), y: .value("Value", value))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.ftAccent.opacity(0.22), Color.ftAccent.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                }
                ForEach(derived) { row in
                    let value = trackedAccounts.reduce(0) { $0 + row.amount(for: $1.id) }
                    LineMark(x: .value("Date", row.date), y: .value("Value", value))
                        .foregroundStyle(Color.ftAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
                if metrics.totalInvested > 0 {
                    RuleMark(y: .value("Invested", metrics.totalInvested))
                        .foregroundStyle(Color.ftInkTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Invested \(Money.currency(metrics.totalInvested))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.ftInkTertiary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.ftHairline)
                    AxisValueLabel().font(.system(size: 10))
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
