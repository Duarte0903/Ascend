import SwiftUI
import SwiftData
import Charts

/// Portuguese personal income tax on a salary: what the year costs and what is
/// left, feeding the net figure Projections runs on.
struct TaxView: View {
    @Environment(\.modelContext) private var context
    /// The screen reads settings and nothing else, so this query is what makes
    /// it react at all: fetching the object by hand leaves SwiftUI with no
    /// dependency to notice, and every figure stays as it was until the screen
    /// is left and re-entered.
    @Query private var storedSettings: [AppSettings]

    @State private var editingClaimedYears = false
    @State private var editingBrackets = false
    @State private var showingBandWorking = false
    @State private var editingWithholdingRate = false
    @State private var showingGlossary = false

    /// The stored table as something the bracket editor can write back to.
    private var tableBinding: Binding<TaxYear> {
        Binding(get: { table }, set: { settings.taxTable = $0; save() })
    }

    private var settings: AppSettings {
        storedSettings.first ?? SeedData.settings(in: context)
    }
    private var table: TaxYear { settings.taxTable }

    private var assessment: TaxAssessment {
        TaxEngine.assess(settings.taxInput
                         ?? TaxInput(grossAnnual: settings.salaryExcludingMealAllowance,
                                     region: settings.taxRegion,
                                     dependents: settings.taxDependents,
                                     jointTaxation: settings.taxJointAssessment,
                                     youngTaxpayerYear: settings.taxYoungTaxpayerYear > 0
                                         ? settings.taxYoungTaxpayerYear : nil,
                                     otherCredits: settings.taxOtherCredits,
                                     mealAllowancePerDay: settings.mealAllowancePerDay,
                                     mealAllowanceDaysPerYear:
                                        Double(settings.mealAllowanceDaysPerYear),
                                     mealAllowanceOnCard: settings.mealAllowanceOnCard,
                                     mealAllowanceSpendable: settings.mealAllowanceSpendable,
                                     withholdingAtSource: settings.taxWithholdingAtSource,
                                     withholdingRate: settings.taxWithholdingRate,
                                     table: table))
    }

    private var mealCost: (amount: Double, shareOfAllowance: Double, shareOfExcess: Double) {
        TaxEngine.mealAllowanceCost(settings.taxInput
                                    ?? TaxInput(grossAnnual: settings.grossAnnualIncome,
                                                mealAllowancePerDay: settings.mealAllowancePerDay,
                                                mealAllowanceDaysPerYear:
                                                    Double(settings.mealAllowanceDaysPerYear),
                                                mealAllowanceOnCard: settings.mealAllowanceOnCard,
                                                table: table))
    }

    var body: some View {
        FillingScreen {
            Callout(text: "An estimate, not a tax return. Withholding through the year and the final assessment differ, and the minimum-income floor and less common reliefs aren't modelled. Check the rates below against the State Budget for your year.",
                    systemImage: "info.circle.fill")

            summary

            HStack(alignment: .top, spacing: Theme.gap) {
                situation
                breakdown
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: Theme.gap) {
                bands
                split
            }
            .fixedSize(horizontal: false, vertical: true)
            rateTable.fillsHeight(minimum: 200)
        }
        .toolbar {
            Button("What everything means", systemImage: "info.circle") {
                showingGlossary = true
            }
            .help("Explains every figure on this screen")
            // A sheet, not a popover: a toolbar popover is capped to what fits
            // below the button, and this is longer than that — it came out
            // clipped mid-sentence with nowhere to scroll.
            .sheet(isPresented: $showingGlossary) {
                TaxGlossary(isPresented: $showingGlossary)
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: Theme.gap) {
            MetricTile(title: "Net per month",
                       value: Money.currency(assessment.budgetMonthlyIncome),
                       caption: spendableCaption)
            MetricTile(title: "Effective rate", value: Money.percent(assessment.effectiveRate),
                       caption: "Tax and social security, over gross")
            MetricTile(title: "Marginal rate", value: Money.percent(assessment.marginalRate),
                       caption: "What the next euro costs")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Inputs

    private var situation: some View {
        CardSection("Your situation", subtitle: "What the estimate is based on") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 11) {
                row("Gross pay a year") {
                    VStack(alignment: .leading, spacing: 3) {
                        MoneyField(value: Binding(
                            get: { settings.grossAnnualIncome },
                            set: { settings.grossAnnualIncome = max(0, $0); save() }),
                                   decimals: 2, width: Theme.Size.picker, suffix: Money.symbol)
                        Text(grossPaySplit)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                row("Region") {
                    Picker("", selection: Binding(
                        get: { settings.taxRegion },
                        set: { settings.taxRegion = $0; save() })) {
                        ForEach(TaxRegion.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: Theme.Size.picker)
                }
                Divider()
                row("Dependents") {
                    IntField(value: Binding(
                        get: { settings.taxDependents },
                        set: { settings.taxDependents = max(0, $0); save() }),
                             range: 0...20, width: Theme.Size.fieldSmall)
                }
                Divider()
                row("Assessed jointly") {
                    Toggle("", isOn: Binding(
                        get: { settings.taxJointAssessment },
                        set: { settings.taxJointAssessment = $0; save() }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                Divider()
                row("IRS Jovem") {
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle("", isOn: Binding(
                            get: { settings.taxYoungTaxpayerEnabled },
                            set: { settings.taxYoungTaxpayerEnabled = $0; save() }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)

                        if settings.taxYoungTaxpayerEnabled {
                            HStack(spacing: 8) {
                                Text("Started in")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.ftInkTertiary)
                                IntField(value: Binding(
                                    get: { settings.taxYoungTaxpayerFirstYear },
                                    set: { settings.taxYoungTaxpayerFirstYear = $0; save() }),
                                         range: 2_000...2_100, width: Theme.Size.picker)
                            }
                            Text(youngYearCaption)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ftInkTertiary)
                                .fixedSize(horizontal: false, vertical: true)

                            if reliefArrivesAsRefund {
                                Text("Your employer withholds a flat \(Money.percent(settings.taxWithholdingRate)) whatever relief applies, so this shows up as a bigger refund rather than in your monthly figure.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            // Skipping a year is rare, so a decade of buttons
                            // stays folded away instead of being on screen for
                            // everyone.
                            if editingClaimedYears {
                                youngYearChips
                                Text("Click a year you didn't claim it in — it uses none of the ten and pushes the last one out.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.ftInkTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button(editingClaimedYears ? "Done" : claimedYearsLabel) {
                                editingClaimedYears.toggle()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        } else {
                            EmptyView()
                        }
                    }
                }
                row("Withholding") {
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle("", isOn: Binding(
                            get: { settings.taxWithholdingAtSource },
                            set: { settings.taxWithholdingAtSource = $0; save() }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)

                        Text(settings.taxWithholdingAtSource
                             ? "The tax is taken monthly, before the money reaches your account, so what arrives is already net of it."
                             : "Nothing is taken monthly — the whole year's tax falls due after the annual return.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        if settings.taxWithholdingAtSource {
                            if editingWithholdingRate {
                                HStack(spacing: 8) {
                                    MoneyField(value: Binding(
                                        get: { settings.taxWithholdingRate * 100 },
                                        set: {
                                            settings.taxWithholdingRate =
                                                min(max(0, $0), 100) / 100
                                            save()
                                        }),
                                               decimals: 2, width: Theme.Size.fieldSmall,
                                               suffix: "%")
                                    Text("0 assumes it matches the tax exactly")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.ftInkTertiary)
                                }
                            }
                            Button(editingWithholdingRate ? "Done" : withholdingRateLabel) {
                                editingWithholdingRate.toggle()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                }
                Divider()
                row("Meal allowance a day") {
                    VStack(alignment: .leading, spacing: 3) {
                        MoneyField(value: Binding(
                            get: { settings.mealAllowancePerDay },
                            set: { settings.mealAllowancePerDay = max(0, $0); save() }),
                                   decimals: 2, width: Theme.Size.picker, suffix: Money.symbol)
                        Text("The gross daily rate from your payslip, before any deduction — what is exempt is worked out below.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                row("Paid onto a card") {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("", isOn: Binding(
                            get: { settings.mealAllowanceOnCard },
                            set: { settings.mealAllowanceOnCard = $0; save() }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Text(allowanceHeadroom)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                row("Vacation days") {
                    HStack(spacing: 8) {
                        IntField(value: Binding(
                            get: { settings.mealAllowanceVacationDays },
                            set: { settings.mealAllowanceVacationDays = max(0, $0); save() }),
                                 range: 0...60, width: Theme.Size.fieldSmall)
                        Text("plus").font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                        IntField(value: Binding(
                            get: { settings.mealAllowanceExtraHolidays },
                            set: { settings.mealAllowanceExtraHolidays = max(0, $0); save() }),
                                 range: 0...10, width: Theme.Size.fieldSmall)
                        Text("municipal holidays").font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                }
                Divider()
                row("Days paid") {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            DerivedText(text: "\(settings.mealAllowanceDaysPerYear)",
                                        width: Theme.Size.fieldSmall)
                            Text("= \(Money.currency(assessment.mealAllowanceGross / 12)) a month")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ftInkTertiary)
                        }
                        Text(daysCaption)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                row("Pin days paid") {
                    VStack(alignment: .leading, spacing: 3) {
                        IntField(value: Binding(
                            get: { settings.mealAllowanceDaysOverride },
                            set: { settings.mealAllowanceDaysOverride = max(0, $0); save() }),
                                 range: 0...366, width: Theme.Size.fieldSmall)
                    }
                }
                Divider()
                row("Allowance is spendable") {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("", isOn: Binding(
                            get: { settings.mealAllowanceSpendable },
                            set: { settings.mealAllowanceSpendable = $0; save() }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                Divider()
                row("Other deductions") {
                    MoneyField(value: Binding(
                        get: { settings.taxOtherCredits },
                        set: { settings.taxOtherCredits = max(0, $0); save() }),
                               decimals: 2, width: Theme.Size.picker, suffix: Money.symbol)
                }
                Divider()
                row("Drives Projections") {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("", isOn: Binding(
                            get: { settings.taxEnabled },
                            set: { settings.taxEnabled = $0; save() }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        // Names the figure that gets sent, so the switch says
                        // what it does rather than only that it is on.
                        Text(projectionsHandoff)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .fillingHeight()
    }

    /// What this screen hands to Projections: one figure, already spendable
    /// and already on the right basis. Projections does not choose between
    /// them — it is sent the one that matters.
    private var projectionsHandoff: String {
        guard settings.taxEnabled else {
            return "Projections is using its own typed figure instead."
        }
        guard settings.grossAnnualIncome > 0 else {
            return "Set a gross salary above and Projections will use what is left of it."
        }
        return "Projections uses \(Money.currency(assessment.budgetMonthlyIncome)) a month — what is left after tax and social security, with anything that cannot be spent freely held back."
    }

    /// A flat withholding rate is charged whether or not relief applies, so
    /// the relief cannot reach the monthly figure — it comes back at the annual
    /// return instead. Worth saying, because the monthly number looks
    /// unchanged by a switch that plainly did something.
    private var reliefArrivesAsRefund: Bool {
        settings.taxWithholdingAtSource
            && settings.taxWithholdingRate > 0
            && assessment.exemptIncome > 0
    }

    /// The rate is optional detail: it only sharpens the monthly figure and
    /// tells you whether a refund is coming.
    private var withholdingRateLabel: String {
        settings.taxWithholdingRate > 0
            ? "Rate: \(Money.percent(settings.taxWithholdingRate))"
            : "Know the rate from your payslip?"
    }

    /// Red is reserved for money that actually leaves you.
    private func amountColor(_ amount: Double, relief: Bool) -> Color {
        if relief { return Color.ftInkSecondary }
        if abs(amount) < 0.005 { return Color.ftInk }
        return amount < 0 ? Color.ftNegative : Color.ftInk
    }

    /// Shows what the entered figure breaks into, so it is clear the salary
    /// the tax runs on is worked out rather than asked for a second time.
    private var grossPaySplit: String {
        let entered = settings.grossAnnualIncome
        guard entered > 0 else { return "Food allowance included." }
        let meal = settings.mealAllowanceAnnual
        guard meal > 0 else { return "No food allowance set, so all of it is salary." }
        return "\(Money.currency(meal)) allowance, \(Money.currency(settings.salaryExcludingMealAllowance)) salary."
    }

    /// The index sets two things, and it is the only figure behind either.
    private var indexCaption: String {
        var uses = ["the specific deduction"]
        if settings.taxYoungTaxpayerEnabled {
            uses.append("the IRS Jovem cap, at \(Money.currency(table.youngExemptionCapMultiple, decimals: 0))× this")
        }
        return "Published each year. It sets " + uses.joined(separator: " and ") + "."
    }

    /// States the effect rather than the rule: the rule is only interesting
    /// once you already know what the allowance does.
    private var specificDeductionBasis: String {
        assessment.specificDeduction > table.specificDeduction + 0.005
            ? "not taxed — your contributions, being larger than the flat allowance"
            : "not taxed, whatever you earn — applied when you file, never on a payslip"
    }

    /// Where the rate sits against the limit, which is what the toggle
    /// actually decides. The limit itself is edited in the rate table.
    private var allowanceHeadroom: String {
        let limit = table.mealAllowanceLimit(onCard: settings.mealAllowanceOnCard)
        let rate = settings.mealAllowancePerDay
        guard rate > 0 else {
            return "Exempt up to \(Money.currency(limit, decimals: 2)) a day."
        }
        if rate > limit {
            return "\(Money.currency(rate - limit, decimals: 2)) a day above the limit is taxed as salary."
        }
        let spare = limit - rate
        return spare < 0.005
            ? "Exactly at the limit — wholly exempt, with no room to spare."
            : "Wholly exempt, with \(Money.currency(spare, decimals: 2)) a day to spare."
    }

    /// Spells out both ways of reading the cost, because a payslip may show
    /// either: the bite out of the whole allowance, or the rate on the part
    /// that is actually taxable.
    private var mealCostDetail: String {
        guard mealCost.amount > 0 else { return "wholly exempt" }
        return "\(Money.percent(mealCost.shareOfAllowance)) of the allowance · "
            + "\(Money.percent(mealCost.shareOfExcess)) of the taxed part"
    }

    /// Shows the sum, so the number is explicable rather than asserted.
    private var daysCaption: String {
        guard settings.mealAllowanceDaysOverride <= 0 else {
            return "Pinned — the calendar for \(table.year) is not being used."
        }
        let weekdays = WorkingCalendar.weekdays(inYear: table.year)
        let holidays = WorkingCalendar.holidaysOnWeekdays(inYear: table.year)
        return "\(table.year): \(weekdays) weekdays − \(holidays) national holidays on weekdays − \(settings.mealAllowanceVacationDays) vacation − \(settings.mealAllowanceExtraHolidays) municipal."
    }

    private var spendableCaption: String {
        let basis = settings.taxWithholdingAtSource
            ? "After tax and social security" : "Tax not yet taken"
        guard assessment.mealAllowanceGross > 0 else {
            return "\(basis), the year over twelve"
        }
        return settings.mealAllowanceSpendable
            ? "\(basis), food allowance included"
            : "\(basis), without the food allowance"
    }

    /// Names the disclosure after what it holds, and says when something is
    /// already set behind it.
    private var claimedYearsLabel: String {
        let skipped = settings.taxYoungTaxpayerSkipped.count
        guard skipped > 0 else { return "Skipped a year?" }
        return skipped == 1 ? "1 year not claimed" : "\(skipped) years not claimed"
    }

    /// One chip per fiscal year the scheme touches, filled when it was
    /// claimed. Clicking one marks it unclaimed, which moves everything after
    /// it along by a year.
    private var youngYearChips: some View {
        let first = settings.taxYoungTaxpayerFirstYear
        let skipped = settings.taxYoungTaxpayerSkipped
        let years = table.youngTaxpayerYears(startingIn: first, skipping: skipped)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 5,
                                            alignment: .leading)],
                         alignment: .leading, spacing: 5) {
            ForEach(years, id: \.self) { year in
                yearChip(year, claimed: !skipped.contains(year))
            }
        }
        .frame(maxWidth: Theme.Size.detailValue, alignment: .leading)
    }

    private func yearChip(_ year: Int, claimed: Bool) -> some View {
        let isThisYear = year == table.year
        return Button {
            settings.toggleYoungTaxpayerYearClaimed(year)
            save()
        } label: {
            // String(year) rather than interpolation: a year is a label, and
            // the number formatter would put a thousands separator in it.
            Text(String(year))
                .font(.system(size: 11, weight: isThisYear ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(claimed ? Color.white : Color.ftInkTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(claimed ? Color.ftAccent : Color.ftSurfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    isThisYear ? Color.ftInk.opacity(0.5)
                               : (claimed ? .clear : Color.ftHairline),
                    lineWidth: isThisYear ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .help(chipHelp(year, claimed: claimed))
    }

    private func chipHelp(_ year: Int, claimed: Bool) -> String {
        guard claimed else { return "\(year): not claimed — uses none of the scheme" }
        var probe = table
        probe.year = year
        guard let index = probe.youngTaxpayerYear(
            startingIn: settings.taxYoungTaxpayerFirstYear,
            skipping: settings.taxYoungTaxpayerSkipped) else { return String(year) }
        return "\(year): year \(index) — \(Money.percent(table.youngExemptionShares[index - 1])) exempt"
    }

    /// Says where in the taper the tax year falls, or why it is not in it.
    private var youngYearCaption: String {
        let first = settings.taxYoungTaxpayerFirstYear
        let skipped = settings.taxYoungTaxpayerSkipped
        let length = table.youngExemptionShares.count
        let final = table.youngTaxpayerFinalYear(startingIn: first, skipping: skipped)
        guard let year = settings.taxYoungTaxpayerSchemeYear else {
            if first > table.year { return "Starts in \(first) — nothing exempt in \(table.year)." }
            if skipped.contains(table.year) {
                return "\(table.year) is marked as not claimed, so nothing is exempt in it."
            }
            return "The \(length) claimed years ended after \(final)."
        }
        let share = Money.percent(table.youngExemptionShares[year - 1])
        let cap = table.youngExemptionCapMultiple * table.socialSupportIndex
        let tail = skipped.isEmpty ? "" : " Last claim falls in \(final)."
        return "\(table.year) is year \(year) of \(length): \(share) exempt, capped at \(Money.currency(cap)).\(tail)"
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        CardSection("This year",
                    subtitle: "The annual assessment — your payslip shows monthly withholding instead, so its lines differ") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 11) {
                amountRow("Gross salary", assessment.grossAnnual)
                if assessment.mealAllowanceGross > 0 {
                    Divider()
                    amountRow("Meal allowance", assessment.mealAllowanceGross,
                              detail: "\(Money.currency(settings.mealAllowancePerDay, decimals: 2)) a day")
                    Divider()
                    amountRow("— exempt", assessment.mealAllowanceExempt)
                    Divider()
                    amountRow("— taxed as salary", assessment.mealAllowanceTaxable)
                    Divider()
                    amountRow("— costs you", -mealCost.amount, detail: mealCostDetail)
                    Divider()
                    amountRow("Total gross", assessment.totalGrossAnnual,
                              detail: "what you are paid", emphasised: true)
                }
                Divider()
                amountRow("Social security", -assessment.socialSecurity,
                          detail: Money.percent(table.socialSecurityRate))
                if assessment.exemptIncome > 0 {
                    Divider()
                    amountRow("IRS Jovem exemption", -assessment.exemptIncome,
                              detail: "not taxed — this is relief, not a cost",
                              relief: true)
                }
                Divider()
                amountRow("Specific deduction", -assessment.specificDeduction,
                          detail: specificDeductionBasis, relief: true)
                Divider()
                amountRow("Taxable income", assessment.taxableIncome,
                          detail: "what the bands are applied to", emphasised: true)
                Divider()
                amountRow("IRS", -assessment.taxBeforeCredits)
                if assessment.solidaritySurcharge > 0 {
                    Divider()
                    amountRow("Solidarity surcharge", -assessment.solidaritySurcharge)
                }
                if assessment.credits > 0 {
                    Divider()
                    amountRow("Deductions to collection", assessment.credits, relief: true)
                }
                Divider()
                amountRow("Tax due", -assessment.taxDue, emphasised: true)
                if settings.taxWithholdingAtSource {
                    Divider()
                    amountRow("Withheld at source", -assessment.withheldAnnual,
                              detail: settings.taxWithholdingRate > 0
                                  ? Money.percent(settings.taxWithholdingRate)
                                  : "monthly, against the year's tax")
                    Divider()
                    amountRow(assessment.withholdingBalance >= 0
                              ? "Refund expected" : "Still to pay",
                              assessment.withholdingBalance,
                              detail: "after the annual return", emphasised: true)
                }
                Divider()
                amountRow("Net for the year", assessment.netAnnual, emphasised: true)
                if abs(assessment.withholdingBalance) > 0.005 {
                    Divider()
                    amountRow("Reaches you this year", assessment.takeHomeAnnual,
                              detail: assessment.withholdingBalance > 0
                                  ? "before the refund" : "before the balance falls due")
                }
                Divider()
                amountRow("Per salary payment", assessment.netPerPayment,
                          detail: "\(table.paymentsPerYear) a year")
                if assessment.mealAllowanceGross > 0 {
                    Divider()
                    amountRow("Spendable for the year", assessment.budgetAnnualIncome,
                              detail: settings.mealAllowanceSpendable
                                  ? "allowance included" : "allowance excluded",
                              emphasised: true)
                }
            }
        }
        .fillingHeight()
    }

    // MARK: - Bands

    private var bands: some View {
        CardSection("Your tax band",
                    subtitle: "Where your taxable income stops on the scale") {
            if assessment.slices.isEmpty {
                emptyBands
            } else {
                currentBand
                // The slice-by-slice working is folded away: it is how the
                // figure is arrived at, not the figure itself.
                Button(showingBandWorking ? "Hide the working" : "Show the working") {
                    showingBandWorking.toggle()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))

                if showingBandWorking {
                Divider().padding(.vertical, 2)
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        header("Band")
                        header("Rate")
                        header("Taxed")
                        header("Tax")
                    }
                    Divider()
                    ForEach(Array(assessment.slices.enumerated()), id: \.offset) { index, slice in
                        // The band the income stops in is the one people mean
                        // when they ask which band they are in.
                        let isCurrent = index == assessment.slices.count - 1
                        GridRow {
                            HStack(spacing: 6) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(isCurrent ? Color.white : Color.ftInkTertiary)
                                    .frame(width: 17, height: 17)
                                    .background(isCurrent ? Color.ftAccent : Color.ftSurfaceAlt,
                                                in: Circle())
                                Text(bandLabel(slice))
                                    .font(.system(size: 12.5,
                                                  weight: isCurrent ? .semibold : .regular))
                            }
                            .gridColumnAlignment(.leading)
                            Text(Money.percent(slice.rate))
                                .font(.system(size: 12.5,
                                              weight: isCurrent ? .semibold : .regular))
                                .monospacedDigit()
                            Text(Money.currency(slice.amountTaxed))
                                .font(.system(size: 12.5)).monospacedDigit()
                                .foregroundStyle(Color.ftInkSecondary)
                            Text(Money.currency(slice.tax))
                                .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        }
                    }
                }
                }
            }
        }
        .fillingHeight()
    }

    /// Answers "which band am I in" outright, rather than leaving it to be
    /// read off the table. The table below is then the working, not the answer.
    private var currentBand: some View {
        let position = assessment.slices.count
        let total = table.brackets.count
        let rate = assessment.slices.last?.rate ?? 0
        return HStack(alignment: .top, spacing: 10) {
            Text("\(position)")
                .font(.figure(19))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(Color.ftAccent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("You are in band \(position) of \(total)")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(Money.percent(rate)) on the next euro earned, \(Money.percent(averageOnTaxable)) across the \(Money.currency(assessment.taxableIncome)) that is taxable — \(Money.currency(assessment.slices.reduce(0) { $0 + $1.tax })) in all.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// The taxa média: what the whole taxable income works out at once every
    /// band has taken its slice.
    private var averageOnTaxable: Double {
        guard assessment.taxableIncome > 0 else { return 0 }
        return assessment.slices.reduce(0) { $0 + $1.tax } / assessment.taxableIncome
    }

    /// An empty scale is a result, not a blank. It always has a cause, and
    /// naming it is the difference between "nothing here" and "nothing is
    /// taxed, and this is why".
    private var emptyBands: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: emptyBandsIcon)
                .font(.system(size: 15))
                .foregroundStyle(settings.grossAnnualIncome > 0
                                 ? Color.ftPositive : Color.ftInkTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(emptyBandsTitle)
                    .font(.system(size: 13, weight: .medium))
                Text(emptyBandsReason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var emptyBandsIcon: String {
        settings.grossAnnualIncome > 0 ? "checkmark.seal.fill" : "arrow.up.circle"
    }

    private var emptyBandsTitle: String {
        settings.grossAnnualIncome > 0 ? "No IRS to pay this year" : "Nothing to show yet"
    }

    private var emptyBandsReason: String {
        guard settings.grossAnnualIncome > 0 else {
            return "Enter your gross salary above and the bands will show what each slice of it costs."
        }
        if assessment.exemptIncome > 0,
           let year = settings.taxYoungTaxpayerSchemeYear {
            let share = Money.percent(table.youngExemptionShares[year - 1])
            return "IRS Jovem exempts \(share) of your salary in \(table.year) — year \(year) of the scheme — which leaves nothing for the bands to tax. Social security is still charged."
        }
        return "Your salary is below the deductions taken off before the scale, so no slice of it reaches a band. Social security is still charged."
    }

    // MARK: - Where the money goes

    /// One wedge of the year's gross. Named rather than indexed, so the chart
    /// keeps a wedge's identity as the figures change under it.
    private struct GrossSlice: Identifiable {
        let name: String
        let amount: Double
        let color: Color
        var id: String { name }
    }

    /// The whole of what you are paid, split into what you keep and what is
    /// taken. The wedges add up to total gross by construction — take-home is
    /// whatever the deductions leave.
    private var grossSlices: [GrossSlice] {
        var slices: [GrossSlice] = []
        if assessment.spendableNetAnnual > 0 {
            slices.append(GrossSlice(name: "Take-home",
                                     amount: assessment.spendableNetAnnual,
                                     color: .ftPositive))
        }
        // Only its own wedge when it is held back; counted as spendable it is
        // already inside take-home.
        if !settings.mealAllowanceSpendable, assessment.mealAllowanceGross > 0 {
            slices.append(GrossSlice(name: "Meal card",
                                     amount: assessment.mealAllowanceGross,
                                     color: .ftAccent))
        }
        if assessment.socialSecurity > 0 {
            slices.append(GrossSlice(name: "Social security",
                                     amount: assessment.socialSecurity,
                                     color: Color(hex: "#C2703D")))
        }
        if assessment.withheldAnnual > 0.005 {
            slices.append(GrossSlice(name: "IRS",
                                     amount: assessment.withheldAnnual,
                                     color: .ftNegative))
        }
        return slices
    }

    private var split: some View {
        CardSection("Where your pay goes",
                    subtitle: "Every euro your employer pays, over the year") {
            if grossSlices.isEmpty || assessment.totalGrossAnnual <= 0 {
                Text("Enter your gross salary above and this will show what is kept and what is taken.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ftInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .center, spacing: 18) {
                    donut
                    legend
                    Spacer(minLength: 0)
                }
            }
        }
        .fillingHeight()
    }

    private var donut: some View {
        Chart(grossSlices) { slice in
            SectorMark(angle: .value("Amount", slice.amount),
                       innerRadius: .ratio(0.62),
                       angularInset: 1.5)
                .foregroundStyle(slice.color)
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .frame(width: 148, height: 148)
        .chartBackground { _ in
            // The hole is the obvious place for the figure the wedges divide.
            VStack(spacing: 1) {
                Text(Money.percent(keptShare))
                    .font(.figure(19))
                    .monospacedDigit()
                    .foregroundStyle(Color.ftInk)
                Text("kept")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ftInkTertiary)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(grossSlices) { slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: Theme.Size.dot, height: Theme.Size.dot)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(slice.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ftInk)
                        Text("\(Money.currency(slice.amount)) · \(Money.percent(share(of: slice)))")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                }
            }
        }
    }

    /// What reaches you, over everything you were paid. The meal card counts as
    /// taken only in the sense that it cannot be spent freely — it is drawn
    /// separately rather than lumped in with the deductions.
    private var keptShare: Double {
        guard assessment.totalGrossAnnual > 0 else { return 0 }
        return assessment.spendableNetAnnual / assessment.totalGrossAnnual
    }

    private func share(of slice: GrossSlice) -> Double {
        guard assessment.totalGrossAnnual > 0 else { return 0 }
        return slice.amount / assessment.totalGrossAnnual
    }

    private func bandLabel(_ slice: BracketSlice) -> String {
        guard let upper = slice.upperLimit else {
            return "Above \(Money.currency(slice.lowerLimit))"
        }
        return "\(Money.currency(slice.lowerLimit)) – \(Money.currency(upper))"
    }

    // MARK: - Rate table

    private var rateTable: some View {
        CardSection("Rate table",
                    subtitle: "Rates change every year. Edit them here — no rebuild needed.") {
            Button("Reset to built-in") {
                settings.taxTable = .portugalDefaults
                save()
            }
            .controlSize(.small)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 24, verticalSpacing: 11) {
                    row("Tax year") {
                        IntField(value: Binding(
                            get: { table.year },
                            set: { new in editTable { $0.year = new } }),
                                 range: 2_000...2_100, width: Theme.Size.fieldSmall)
                    }
                    Divider()
                    row("Social security") {
                        percentField(get: { table.socialSecurityRate },
                                     set: { value, year in year.socialSecurityRate = value })
                    }
                    Divider()
                    row("Specific deduction") {
                        VStack(alignment: .leading, spacing: 3) {
                            DerivedText(text: Money.currency(table.specificDeduction),
                                        width: Theme.Size.picker)
                        }
                    }
                    Divider()
                    row("Social support index (IAS)") {
                        VStack(alignment: .leading, spacing: 3) {
                            moneyField(get: { table.socialSupportIndex },
                                       set: { value, year in
                                           year.socialSupportIndex = value
                                       })
                            Text(indexCaption)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ftInkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                    row("Credit per dependent") {
                        moneyField(get: { table.creditPerDependent },
                                   set: { value, year in year.creditPerDependent = value })
                    }
                    // Only the limit that applies is offered — the other is
                    // dead weight, and two near-identical rows read as the same
                    // figure listed twice.
                    Divider()
                    row(settings.mealAllowanceOnCard
                        ? "Exempt limit, on a card" : "Exempt limit, in cash") {
                        VStack(alignment: .leading, spacing: 3) {
                            moneyField(
                                get: {
                                    table.mealAllowanceLimit(
                                        onCard: settings.mealAllowanceOnCard)
                                },
                                set: { value, year in
                                    if settings.mealAllowanceOnCard {
                                        year.mealAllowanceCardLimit = value
                                    } else {
                                        year.mealAllowanceCashLimit = value
                                    }
                                })
                        }
                    }
                    Divider()
                    row("Payments a year") {
                        IntField(value: Binding(
                            get: { table.paymentsPerYear },
                            set: { new in editTable { $0.paymentsPerYear = new } }),
                                 range: 1...14, width: Theme.Size.fieldSmall)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TAX BANDS")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.ftInkTertiary)
                        Text(bandsSummary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ftInkSecondary)
                    }
                    Spacer(minLength: 8)
                    Button("Set up bands…") { editingBrackets = true }
                        .controlSize(.small)
                        .popover(isPresented: $editingBrackets, arrowEdge: .bottom) {
                            TaxBracketEditor(isPresented: $editingBrackets,
                                             table: tableBinding)
                        }
                }
            }
        }
    }

    /// The scale at a glance, so the card says something without listing it.
    private var bandsSummary: String {
        let rates = table.brackets.map(\.rate)
        guard let low = rates.min(), let high = rates.max() else { return "No bands set" }
        let top = table.brackets.compactMap(\.upperLimit).max()
        let ceiling = top.map { "top band above \(Money.currency($0))" } ?? "one band"
        return "\(table.brackets.count) bands, \(Money.percent(low)) to \(Money.percent(high)) — \(ceiling)."
    }

    // MARK: - Editing the table

    /// Every table edit goes through here: decode, change, re-encode, save.
    private func editTable(_ change: (inout TaxYear) -> Void) {
        var copy = table
        change(&copy)
        settings.taxTable = copy
        save()
    }

    private func editBracket(_ index: Int, _ change: (inout TaxBracket) -> Void) {
        editTable { year in
            guard year.brackets.indices.contains(index) else { return }
            change(&year.brackets[index])
        }
    }

    private func moneyField(get: @escaping () -> Double,
                            set: @escaping (Double, inout TaxYear) -> Void) -> some View {
        MoneyField(value: Binding(
            get: get,
            set: { new in editTable { year in set(max(0, new), &year) } }),
                   decimals: 2, width: Theme.Size.picker, suffix: Money.symbol)
    }

    private func percentField(get: @escaping () -> Double,
                              set: @escaping (Double, inout TaxYear) -> Void) -> some View {
        MoneyField(value: Binding(
            get: { get() * 100 },
            set: { new in editTable { year in set(min(max(0, new), 100) / 100, &year) } }),
                   decimals: 1, width: Theme.Size.fieldSmall, suffix: "%")
    }

    // MARK: - Shared row shapes

    private func row<Content: View>(_ title: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ftInkSecondary)
                .gridColumnAlignment(.leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A figure in the year's breakdown.
    ///
    /// `relief` marks a row that lowers what is taxed rather than what reaches
    /// you. Painting those the same red as social security makes a benefit look
    /// like a cost — an exemption that wipes out the tax bill read as the
    /// largest expense on the screen.
    private func amountRow(_ title: String, _ amount: Double,
                           detail: String? = nil,
                           emphasised: Bool = false,
                           relief: Bool = false) -> some View {
        GridRow {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: emphasised ? .semibold : .regular))
                    .foregroundStyle(emphasised ? Color.ftInk : Color.ftInkSecondary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
            .gridColumnAlignment(.leading)

            // A rounded-away figure is zero, not minus zero.
            Text(Money.currency(abs(amount) < 0.005 ? 0 : amount))
                .font(.system(size: 13, weight: emphasised ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(amountColor(amount, relief: relief))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: Theme.tableHeaderSize, weight: .semibold))
            .tracking(Theme.tableHeaderTracking)
            .foregroundStyle(Color.ftInkTertiary)
            .gridColumnAlignment(.leading)
    }

    private func save() { try? context.save() }
}
