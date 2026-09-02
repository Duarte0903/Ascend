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
    /// Which account's interest schedule is open for editing, if any.
    @State private var editingSchedule: UUID?
    @State private var hoveredSchedule: UUID?

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
                                         target: settings.investmentReturnTarget,
                                         interestTaxRate: settings.investmentTaxRate)
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
                if !metrics.holdings.isEmpty { forecastTable }
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

    /// What each holding is expected to become, account by account. Separate
    /// from Holdings above deliberately: that table is recorded history, this
    /// one is entirely assumption, and mixing the two invites reading a guess
    /// as a fact.
    private var forecastTable: some View {
        CardSection("Projected value",
                    subtitle: "Counted forward from today, after tax. Money you pay in is shown, but never counted as earned.") {
            HStack(spacing: 6) {
                Text("Tax on interest")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                MoneyField(value: Binding(
                    get: { settings.investmentTaxRate * 100 },
                    set: {
                        settings.investmentTaxRate = min(max(0, $0), 100) / 100
                        try? context.save()
                    }),
                    decimals: 2, width: Theme.Size.fieldSmall, suffix: "%")
            }
            .help("Charged on interest as it is credited. Gains taxed only when you sell are left alone — that bill depends on when you sell, not on the year passing.")
        } content: {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                GridRow {
                    Text("Account").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Return").frame(width: Theme.Size.fieldSmall, alignment: .trailing)
                    Text("Interest").frame(width: Theme.Size.picker, alignment: .leading)
                    Text("Next payment").frame(width: Theme.Size.name, alignment: .trailing)
                    horizonHeader("Value in 1 year", months: 12)
                    horizonHeader("Value in 5 years", months: 60)
                }
                .font(.tableHeader)
                .tracking(Theme.tableHeaderTracking)
                .foregroundStyle(Color.ftInkSecondary)
                .padding(.bottom, 8)

                Divider()

                ForEach(metrics.holdings) { holding in
                    GridRow {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: holding.colorHex))
                                .frame(width: Theme.Size.dot, height: Theme.Size.dot)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(holding.name).font(.system(size: 13))
                                // Named next to the account, because it is what
                                // makes two accounts on the same rate project so
                                // differently — and it is set on another screen.
                                if holding.monthlyContribution > 0 {
                                    Text("\(Money.currency(holding.monthlyContribution))/mo in")
                                        .font(.system(size: 10.5))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.ftInkTertiary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(holding.monthlyContribution > 0
                              ? "Set on the Accounts screen. It is money you add, not return — the projections separate the two."
                              : "Nothing is paid into this account, so its projection is growth alone.")

                        returnField(holding)
                            .frame(width: Theme.Size.fieldSmall, alignment: .trailing)

                        frequencyPicker(holding)
                            .frame(width: Theme.Size.picker, alignment: .leading)

                        nextPaymentCell(holding)
                            .frame(width: Theme.Size.name, alignment: .trailing)

                        projectionCell(holding, months: 12)
                        projectionCell(holding, months: 60, emphasised: true)
                    }
                    .padding(.vertical, 9)

                    if holding.id != metrics.holdings.last?.id {
                        Divider().opacity(0.6)
                    }
                }

                Divider()

                GridRow {
                    Text("Total").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("").frame(width: Theme.Size.fieldSmall)
                    Text("").frame(width: Theme.Size.picker)
                    Text("").frame(width: Theme.Size.name)
                    totalCell(months: 12)
                    totalCell(months: 60)
                }

            }
        }
    }

    /// Says what the column is and when it lands.
    ///
    /// "1 year" alone reads as "by the end of this year", which in September is
    /// four months away, not twelve — so the date it actually reaches is part
    /// of the heading rather than something to work out.
    private func horizonHeader(_ title: String, months: Int) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title)
            Text(horizonDate(months: months))
                .textCase(nil)
                .foregroundStyle(Color.ftInkTertiary)
        }
        .frame(width: Theme.Size.field, alignment: .trailing)
    }

    /// Says what is in the figure: the horizon, what you pay in, and whether
    /// tax has been taken — which depends on how the account is taxed.
    private func projectionHelp(_ holding: InvestmentHolding, months: Int) -> String {
        var parts = ["Over \(months) months, to \(horizonDate(months: months))."]
        if holding.contributions(overMonths: months) > 0 {
            parts.append("Includes \(Money.currency(holding.contributions(overMonths: months))) you would pay in.")
        }
        parts.append(holding.appliedTaxRate > 0
                     ? "Net of \(Money.percent(holding.appliedTaxRate)) tax on interest."
                     : "Untaxed here — gains on this account are taxed when you sell.")
        return parts.joined(separator: " ")
    }

    private func horizonDate(months: Int) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .month, value: months, to: Date()) ?? Date()
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    /// The projected value, with what it actually earns underneath.
    ///
    /// Without the second line an account you pay into looks like it earns more
    /// than one you don't: most of the figure is your own money arriving, and
    /// two accounts on the same rate read as wildly different.
    private func projectionCell(_ holding: InvestmentHolding, months: Int,
                                emphasised: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            // Profit leads: it is the figure that makes two accounts on the
            // same rate comparable. The value it grows into is the supporting
            // detail, not the headline.
            Text(Money.currency(holding.growth(overMonths: months), decimals: 2))
                .font(.figure(13, weight: emphasised ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(holding.growth(overMonths: months) > 0
                                 ? Color.ftPositive : Color.ftInkSecondary)
            Text("worth \(Money.currency(holding.projectedValue(months: months)))")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Color.ftInkTertiary)
        }
        .frame(width: Theme.Size.field, alignment: .trailing)
        .help(projectionHelp(holding, months: months))
    }

    /// The stored account behind a holding, so the assumptions can be edited
    /// where their effect is visible.
    private func account(for holding: InvestmentHolding) -> Account? {
        accounts.first { $0.id == holding.accountID }
    }

    private func returnField(_ holding: InvestmentHolding) -> some View {
        Group {
            if let account = account(for: holding) {
                MoneyField(value: Binding(
                    get: { account.expectedAnnualReturn * 100 },
                    set: { account.expectedAnnualReturn = $0 / 100; try? context.save() }),
                    decimals: 2, width: Theme.Size.fieldSmall, suffix: "%")
            }
        }
    }

    private func frequencyPicker(_ holding: InvestmentHolding) -> some View {
        Group {
            if let account = account(for: holding) {
                // Boxed like the fields beside it: the card promises that
                // boxed cells are yours to set, and a bare label with a chevron
                // reads as a caption rather than a control.
                let shape = RoundedRectangle(cornerRadius: Theme.fieldRadius,
                                             style: .continuous)
                let open = editingSchedule == account.id
                let hovering = hoveredSchedule == account.id
                Button {
                    editingSchedule = account.id
                } label: {
                    HStack(spacing: 5) {
                        Text(account.interestFrequency.isScheduled
                             ? account.interestFrequency.label
                             : "Not scheduled")
                            .font(.system(size: 12))
                            .foregroundStyle(account.interestFrequency.isScheduled
                                             ? Color.ftInk : Color.ftInkTertiary)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                    .padding(.horizontal, Theme.Size.fieldPaddingH)
                    .padding(.vertical, Theme.Size.fieldPaddingV)
                    .background(Color.ftSurface, in: shape)
                    .overlay(shape.strokeBorder(
                        open ? Color.ftAccent
                             : (hovering ? Color.ftInkTertiary : Color.ftHairlineStrong),
                        lineWidth: open ? 1.5 : 1))
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoveredSchedule = account.id }
                    else if hoveredSchedule == account.id { hoveredSchedule = nil }
                }
                .animation(.easeOut(duration: 0.13), value: hovering)
                .help("Set how often interest is credited")
                .popover(isPresented: Binding(
                    get: { editingSchedule == account.id },
                    set: { if !$0 && editingSchedule == account.id { editingSchedule = nil } }),
                         arrowEdge: .bottom) {
                    scheduleEditor(account, holding: holding)
                }
            }
        }
    }

    /// The three settings that make a schedule, laid out with room to breathe
    /// rather than stacked into a table cell.
    private func scheduleEditor(_ account: Account,
                                holding: InvestmentHolding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Interest schedule")
                    .font(.system(size: 13, weight: .semibold))
                Text(account.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ftInkTertiary)
            }

            Picker("How often", selection: Binding(
                get: { account.interestFrequency },
                set: { AccountService.setInterestSchedule($0, on: account, in: context) })) {
                ForEach(InterestFrequency.presets) { Text($0.label).tag($0) }
                Divider()
                Text("Another interval…").tag(customTag(for: account))
            }
            .controlSize(.small)

            if account.interestFrequency.isCustom {
                HStack(spacing: 6) {
                    Text("Every").font(.system(size: 12))
                    IntField(value: Binding(
                        get: { account.interestFrequency.monthsBetween ?? 2 },
                        set: {
                            AccountService.setInterestSchedule(.everyMonths($0),
                                                               on: account, in: context)
                        }),
                        range: InterestFrequency.customRange, width: Theme.Size.fieldSmall)
                    Text("months").font(.system(size: 12))
                }
            }

            if account.interestFrequency.isScheduled {
                HStack(spacing: 6) {
                    Text("On day").font(.system(size: 12))
                    IntField(value: Binding(
                        get: { AccountService.interestDay(of: account) },
                        set: { AccountService.setInterestDay($0, on: account, in: context) }),
                        range: 1...31, width: Theme.Size.fieldSmall)
                    Text("of the month").font(.system(size: 12))
                }

                Divider()

                // The consequence, right where it is being set.
                if let next = holding.nextInterest(after: Date()) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next payment \(next.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ftInkSecondary)
                        if let amount = holding.netInterestPerPayment {
                            Text("\(Money.currency(amount, decimals: 2)) a payment, after tax")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ftInkTertiary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { editingSchedule = nil }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 268)
    }

    /// The tag behind the custom entry: the account's own interval when it has
    /// a custom one, and a sensible starting point otherwise.
    private func customTag(for account: Account) -> InterestFrequency {
        account.interestFrequency.isCustom ? account.interestFrequency : .everyMonths(2)
    }

    /// When the next payment falls, and what it is worth. Both are worked out
    /// from the frequency — there is nothing to type, and a date you could edit
    /// would be a second way of saying what the frequency already says.
    private func nextPaymentCell(_ holding: InvestmentHolding) -> some View {
        Group {
            if holding.interestFrequency.isScheduled,
               let next = holding.nextInterest(after: Date()) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(next.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.ftInk)
                    if let amount = holding.netInterestPerPayment {
                        Text(Money.currency(amount, decimals: 2))
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                }
                .help("Counted forward from when you set the schedule.")
            } else {
                Text(Money.dash)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ftInkTertiary)
            }
        }
    }

    private func projectedTotal(months: Int) -> Double {
        metrics.holdings.reduce(0) { $0 + $1.projectedValue(months: months) }
    }

    private func totalGrowth(months: Int) -> Double {
        metrics.holdings.reduce(0) { $0 + $1.growth(overMonths: months) }
    }

    private func totalCell(months: Int) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(Money.currency(totalGrowth(months: months), decimals: 2))
                .font(.figure(13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Color.ftPositive)
            Text("worth \(Money.currency(projectedTotal(months: months)))")
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(Color.ftInkTertiary)
        }
        .frame(width: Theme.Size.field, alignment: .trailing)
    }

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
