import Foundation
import Testing
@testable import Ascend

@Suite("Portuguese tax")
struct TaxEngineTests {
    private let table = TaxYear.portugalDefaults

    private func assess(_ gross: Double,
                        region: TaxRegion = .mainland,
                        dependents: Int = 0,
                        joint: Bool = false,
                        youngYear: Int? = nil,
                        credits: Double = 0) -> TaxAssessment {
        TaxEngine.assess(TaxInput(grossAnnual: gross, region: region,
                                  dependents: dependents, jointTaxation: joint,
                                  youngTaxpayerYear: youngYear,
                                  otherCredits: credits, table: table))
    }

    // MARK: - The scale

    /// Read from the table rather than restated, so a rate change does not
    /// mean editing the tests that check the arithmetic.
    private var ceilings: [Double] { table.brackets.compactMap(\.upperLimit) }

    @Test("Each band taxes only the part of the income inside it")
    func slicesAreProgressive() {
        let income = ceilings[2] + 1_000          // partway into the fourth band
        let slices = TaxEngine.slices(on: income, brackets: table.brackets)
        #expect(slices.count == 4)
        #expect(slices[0].amountTaxed == ceilings[0])
        #expect(slices[1].amountTaxed == ceilings[1] - ceilings[0])
        #expect(slices[3].amountTaxed == income - ceilings[2])
        // The bands together account for the whole income, none of it twice.
        #expect(abs(slices.reduce(0) { $0 + $1.amountTaxed } - income) < 0.000_1)
    }

    @Test("Income below the first ceiling uses one band only")
    func singleBand() {
        let income = ceilings[0] / 2
        let slices = TaxEngine.slices(on: income, brackets: table.brackets)
        #expect(slices.count == 1)
        #expect(abs(slices[0].tax - income * table.brackets[0].rate) < 0.000_1)
    }

    @Test("Income above the top ceiling reaches the last band")
    func topBandHasNoCeiling() {
        let highest = ceilings.max()!
        let income = highest * 2
        let slices = TaxEngine.slices(on: income, brackets: table.brackets)
        #expect(slices.count == table.brackets.count)
        #expect(slices.last?.upperLimit == nil)
        #expect(abs(slices.last!.amountTaxed - (income - highest)) < 0.000_1)
    }

    @Test("No income means no tax and no negative anything")
    func zeroIncome() {
        let result = assess(0)
        #expect(result.taxDue == 0)
        #expect(result.netAnnual == 0)
        #expect(result.effectiveRate == 0)
        #expect(result.taxableIncome == 0)
    }

    @Test("Income under the deductions is not taxed")
    func belowDeductions() {
        let result = assess(4_000)
        #expect(result.taxableIncome == 0)
        #expect(result.taxDue == 0)
        // Social security still comes off, so net is below gross.
        #expect(result.netAnnual < 4_000)
    }

    // MARK: - Deductions and contributions

    @Test("Social security comes off the gross before anything else")
    func socialSecurityIsCharged() {
        let result = assess(30_000)
        #expect(abs(result.socialSecurity - 3_300) < 0.000_1)
    }

    @Test("The specific deduction is the greater of the fixed sum and what was paid")
    func specificDeductionTakesTheGreater() {
        // At a low salary the fixed figure wins.
        #expect(assess(20_000).specificDeduction == table.specificDeduction)
        // At a high one, 11% of gross exceeds it and is used instead.
        let high = assess(60_000)
        #expect(abs(high.specificDeduction - 6_600) < 0.000_1)
    }

    // MARK: - Rates

    @Test("The marginal rate counts social security, like the effective rate does")
    func marginalCountsSocialSecurity() {
        // Whichever band the taxable income lands in, the next euro also
        // carries the contribution.
        let taxable = assess(15_000).taxableIncome
        let band = table.brackets.first { taxable <= ($0.upperLimit ?? .infinity) }!
        #expect(abs(assess(15_000).marginalRate
                    - (band.rate + table.socialSecurityRate)) < 0.000_1)
        // The islands reduce the scale but not the contribution.
        #expect(assess(15_000, region: .azores).marginalRate
                < assess(15_000).marginalRate)
    }

    @Test("The effective rate stays below the marginal rate")
    func effectiveBelowMarginal() {
        for gross in [15_000.0, 30_000, 60_000, 120_000] {
            let result = assess(gross)
            #expect(result.effectiveRate < result.marginalRate)
        }
    }

    @Test("Earning more never leaves you with less")
    func netIncreasesWithGross() {
        var previous = 0.0
        for gross in stride(from: 10_000.0, through: 150_000, by: 5_000) {
            let net = assess(gross).netAnnual
            #expect(net > previous)
            previous = net
        }
    }

    @Test("The breakdown adds up to the tax charged")
    func slicesReconcile() {
        let result = assess(45_000)
        let fromSlices = result.slices.reduce(0) { $0 + $1.tax }
        #expect(abs(fromSlices - result.taxBeforeCredits) < 0.000_1)
    }

    // MARK: - Young taxpayer

    @Test("The first year of the young scheme exempts the most")
    func youngExemptionTapers() {
        let first = assess(25_000, youngYear: 1)
        let fifth = assess(25_000, youngYear: 5)
        let tenth = assess(25_000, youngYear: 10)
        let none = assess(25_000)
        #expect(first.taxDue < fifth.taxDue)
        #expect(fifth.taxDue < tenth.taxDue)
        #expect(tenth.taxDue < none.taxDue)
    }

    @Test("The young exemption is capped, so a large salary is not wholly exempt")
    func youngExemptionIsCapped() {
        let cap = table.youngExemptionCapMultiple * table.socialSupportIndex
        let result = assess(90_000, youngYear: 1)
        #expect(abs(result.exemptIncome - cap) < 0.000_1)
        #expect(result.taxDue > 0)
    }

    @Test("Below the cap the exemption is the full share of income")
    func youngExemptionUnderCap() {
        let result = assess(20_000, youngYear: 1)
        #expect(abs(result.exemptIncome - 20_000) < 0.000_1)
    }

    @Test("A year outside the scheme exempts nothing")
    func youngExemptionOutOfRange() {
        #expect(assess(25_000, youngYear: 0).exemptIncome == 0)
        #expect(assess(25_000, youngYear: 11).exemptIncome == 0)
        #expect(assess(25_000, youngYear: nil).exemptIncome == 0)
    }

    // MARK: - Household

    @Test("Joint assessment never costs a couple more than the single scale")
    func jointNeverCostsMore() {
        for gross in [30_000.0, 60_000, 120_000] {
            #expect(assess(gross, joint: true).taxDue <= assess(gross).taxDue)
        }
    }

    @Test("The joint breakdown still adds up to the tax charged")
    func jointSlicesReconcile() {
        let result = assess(60_000, joint: true)
        let fromSlices = result.slices.reduce(0) { $0 + $1.tax }
        #expect(abs(fromSlices - result.taxBeforeCredits) < 0.000_1)
    }

    @Test("Each dependent reduces the bill by the credit")
    func dependentsReduceTheBill() {
        let none = assess(40_000)
        let two = assess(40_000, dependents: 2)
        #expect(abs((none.taxDue - two.taxDue) - 2 * table.creditPerDependent) < 0.000_1)
    }

    @Test("Credits cannot push the bill below zero or turn into a refund")
    func creditsStopAtZero() {
        let result = assess(12_000, credits: 100_000)
        #expect(result.taxDue == 0)
        #expect(result.credits <= result.taxBeforeCredits + result.solidaritySurcharge)
    }

    // MARK: - Region and surcharge

    @Test("The islands charge less than the mainland on the same salary")
    func regionalReduction() {
        let mainland = assess(40_000)
        #expect(assess(40_000, region: .madeira).taxDue < mainland.taxDue)
        #expect(assess(40_000, region: .azores).taxDue < mainland.taxDue)
    }

    @Test("The solidarity surcharge starts only above its floor")
    func solidarityFloor() {
        #expect(assess(70_000).solidaritySurcharge == 0)
        #expect(assess(120_000).solidaritySurcharge > 0)
    }

    @Test("Each solidarity band charges only its own slice")
    func solidarityIsBanded() {
        // Taxable income here is gross less the 11% specific deduction.
        let result = assess(300_000)
        let taxable = result.taxableIncome
        let expected = (250_000 - 80_000) * 0.025 + (taxable - 250_000) * 0.05
        #expect(abs(result.solidaritySurcharge - expected) < 0.000_1)
    }

    // MARK: - What the rest of the app consumes

    @Test("Monthly net spreads the year evenly, not over the fourteen payments")
    func monthlyNetSpreadsEvenly() {
        let result = assess(28_000)
        #expect(abs(result.netMonthly - result.netAnnual / 12) < 0.000_1)
        #expect(abs(result.netPerPayment - result.netAnnual / 14) < 0.000_1)
        // Fourteen payments a year means a payment is smaller than a month.
        #expect(result.netPerPayment < result.netMonthly)
    }

    @Test("The rate table survives a round trip so it can be stored and edited")
    func tableIsCodable() throws {
        let data = try JSONEncoder().encode(table)
        #expect(try JSONDecoder().decode(TaxYear.self, from: data) == table)
    }

    @Test("An edited table changes the result, so editing rates actually works")
    func editingTheTableChangesTheOutcome() {
        var edited = table
        edited.socialSecurityRate = 0.20
        let changed = TaxEngine.assess(TaxInput(grossAnnual: 30_000, table: edited))
        #expect(changed.socialSecurity > assess(30_000).socialSecurity)
        #expect(changed.netAnnual < assess(30_000).netAnnual)
    }
}

@Suite("Tax drives projections")
struct TaxProjectionWiringTests {

    private func input(taxEnabled: Bool, gross: Double, typed: Double) -> PortfolioInput {
        PortfolioInput(
            accounts: [], records: [],
            targetNetWorth: 10_000,
            monthlyNetIncome: typed,
            projectionHorizonMonths: 12,
            tax: taxEnabled ? TaxInput(grossAnnual: gross) : nil)
    }

    @Test("With tax off, the typed figure is used")
    func typedWhenOff() {
        let subject = input(taxEnabled: false, gross: 40_000, typed: 1_500)
        #expect(subject.monthlyNetIncome == 1_500)
        #expect(!subject.derivesNetIncome)
    }

    @Test("With tax on, income is worked out and the typed figure ignored")
    func derivedWhenOn() {
        let subject = input(taxEnabled: true, gross: 40_000, typed: 1_500)
        let expected = TaxEngine.assess(TaxInput(grossAnnual: 40_000)).netMonthly
        #expect(subject.monthlyNetIncome == expected)
        #expect(subject.monthlyNetIncome != 1_500)
        #expect(subject.derivesNetIncome)
    }

    @Test("A raise flows through to the income projections run on")
    func raiseFlowsThrough() {
        let before = input(taxEnabled: true, gross: 40_000, typed: 0).monthlyNetIncome
        let after = input(taxEnabled: true, gross: 50_000, typed: 0).monthlyNetIncome
        #expect(after > before)
    }

    @Test("Derived income still leaves expenses derived from the expense list")
    func expensesStayDerived() {
        var subject = input(taxEnabled: true, gross: 40_000, typed: 0)
        subject.expenses = [ExpenseInput(id: UUID(), name: "Rent", amount: 400,
                                         frequency: .monthly, accountID: nil)]
        #expect(subject.maxMonthlyExpenses == 400)
        #expect(subject.monthlyNetIncome > 0)
    }
}

@Suite("Meal allowance")
struct MealAllowanceTests {
    private let table = TaxYear.portugalDefaults

    private func assess(salary: Double = 30_000,
                        perDay: Double,
                        days: Double = 229,
                        onCard: Bool = true,
                        spendable: Bool = false) -> TaxAssessment {
        TaxEngine.assess(TaxInput(grossAnnual: salary,
                                  mealAllowancePerDay: perDay,
                                  mealAllowanceDaysPerYear: days,
                                  mealAllowanceOnCard: onCard,
                                  mealAllowanceSpendable: spendable,
                                  table: table))
    }

    @Test("No allowance leaves the assessment untouched")
    func noAllowance() {
        let result = assess(perDay: 0)
        #expect(result.mealAllowanceGross == 0)
        #expect(result.mealAllowanceTaxable == 0)
        #expect(result.spendableNetAnnual == result.netAnnual)
    }

    @Test("An allowance at the card limit is wholly exempt")
    func atTheCardLimit() {
        let result = assess(perDay: table.mealAllowanceCardLimit)
        #expect(result.mealAllowanceTaxable == 0)
        #expect(abs(result.mealAllowanceExempt - result.mealAllowanceGross) < 0.000_1)
        // Exempt means invisible to both: same tax as with no allowance at all.
        #expect(abs(result.taxDue - assess(perDay: 0).taxDue) < 0.000_1)
        #expect(abs(result.socialSecurity - assess(perDay: 0).socialSecurity) < 0.000_1)
    }

    @Test("Only the part above the daily limit is taxed")
    func excessIsTaxed() {
        let overBy = 2.0
        let result = assess(perDay: table.mealAllowanceCardLimit + overBy)
        let days = 229.0
        #expect(abs(result.mealAllowanceTaxable - overBy * days) < 0.000_1)
        #expect(abs(result.mealAllowanceExempt - table.mealAllowanceCardLimit * days) < 0.000_1)
        // The excess is salary, so it carries social security too.
        #expect(result.socialSecurity > assess(perDay: 0).socialSecurity)
    }

    @Test("The limit is applied per day, not to the yearly total")
    func limitIsDaily() {
        // Half the days at double the rate is the same money, but not the same
        // tax: the daily limit only shelters so much on each day worked.
        let spread = assess(perDay: 10, days: 220)
        let concentrated = assess(perDay: 20, days: 110)
        #expect(abs(spread.mealAllowanceGross - concentrated.mealAllowanceGross) < 0.000_1)
        #expect(concentrated.mealAllowanceTaxable > spread.mealAllowanceTaxable)
    }

    @Test("Cash is sheltered less than a card, so it is taxed sooner")
    func cashLimitIsLower() {
        let perDay = table.mealAllowanceCardLimit
        #expect(assess(perDay: perDay, onCard: false).mealAllowanceTaxable > 0)
        #expect(assess(perDay: perDay, onCard: true).mealAllowanceTaxable == 0)
    }

    @Test("The allowance is received in full, so net income rises with it")
    func allowanceReachesYou() {
        let without = assess(perDay: 0)
        let with = assess(perDay: 9)
        #expect(with.netAnnual > without.netAnnual)
        #expect(abs(with.netAnnual - (without.netAnnual + with.mealAllowanceGross)) < 0.000_1)
    }

    @Test("A card that only buys food is kept out of spendable income")
    func cardIsNotSpendable() {
        let result = assess(perDay: 9)
        #expect(result.spendableNetAnnual < result.netAnnual)
        #expect(abs(result.spendableNetAnnual
                    - (result.netAnnual - result.mealAllowanceGross)) < 0.000_1)
        // Marking it spendable puts it back.
        let spendable = assess(perDay: 9, spendable: true)
        #expect(spendable.spendableNetAnnual == spendable.netAnnual)
    }

    @Test("A salary payment is worth the salary alone, not salary plus card")
    func paymentExcludesTheCard() {
        let result = assess(perDay: 9)
        let salaryNet = result.netAnnual - result.mealAllowanceGross
        #expect(abs(result.netPerPayment - salaryNet / 14) < 0.000_1)
    }

    @Test("The effective rate is measured against everything received")
    func effectiveRateCountsTheAllowance() {
        // An exempt allowance is money received untaxed, so it lowers the share
        // of the whole that tax takes.
        #expect(assess(perDay: 9).effectiveRate < assess(perDay: 0).effectiveRate)
    }

    @Test("Zero days means no allowance however high the daily rate")
    func zeroDays() {
        #expect(assess(perDay: 50, days: 0).mealAllowanceGross == 0)
        #expect(assess(perDay: 0, days: 229).mealAllowanceGross == 0)
    }

    @Test("A table saved before the allowance limits existed still loads")
    func decodesOlderTable() throws {
        // Everything except the two new fields, as an earlier version wrote it.
        var older = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(table)) as! [String: Any]
        older.removeValue(forKey: "mealAllowanceCashLimit")
        older.removeValue(forKey: "mealAllowanceCardLimit")
        older["specificDeductionMultiple"] = 9.0

        let data = try JSONSerialization.data(withJSONObject: older)
        let decoded = try JSONDecoder().decode(TaxYear.self, from: data)
        // The edit survives, and the missing figures fall back to the built-in.
        #expect(decoded.specificDeductionMultiple == 9.0)
        #expect(decoded.mealAllowanceCardLimit == table.mealAllowanceCardLimit)
    }
}

@Suite("Gross income")
struct GrossIncomeTests {

    private func assess(salary: Double, perDay: Double) -> TaxAssessment {
        TaxEngine.assess(TaxInput(grossAnnual: salary,
                                  mealAllowancePerDay: perDay,
                                  mealAllowanceDaysPerYear: 229))
    }

    @Test("Total gross is the salary plus the whole allowance")
    func totalGrossAddsTheAllowance() {
        let result = assess(salary: 30_000, perDay: 9)
        #expect(abs(result.totalGrossAnnual
                    - (result.grossAnnual + result.mealAllowanceGross)) < 0.000_1)
        #expect(result.totalGrossAnnual > result.grossAnnual)
    }

    @Test("Without an allowance, total gross is just the salary")
    func totalGrossWithoutAllowance() {
        let result = assess(salary: 30_000, perDay: 0)
        #expect(result.totalGrossAnnual == result.grossAnnual)
    }

    @Test("Total gross is what is paid, not what is declared for IRS")
    func totalGrossIsNotTaxableIncome() {
        // The exempt allowance sits inside total gross and outside taxable
        // income — that gap is the whole point of the allowance.
        let result = assess(salary: 30_000, perDay: 9)
        #expect(result.mealAllowanceExempt > 0)
        #expect(result.totalGrossAnnual - result.taxableIncome > result.mealAllowanceExempt)
        // An entirely exempt allowance raises what is paid without raising tax.
        let bigger = assess(salary: 30_000, perDay: 10)
        #expect(bigger.totalGrossAnnual > result.totalGrossAnnual)
        #expect(abs(bigger.taxDue - result.taxDue) < 0.000_1)
    }
}

@Suite("What the allowance costs")
struct MealAllowanceCostTests {
    private let table = TaxYear.portugalDefaults

    private func cost(perDay: Double, onCard: Bool = true, salary: Double = 30_000)
        -> (amount: Double, shareOfAllowance: Double, shareOfExcess: Double) {
        TaxEngine.mealAllowanceCost(
            TaxInput(grossAnnual: salary,
                     mealAllowancePerDay: perDay,
                     mealAllowanceDaysPerYear: 229,
                     mealAllowanceOnCard: onCard,
                     table: table))
    }

    @Test("An allowance inside the daily limit costs nothing at all")
    func exemptCostsNothing() {
        #expect(cost(perDay: table.mealAllowanceCardLimit).amount == 0)
        #expect(cost(perDay: table.mealAllowanceCardLimit).shareOfAllowance == 0)
        #expect(cost(perDay: 0).amount == 0)
    }

    @Test("Only the part above the limit is charged, so the bite is the smaller share")
    func costFallsOnTheExcessOnly() {
        let result = cost(perDay: 15)
        #expect(result.amount > 0)
        // The rate on the taxed slice is well above what it works out to
        // against the whole allowance — which is why a payslip can look like a
        // small flat percentage.
        #expect(result.shareOfExcess > result.shareOfAllowance)
    }

    @Test("The charge on the taxed part is social security plus the band it lands in")
    func excessIsChargedAtTheMarginalRate() {
        let input = TaxInput(grossAnnual: 30_000,
                             mealAllowancePerDay: 15,
                             mealAllowanceDaysPerYear: 229,
                             table: table)
        let marginal = TaxEngine.assess(input).marginalRate
        let result = TaxEngine.mealAllowanceCost(input)
        // Within a band, the excess is charged at exactly the marginal rate.
        #expect(abs(result.shareOfExcess - marginal) < 0.01)
    }

    @Test("Cash is sheltered less, so the same allowance costs more")
    func cashCostsMore() {
        let perDay = 9.0
        #expect(cost(perDay: perDay, onCard: false).amount
                > cost(perDay: perDay, onCard: true).amount)
    }

    @Test("The allowance never costs more than it is worth")
    func costCannotExceedTheAllowance() {
        for perDay in [7.0, 12, 20, 40] {
            let result = cost(perDay: perDay)
            #expect(result.shareOfAllowance >= 0)
            #expect(result.shareOfAllowance < 1)
        }
    }
}

@MainActor
@Suite("IRS Jovem")
struct YoungTaxpayerTests {

    private func settings(taxYear: Int = 2026) -> AppSettings {
        let settings = AppSettings()
        var table = TaxYear.portugalDefaults
        table.year = taxYear
        settings.taxTable = table
        settings.taxEnabled = true
        settings.grossAnnualIncome = 25_000
        return settings
    }

    // MARK: - The switch

    @Test("The switch reads the starting year, so a stored start is already on")
    func switchFollowsTheStartingYear() {
        let subject = settings()
        subject.taxYoungTaxpayerFirstYear = 2024
        #expect(subject.taxYoungTaxpayerEnabled)

        subject.taxYoungTaxpayerFirstYear = 0
        #expect(!subject.taxYoungTaxpayerEnabled)
    }

    @Test("Switching off remembers the starting year and switching on restores it")
    func togglingKeepsTheStartingYear() {
        let subject = settings()
        subject.taxYoungTaxpayerFirstYear = 2022

        subject.taxYoungTaxpayerEnabled = false
        #expect(subject.taxYoungTaxpayerFirstYear == 0)

        subject.taxYoungTaxpayerEnabled = true
        #expect(subject.taxYoungTaxpayerFirstYear == 2022)
    }

    @Test("Switching on from nothing assumes it started this tax year")
    func firstTimeStartsThisYear() {
        let subject = settings(taxYear: 2026)
        subject.taxYoungTaxpayerEnabled = true
        #expect(subject.taxYoungTaxpayerFirstYear == 2026)
        #expect(subject.taxYoungTaxpayerSchemeYear == 1)
    }

    @Test("Switching on twice does not move the starting year")
    func idempotent() {
        let subject = settings()
        subject.taxYoungTaxpayerFirstYear = 2023
        subject.taxYoungTaxpayerEnabled = true
        #expect(subject.taxYoungTaxpayerFirstYear == 2023)
    }

    // MARK: - Which year of the scheme

    @Test("The year of the scheme follows from the tax year, never typed")
    func schemeYearIsDerived() {
        let table = TaxYear.portugalDefaults
        var year2026 = table
        year2026.year = 2026
        #expect(year2026.youngTaxpayerYear(startingIn: 2026) == 1)
        #expect(year2026.youngTaxpayerYear(startingIn: 2024) == 3)
        #expect(year2026.youngTaxpayerYear(startingIn: 2017) == 10)
    }

    @Test("A year moves the scheme on by itself, with nothing to update")
    func advancesOnItsOwn() {
        let subject = settings(taxYear: 2026)
        subject.taxYoungTaxpayerFirstYear = 2024
        #expect(subject.taxYoungTaxpayerSchemeYear == 3)

        // Next year, having changed nothing else.
        var next = subject.taxTable
        next.year = 2027
        subject.taxTable = next
        #expect(subject.taxYoungTaxpayerSchemeYear == 4)
    }

    @Test("The exemption expires by itself once the taper runs out")
    func expiresOnItsOwn() {
        var table = TaxYear.portugalDefaults
        table.year = 2027
        #expect(table.youngTaxpayerYear(startingIn: 2017) == nil)
        #expect(table.youngTaxpayerFinalYear(startingIn: 2017) == 2026)

        let subject = settings(taxYear: 2040)
        subject.taxYoungTaxpayerFirstYear = 2024
        #expect(subject.taxYoungTaxpayerSchemeYear == nil)
        #expect(TaxEngine.assess(subject.taxInput!).exemptIncome == 0)
    }

    @Test("A start in the future exempts nothing yet")
    func notStartedYet() {
        let subject = settings(taxYear: 2026)
        subject.taxYoungTaxpayerFirstYear = 2028
        #expect(subject.taxYoungTaxpayerSchemeYear == nil)
        #expect(TaxEngine.assess(subject.taxInput!).exemptIncome == 0)
    }

    @Test("The taper reaches the assessment, smaller each year")
    func taperReachesTheEngine() {
        var previous = Double.infinity
        for start in stride(from: 2026, through: 2017, by: -1) {
            let subject = settings(taxYear: 2026)
            subject.taxYoungTaxpayerFirstYear = start
            let exempt = TaxEngine.assess(subject.taxInput!).exemptIncome
            #expect(exempt <= previous)
            previous = exempt
        }
        #expect(previous > 0)
    }

    // MARK: - Coming from the older model

    @Test("A stored year of the scheme becomes the year it started")
    func migratesFromSchemeYear() throws {
        let context = try inMemoryContext()
        let subject = SeedData.settings(in: context)
        var table = TaxYear.portugalDefaults
        table.year = 2026
        subject.taxTable = table
        subject.taxYoungTaxpayerYear = 3
        try context.save()

        SeedData.migrateYoungTaxpayerStart(context)
        // Year 3 of 2026 means it started in 2024.
        #expect(subject.taxYoungTaxpayerFirstYear == 2024)
        #expect(subject.taxYoungTaxpayerSchemeYear == 3)
        // The old field is cleared as it is read.
        #expect(subject.taxYoungTaxpayerYear == 0)
    }

    @Test("The migration cannot switch the scheme back on after it is turned off")
    func migrationRunsOnce() throws {
        let context = try inMemoryContext()
        let subject = SeedData.settings(in: context)
        subject.taxYoungTaxpayerYear = 2
        try context.save()

        SeedData.migrateYoungTaxpayerStart(context)
        #expect(subject.taxYoungTaxpayerEnabled)

        subject.taxYoungTaxpayerEnabled = false
        SeedData.migrateYoungTaxpayerStart(context)
        #expect(!subject.taxYoungTaxpayerEnabled)
    }

    @Test("A store that never used the scheme is left alone")
    func migrationIgnoresUnusedSettings() throws {
        let context = try inMemoryContext()
        let subject = SeedData.settings(in: context)
        SeedData.migrateYoungTaxpayerStart(context)
        #expect(subject.taxYoungTaxpayerFirstYear == 0)
        #expect(!subject.taxYoungTaxpayerEnabled)
    }
}

@MainActor
@Suite("IRS Jovem across fiscal years")
struct YoungTaxpayerFiscalYearTests {

    private func table(_ year: Int) -> TaxYear {
        var table = TaxYear.portugalDefaults
        table.year = year
        return table
    }

    @Test("A skipped year uses none of the scheme")
    func skippedYearIsNotCounted() {
        // Started 2024, nothing claimed in 2025: 2026 is still only the second
        // claimed year, not the third.
        #expect(table(2026).youngTaxpayerYear(startingIn: 2024, skipping: [2025]) == 2)
        #expect(table(2026).youngTaxpayerYear(startingIn: 2024) == 3)
    }

    @Test("The skipped year itself exempts nothing")
    func skippedYearExemptsNothing() {
        #expect(table(2025).youngTaxpayerYear(startingIn: 2024, skipping: [2025]) == nil)
    }

    @Test("Skipping pushes the final year out rather than losing a year")
    func skippingMovesTheEnd() {
        let plain = table(2026).youngTaxpayerFinalYear(startingIn: 2024)
        let withGaps = table(2026).youngTaxpayerFinalYear(startingIn: 2024,
                                                          skipping: [2025, 2027])
        #expect(plain == 2033)
        #expect(withGaps == plain + 2)
    }

    @Test("Ten claims are always available however they are spread")
    func tenClaimsRegardless() {
        let skipped: Set<Int> = [2025, 2027, 2029]
        let final = table(2026).youngTaxpayerFinalYear(startingIn: 2024, skipping: skipped)
        let claimed = (2024...final).filter { !skipped.contains($0) }
        #expect(claimed.count == 10)
        // Each claimed year maps to a distinct position in the taper.
        let positions = claimed.compactMap {
            table($0).youngTaxpayerYear(startingIn: 2024, skipping: skipped)
        }
        #expect(positions == Array(1...10))
    }

    @Test("The listed years cover every year the scheme touches, gaps included")
    func listedYearsIncludeGaps() {
        let skipped: Set<Int> = [2025]
        let years = table(2026).youngTaxpayerYears(startingIn: 2024, skipping: skipped)
        #expect(years.first == 2024)
        #expect(years.contains(2025))
        #expect(years.count == 11)
    }

    @Test("Skipped years survive being written to the store and read back")
    func skippedYearsRoundTrip() {
        let settings = AppSettings()
        settings.taxYoungTaxpayerFirstYear = 2024
        settings.taxYoungTaxpayerSkipped = [2027, 2025]
        #expect(settings.taxYoungTaxpayerSkippedRaw == "2025,2027")
        #expect(settings.taxYoungTaxpayerSkipped == [2025, 2027])
    }

    @Test("Toggling a year marks it unclaimed and back again")
    func togglingAYear() {
        let settings = AppSettings()
        settings.taxYoungTaxpayerFirstYear = 2024
        settings.toggleYoungTaxpayerYearClaimed(2025)
        #expect(settings.taxYoungTaxpayerSkipped == [2025])
        settings.toggleYoungTaxpayerYearClaimed(2025)
        #expect(settings.taxYoungTaxpayerSkipped.isEmpty)
    }

    @Test("Nonsense in the stored text is ignored rather than crashing")
    func malformedStorageIsIgnored() {
        let settings = AppSettings()
        settings.taxYoungTaxpayerFirstYear = 2024
        settings.taxYoungTaxpayerSkippedRaw = "2025, ,abc,2027,"
        #expect(settings.taxYoungTaxpayerSkipped == [2025, 2027])
    }

    @Test("A year the scheme never reaches cannot be stored as skipped")
    func straySkipsArePruned() {
        let settings = AppSettings()
        settings.taxYoungTaxpayerFirstYear = 2026
        // 2040 onwards is long past the tenth claim, so marking it means
        // nothing — and counted silently it produced "13 years not claimed".
        settings.taxYoungTaxpayerSkipped = [2027, 2040, 2041, 2055]
        #expect(settings.taxYoungTaxpayerSkipped == [2027])
    }

    @Test("Skips are meaningless before the scheme has a starting year")
    func skipsNeedAStart() {
        let settings = AppSettings()
        settings.taxYoungTaxpayerSkipped = [2027]
        #expect(settings.taxYoungTaxpayerSkipped.isEmpty)
    }

    @Test("A store carrying stray skips is repaired")
    func migrationClearsStraySkips() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        settings.taxYoungTaxpayerFirstYear = 2026
        settings.taxYoungTaxpayerSkippedRaw = "2040,2041,2042,2055,2056"
        try context.save()

        SeedData.migrateYoungTaxpayerSkips(context)
        #expect(settings.taxYoungTaxpayerSkipped.isEmpty)
    }

    @Test("A gap reaches the assessment, so the exemption is the earlier share")
    func gapReachesTheEngine() {
        let settings = AppSettings()
        settings.taxEnabled = true
        settings.grossAnnualIncome = 25_000
        settings.taxTable = table(2028)
        settings.taxYoungTaxpayerFirstYear = 2024

        let straight = TaxEngine.assess(settings.taxInput!).exemptIncome
        settings.taxYoungTaxpayerSkipped = [2025, 2026]
        let withGaps = TaxEngine.assess(settings.taxInput!).exemptIncome
        // Two years unclaimed means 2028 is the third claim, not the fifth —
        // and the third year still exempts more than the fifth does.
        #expect(withGaps > straight)
    }
}

@Suite("Withholding at source")
struct WithholdingTests {
    private let table = TaxYear.portugalDefaults

    private func assess(rate: Double = 0,
                        atSource: Bool = true,
                        salary: Double = 16_917,
                        perDay: Double = 0) -> TaxAssessment {
        TaxEngine.assess(TaxInput(grossAnnual: salary,
                                  mealAllowancePerDay: perDay,
                                  mealAllowanceDaysPerYear: 229,
                                  withholdingAtSource: atSource,
                                  withholdingRate: rate,
                                  table: table))
    }

    @Test("No rate means nothing is withheld and nothing is owed either way")
    func noRate() {
        let result = assess(rate: 0)
        // No rate means "assume it matches the tax", not "assume nothing is
        // taken" — otherwise take-home would ignore the tax altogether.
        #expect(result.withheldAnnual == result.taxDue)
        #expect(result.withholdingBalance == 0)
        #expect(result.takeHomeAnnual == result.netAnnual)
        // With no rate the budget falls back to the assessment.
        #expect(result.budgetMonthlyIncome == result.spendableNetMonthly)
    }

    @Test("Withholding is charged on the income IRS sees, not on the allowance")
    func withheldOnTheIRSBase() {
        // An exempt allowance is invisible to withholding, exactly as it is to
        // the tax itself.
        let plain = assess(rate: 0.102)
        let withAllowance = assess(rate: 0.102, perDay: table.mealAllowanceCardLimit)
        #expect(abs(plain.withheldAnnual - withAllowance.withheldAnnual) < 0.000_1)
        #expect(abs(plain.withheldAnnual - 16_917 * 0.102) < 0.000_1)
    }

    @Test("Withholding more than the tax due means a refund")
    func overWithholdingRefunds() {
        let result = assess(rate: 0.25)
        #expect(result.withheldAnnual > result.taxDue)
        #expect(result.withholdingBalance > 0)
        // And what reaches you in the year is less than the assessment says.
        #expect(result.takeHomeAnnual < result.netAnnual)
    }

    @Test("Withholding less than the tax due leaves a balance to pay")
    func underWithholdingLeavesABalance() {
        let result = assess(rate: 0.02)
        #expect(result.withholdingBalance < 0)
        #expect(result.takeHomeAnnual > result.netAnnual)
    }

    @Test("The balance is exactly what was withheld less what was due")
    func balanceReconciles() {
        let result = assess(rate: 0.102)
        #expect(abs(result.withholdingBalance
                    - (result.withheldAnnual - result.taxDue)) < 0.000_1)
        // Take-home plus the refund comes back to the assessment.
        #expect(abs((result.takeHomeAnnual + result.withholdingBalance)
                    - result.netAnnual) < 0.000_1)
    }

    @Test("With withholding off, nothing is taken monthly and it all falls due")
    func withholdingOff() {
        let off = assess(atSource: false)
        #expect(off.withheldAnnual == 0)
        // The whole year's tax is still owed — it just has not been taken yet.
        #expect(abs(off.withholdingBalance + off.taxDue) < 0.000_1)
        #expect(off.takeHomeAnnual > off.netAnnual)
    }

    @Test("Turning withholding off raises the monthly figure by the tax")
    func withholdingOffRaisesMonthlyIncome() {
        let on = assess()
        let off = assess(atSource: false)
        #expect(off.budgetMonthlyIncome > on.budgetMonthlyIncome)
        #expect(abs((off.budgetMonthlyIncome - on.budgetMonthlyIncome)
                    - on.taxDue / 12) < 0.000_1)
    }

    @Test("A known rate sharpens the monthly figure and shows the refund")
    func knownRateRefinesIt() {
        let estimated = assess()
        let known = assess(rate: 0.25)
        #expect(estimated.withholdingBalance == 0)
        #expect(known.withholdingBalance > 0)
        #expect(known.budgetMonthlyIncome < estimated.budgetMonthlyIncome)
    }

    @Test("A rate is ignored when nothing is withheld at all")
    func rateIgnoredWhenOff() {
        #expect(assess(rate: 0.25, atSource: false).withheldAnnual == 0)
    }

    @Test("The budget figure still holds the meal card back")
    func budgetStaysSpendableOnly() {
        let result = assess(rate: 0.102, perDay: 10.20)
        #expect(result.mealAllowanceGross > 0)
        #expect(abs(result.budgetMonthlyIncome
                    - (result.takeHomeAnnual - result.mealAllowanceGross) / 12) < 0.000_1)
    }

    @Test("An absurd rate is clamped rather than producing negative pay")
    func rateIsClamped() {
        #expect(assess(rate: 5).withheldAnnual <= 16_917)
        #expect(assess(rate: -1).withheldAnnual == assess(rate: 0).taxDue)
    }

    @Test("Projections budget on what actually arrives")
    func projectionsFollowWithholding() {
        let input = TaxInput(grossAnnual: 16_917, withholdingRate: 0.25)
        let portfolio = PortfolioInput(accounts: [], records: [],
                                       targetNetWorth: 0, monthlyNetIncome: 999,
                                       projectionHorizonMonths: 12, tax: input)
        #expect(abs(portfolio.monthlyNetIncome
                    - TaxEngine.assess(input).budgetMonthlyIncome) < 0.000_1)
        #expect(portfolio.monthlyNetIncome != 999)
    }
}

@MainActor
@Suite("Meal allowance limits for 2026")
struct MealAllowanceLimitMigrationTests {

    @Test("The card limit is the cash limit plus seventy per cent")
    func cardIsSeventyPercentAbove() {
        let table = TaxYear.portugalDefaults
        #expect(table.mealAllowanceCashLimit == 6.15)
        #expect(table.mealAllowanceCardLimit == 10.46)
        // 6,15 × 1,70 = 10,455, rounded up to the published 10,46.
        #expect(abs(table.mealAllowanceCardLimit
                    - (table.mealAllowanceCashLimit * 1.70)) < 0.01)
    }

    @Test("A card allowance of 10,20 is exempt with room to spare")
    func tenTwentyIsExempt() {
        let result = TaxEngine.assess(
            TaxInput(grossAnnual: 20_300,
                     mealAllowancePerDay: 10.20,
                     mealAllowanceDaysPerYear: 229))
        #expect(result.mealAllowanceTaxable == 0)
        #expect(TaxEngine.mealAllowanceCost(
            TaxInput(grossAnnual: 20_300,
                     mealAllowancePerDay: 10.20,
                     mealAllowanceDaysPerYear: 229)).amount == 0)
        // And there is headroom before it would start being taxed.
        #expect(TaxYear.portugalDefaults.mealAllowanceCardLimit > 10.20)
    }

    @Test("A saved table on the old limits is moved to the new ones")
    func migratesShippedLimits() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        var old = TaxYear.portugalDefaults
        old.mealAllowanceCashLimit = 6.00
        old.mealAllowanceCardLimit = 10.20
        settings.taxTable = old
        try context.save()

        SeedData.migrateMealAllowanceLimits(context)
        #expect(settings.taxTable.mealAllowanceCashLimit == 6.15)
        #expect(settings.taxTable.mealAllowanceCardLimit == 10.46)
    }

    @Test("An edited cash limit does not block the card limit being updated")
    func limitsMigrateIndependently() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        var mixed = TaxYear.portugalDefaults
        mixed.mealAllowanceCashLimit = 0        // set by hand, paid on a card
        mixed.mealAllowanceCardLimit = 10.20    // still the shipped figure
        settings.taxTable = mixed
        try context.save()

        SeedData.migrateMealAllowanceLimits(context)
        #expect(settings.taxTable.mealAllowanceCashLimit == 0)
        #expect(settings.taxTable.mealAllowanceCardLimit == 10.46)
    }

    @Test("A limit set by hand is left alone")
    func leavesEditedLimitsAlone() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        // Both figures are ones the app never shipped, so neither can be
        // mistaken for a default left untouched.
        var mine = TaxYear.portugalDefaults
        mine.mealAllowanceCashLimit = 5.00
        mine.mealAllowanceCardLimit = 9.00
        settings.taxTable = mine
        try context.save()

        SeedData.migrateMealAllowanceLimits(context)
        #expect(settings.taxTable.mealAllowanceCardLimit == 9.00)
        #expect(settings.taxTable.mealAllowanceCashLimit == 5.00)
    }

    @Test("Running the migration twice changes nothing the second time")
    func migrationIsIdempotent() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        var old = TaxYear.portugalDefaults
        old.mealAllowanceCashLimit = 6.00
        old.mealAllowanceCardLimit = 10.20
        settings.taxTable = old
        try context.save()

        SeedData.migrateMealAllowanceLimits(context)
        let after = settings.taxTable
        SeedData.migrateMealAllowanceLimits(context)
        #expect(settings.taxTable == after)
    }

    @Test("Other edits in the table survive the migration")
    func otherEditsSurvive() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        var mixed = TaxYear.portugalDefaults
        mixed.mealAllowanceCashLimit = 6.00
        mixed.mealAllowanceCardLimit = 10.20
        mixed.specificDeductionMultiple = 9.0
        mixed.year = 2027
        settings.taxTable = mixed
        try context.save()

        SeedData.migrateMealAllowanceLimits(context)
        #expect(settings.taxTable.specificDeductionMultiple == 9.0)
        #expect(settings.taxTable.year == 2027)
        #expect(settings.taxTable.mealAllowanceCardLimit == 10.46)
    }
}

@Suite("Setting up the bands")
struct TaxBracketEditingTests {

    private var table: TaxYear { TaxYear.portugalDefaults }

    @Test("The shipped scale is already in order with one open-ended top")
    func shippedScaleIsOrdered() {
        #expect(table.bandsAreOrdered)
        #expect(table.brackets.filter { $0.upperLimit == nil }.count == 1)
        #expect(table.brackets.last?.upperLimit == nil)
    }

    @Test("Bands entered out of order are sorted, keeping the top band last")
    func normalisingSorts() {
        var jumbled = table
        jumbled.brackets = [
            TaxBracket(upperLimit: 20_000, rate: 0.25),
            TaxBracket(upperLimit: nil, rate: 0.48),
            TaxBracket(upperLimit: 5_000, rate: 0.13),
        ]
        #expect(!jumbled.bandsAreOrdered)

        let fixed = jumbled.normalised()
        #expect(fixed.brackets.map(\.upperLimit) == [5_000, 20_000, nil])
        #expect(fixed.bandsAreOrdered)
    }

    @Test("Out-of-order bands would leave income untaxed, which sorting fixes")
    func sortingRestoresTheWholeScale() {
        var jumbled = table
        jumbled.brackets = [
            TaxBracket(upperLimit: 20_000, rate: 0.25),
            TaxBracket(upperLimit: 5_000, rate: 0.13),
            TaxBracket(upperLimit: nil, rate: 0.48),
        ]
        // The walk stops at the first band it has already passed, so part of
        // the income never gets taxed.
        let broken = TaxEngine.slices(on: 30_000, brackets: jumbled.brackets)
        let fixed = TaxEngine.slices(on: 30_000, brackets: jumbled.normalised().brackets)
        #expect(broken.reduce(0) { $0 + $1.amountTaxed } < 30_000)
        #expect(abs(fixed.reduce(0) { $0 + $1.amountTaxed } - 30_000) < 0.000_1)
    }

    @Test("A table with no open-ended band gains one")
    func normalisingAddsATop() {
        var capped = table
        capped.brackets = [TaxBracket(upperLimit: 10_000, rate: 0.2)]
        let fixed = capped.normalised()
        #expect(fixed.brackets.last?.upperLimit == nil)
        // Income above the last ceiling is taxed rather than falling off.
        #expect(TaxEngine.slices(on: 50_000, brackets: fixed.brackets).count == 2)
    }

    @Test("A new band goes below the open-ended one, above every ceiling")
    func addingABand() {
        var subject = table
        let before = subject.brackets.count
        subject.addBracket()
        #expect(subject.brackets.count == before + 1)
        #expect(subject.brackets.last?.upperLimit == nil)
        #expect(subject.bandsAreOrdered)
    }

    @Test("Removing a band takes that one and leaves the rest")
    func removingABand() {
        var subject = table
        let removed = subject.brackets[2].upperLimit
        subject.removeBracket(at: 2)
        #expect(subject.brackets.count == table.brackets.count - 1)
        #expect(!subject.brackets.contains { $0.upperLimit == removed })
    }

    @Test("The open-ended band cannot be removed")
    func topBandIsProtected() {
        var subject = table
        subject.removeBracket(at: subject.brackets.count - 1)
        #expect(subject.brackets.count == table.brackets.count)
        #expect(subject.brackets.last?.upperLimit == nil)
    }

    @Test("Removing an index that isn't there changes nothing")
    func removingOutOfRange() {
        var subject = table
        subject.removeBracket(at: 99)
        #expect(subject.brackets == table.brackets)
    }

    @Test("An edited scale reaches the assessment")
    func editedScaleChangesTheTax() {
        var flat = table
        flat.brackets = [TaxBracket(upperLimit: nil, rate: 0.10)]
        let before = TaxEngine.assess(TaxInput(grossAnnual: 30_000, table: table)).taxDue
        let after = TaxEngine.assess(TaxInput(grossAnnual: 30_000, table: flat)).taxDue
        #expect(after != before)
        #expect(after > 0)
    }
}

@MainActor
@Suite("The 2026 escalões")
struct Escaloes2026Tests {
    private let table = TaxYear.portugalDefaults

    /// Ceiling and published taxa média for each band, from the official
    /// table. The taxa normal is what the app stores; the taxa média is what
    /// the whole income up to that ceiling works out at. Checking one against
    /// the other verifies the app taxes the way the tables say it does — an
    /// independent check, not a restatement of the code.
    private let published: [(ceiling: Double, average: Double)] = [
        (8_342, 0.125_00),
        (12_587, 0.135_79),
        (17_838, 0.158_23),
        (23_089, 0.177_05),
        (29_397, 0.205_79),
        (43_090, 0.251_30),
        (46_566, 0.264_72),
        (86_634, 0.348_56),
    ]

    @Test("The ceilings are the published ones")
    func ceilingsMatch() {
        #expect(table.brackets.compactMap(\.upperLimit) == published.map(\.ceiling))
        #expect(table.brackets.count == 9)
        #expect(table.brackets.last?.rate == 0.48)
    }

    @Test("At every ceiling the average rate matches the published taxa média")
    func averageRatesMatch() {
        for band in published {
            let tax = TaxEngine.slices(on: band.ceiling, brackets: table.brackets)
                .reduce(0) { $0 + $1.tax }
            let average = tax / band.ceiling
            // The published figures carry three decimal places as percentages.
            #expect(abs(average - band.average) < 0.000_005,
                    "at \(band.ceiling): \(average) vs \(band.average)")
        }
    }

    @Test("The scale rises: every band is dearer than the one below it")
    func ratesAscend() {
        let rates = table.brackets.map(\.rate)
        #expect(rates == rates.sorted())
        #expect(Set(rates).count == rates.count)
    }

    @Test("A saved table on the previous escalões is moved to the current ones")
    func migratesPreviousBands() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        var old = TaxYear.portugalDefaults
        old.brackets = [
            TaxBracket(upperLimit: 8_059, rate: 0.130),
            TaxBracket(upperLimit: 12_160, rate: 0.165),
            TaxBracket(upperLimit: 17_233, rate: 0.220),
            TaxBracket(upperLimit: 22_306, rate: 0.250),
            TaxBracket(upperLimit: 28_400, rate: 0.320),
            TaxBracket(upperLimit: 41_629, rate: 0.355),
            TaxBracket(upperLimit: 44_987, rate: 0.435),
            TaxBracket(upperLimit: 83_696, rate: 0.450),
            TaxBracket(upperLimit: nil, rate: 0.480),
        ]
        settings.taxTable = old
        try context.save()

        SeedData.migrateTaxBands(context)
        #expect(settings.taxTable.brackets == table.brackets)
    }

    @Test("A scale edited by hand is left alone")
    func leavesEditedBandsAlone() throws {
        let context = try inMemoryContext()
        let settings = SeedData.settings(in: context)
        var mine = TaxYear.portugalDefaults
        mine.brackets = [TaxBracket(upperLimit: 10_000, rate: 0.1),
                         TaxBracket(upperLimit: nil, rate: 0.3)]
        settings.taxTable = mine
        try context.save()

        SeedData.migrateTaxBands(context)
        #expect(settings.taxTable.brackets.count == 2)
    }
}

@Suite("Spendable income agrees with itself")
struct SpendableConsistencyTests {

    private func assess(rate: Double, perDay: Double = 10.20) -> TaxAssessment {
        TaxEngine.assess(TaxInput(grossAnnual: 19_117,
                                  mealAllowancePerDay: perDay,
                                  mealAllowanceDaysPerYear: 229,
                                  withholdingRate: rate))
    }

    @Test("The yearly and monthly spendable figures are the same number")
    func annualAndMonthlyAgree() {
        for rate in [0.0, 0.102, 0.30] {
            let result = assess(rate: rate)
            #expect(abs(result.budgetAnnualIncome / 12
                        - result.budgetMonthlyIncome) < 0.000_1)
        }
    }

    @Test("Spendable income is what arrives, not what the assessment says")
    func spendableFollowsCash() {
        // Over-withheld: the refund has not arrived yet, so spendable income is
        // below the assessment. Quoting the assessment as spendable overstates
        // what there is to spend by the refund.
        let result = assess(rate: 0.30)
        #expect(result.budgetAnnualIncome < result.spendableNetAnnual)
        #expect(abs((result.spendableNetAnnual - result.budgetAnnualIncome)
                    - result.withholdingBalance) < 0.000_1)
    }

    @Test("With withholding matching the tax, both bases coincide")
    func basesMeetWhenWithholdingIsExact() {
        let result = assess(rate: 0)
        #expect(abs(result.budgetAnnualIncome - result.spendableNetAnnual) < 0.000_1)
    }

    @Test("Spendable holds the meal card back, on either basis")
    func mealCardHeldBack() {
        let result = assess(rate: 0.102)
        #expect(abs((result.takeHomeAnnual - result.budgetAnnualIncome)
                    - result.mealAllowanceGross) < 0.000_1)
    }
}

@MainActor
@Suite("What the tax screen hands over")
struct TaxHandoffTests {

    private func settings(enabled: Bool, gross: Double, typed: Double = 1_500) -> AppSettings {
        let settings = AppSettings()
        settings.taxEnabled = enabled
        settings.grossAnnualIncome = gross
        settings.monthlyNetIncome = typed
        return settings
    }

    private func portfolio(_ settings: AppSettings) -> PortfolioInput {
        PortfolioInput(accounts: [], records: [],
                       targetNetWorth: 0,
                       monthlyNetIncome: settings.monthlyNetIncome,
                       projectionHorizonMonths: 12,
                       tax: settings.taxInput)
    }

    @Test("Switched off, the typed figure is used however big the salary")
    func offUsesTheTypedFigure() {
        let subject = settings(enabled: false, gross: 19_117)
        #expect(subject.taxInput == nil)
        #expect(portfolio(subject).monthlyNetIncome == 1_500)
        #expect(!portfolio(subject).derivesNetIncome)
    }

    @Test("Switched on without a salary, there is nothing to hand over")
    func onWithoutSalary() {
        let subject = settings(enabled: true, gross: 0)
        #expect(subject.taxInput == nil)
        #expect(portfolio(subject).monthlyNetIncome == 1_500)
    }

    @Test("Switched on with a salary, the worked-out figure takes over")
    func onWithSalary() {
        let subject = settings(enabled: true, gross: 19_117)
        let input = portfolio(subject)
        #expect(input.derivesNetIncome)
        #expect(input.monthlyNetIncome != 1_500)
        #expect(input.monthlyNetIncome
                == TaxEngine.assess(subject.taxInput!).budgetMonthlyIncome)
    }

    @Test("The figure handed over is spendable, not gross or assessed")
    func handsOverTheSpendableFigure() {
        let subject = settings(enabled: true, gross: 19_117)
        subject.mealAllowancePerDay = 10.20
        subject.taxWithholdingRate = 0.102

        let assessment = TaxEngine.assess(subject.taxInput!)
        let handed = portfolio(subject).monthlyNetIncome
        // Not the gross, not the assessment, not the meal card.
        #expect(handed < subject.grossAnnualIncome / 12)
        #expect(handed != assessment.spendableNetMonthly)
        #expect(handed == assessment.budgetAnnualIncome / 12)
    }

    @Test("Switching it off hands control straight back")
    func switchingOffRestoresTheTypedFigure() {
        let subject = settings(enabled: true, gross: 19_117)
        #expect(portfolio(subject).derivesNetIncome)

        subject.taxEnabled = false
        #expect(portfolio(subject).monthlyNetIncome == 1_500)
    }
}

@Suite("The deduction follows the index")
struct SpecificDeductionTests {

    @Test("It is the index times the multiple, not a figure of its own")
    func derivedFromTheIndex() {
        let table = TaxYear.portugalDefaults
        #expect(abs(table.specificDeduction
                    - table.socialSupportIndex * table.specificDeductionMultiple) < 0.000_1)
    }

    @Test("Changing the index moves the deduction with it")
    func indexMovesTheDeduction() {
        var table = TaxYear.portugalDefaults
        let before = table.specificDeduction
        table.socialSupportIndex *= 1.10
        #expect(abs(table.specificDeduction - before * 1.10) < 0.000_1)
        // And the tax bill follows, which is the point of not typing it twice.
        let dearer = TaxEngine.assess(TaxInput(grossAnnual: 19_117, table: table))
        let plain = TaxEngine.assess(TaxInput(grossAnnual: 19_117,
                                              table: .portugalDefaults))
        #expect(dearer.taxableIncome < plain.taxableIncome)
    }

    @Test("The index also sets the IRS Jovem cap, from the same one figure")
    func oneIndexTwoUses() {
        var table = TaxYear.portugalDefaults
        table.socialSupportIndex = 600
        #expect(abs(table.specificDeduction - 600 * table.specificDeductionMultiple) < 0.000_1)

        let capped = TaxEngine.assess(TaxInput(grossAnnual: 90_000,
                                               youngTaxpayerYear: 1, table: table))
        #expect(abs(capped.exemptIncome
                    - 600 * table.youngExemptionCapMultiple) < 0.000_1)
    }

    @Test("A table saved when the deduction was typed keeps that figure")
    func legacyValueCarriesOver() throws {
        // Written under the old key, with no multiple: the multiple is worked
        // back out so the deduction lands on exactly what was saved.
        var older = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(TaxYear.portugalDefaults)) as! [String: Any]
        older.removeValue(forKey: "specificDeductionMultiple")
        older["specificDeduction"] = 4_350.24
        older["socialSupportIndex"] = 522.50

        let decoded = try JSONDecoder().decode(
            TaxYear.self, from: try JSONSerialization.data(withJSONObject: older))
        #expect(abs(decoded.specificDeduction - 4_350.24) < 0.000_1)
    }

    @Test("A table with neither figure falls back to the built-in multiple")
    func fallsBackWhenAbsent() throws {
        var older = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(TaxYear.portugalDefaults)) as! [String: Any]
        older.removeValue(forKey: "specificDeductionMultiple")

        let decoded = try JSONDecoder().decode(
            TaxYear.self, from: try JSONSerialization.data(withJSONObject: older))
        #expect(decoded.specificDeductionMultiple
                == TaxYear.portugalDefaults.specificDeductionMultiple)
    }
}

@MainActor
@Suite("Gross pay includes the food allowance")
struct GrossIncludesAllowanceTests {

    private func settings(gross: Double, perDay: Double = 10.20,
                          days: Int = 264) -> AppSettings {
        let settings = AppSettings()
        settings.taxEnabled = true
        settings.grossAnnualIncome = gross
        settings.mealAllowancePerDay = perDay
        settings.mealAllowanceDaysOverride = days
        return settings
    }

    @Test("The allowance is taken out of the entered figure, not added to it")
    func allowanceComesOutOfGross() {
        let subject = settings(gross: 23_118.40)
        #expect(abs(subject.mealAllowanceAnnual - 2_692.80) < 0.000_1)
        #expect(abs(subject.salaryExcludingMealAllowance - 20_425.60) < 0.000_1)
    }

    @Test("Total gross comes back to exactly what was entered")
    func totalMatchesTheInput() {
        let subject = settings(gross: 23_118.40)
        let assessment = TaxEngine.assess(subject.taxInput!)
        #expect(abs(assessment.totalGrossAnnual - 23_118.40) < 0.000_1)
        // And the salary line is the remainder, not the whole figure.
        #expect(abs(assessment.grossAnnual - 20_425.60) < 0.000_1)
    }

    @Test("Only the salary part is taxed and charged contributions")
    func allowanceIsNotTaxedTwice() {
        let subject = settings(gross: 23_118.40)
        let assessment = TaxEngine.assess(subject.taxInput!)
        #expect(abs(assessment.socialSecurity - 20_425.60 * 0.11) < 0.000_1)
        #expect(assessment.mealAllowanceTaxable == 0)
    }

    @Test("With no allowance the whole figure is salary")
    func noAllowance() {
        let subject = settings(gross: 20_300, perDay: 0)
        #expect(subject.mealAllowanceAnnual == 0)
        #expect(subject.salaryExcludingMealAllowance == 20_300)
    }

    @Test("An allowance larger than the pay leaves no negative salary")
    func allowanceCannotExceedGross() {
        let subject = settings(gross: 1_000, perDay: 10.20, days: 264)
        #expect(subject.salaryExcludingMealAllowance == 0)
        #expect(TaxEngine.assess(subject.taxInput!).taxDue == 0)
    }

    @Test("Raising the daily rate shifts pay from salary to the allowance")
    func rateShiftsTheSplit() {
        let low = settings(gross: 23_118.40, perDay: 5)
        let high = settings(gross: 23_118.40, perDay: 10.20)
        #expect(high.salaryExcludingMealAllowance < low.salaryExcludingMealAllowance)
        // The total is untouched: it is the figure that was entered.
        #expect(abs(TaxEngine.assess(high.taxInput!).totalGrossAnnual
                    - TaxEngine.assess(low.taxInput!).totalGrossAnnual) < 0.000_1)
        // And less taxable salary means less tax.
        #expect(TaxEngine.assess(high.taxInput!).socialSecurity
                < TaxEngine.assess(low.taxInput!).socialSecurity)
    }
}

@Suite("What counts as invested")
struct InvestedPerMonthTests {

    private func account(_ name: String, contribution: Double,
                         usable: Bool, savings: Bool,
                         tracking: InvestmentTracking = .auto,
                         destination: Bool = false) -> AccountInfo {
        AccountInfo(id: UUID(), name: name, colorHex: "#1F6E8C", sortOrder: 0,
                    includeInUsable: usable, countsAsSavings: savings,
                    expectedAnnualReturn: 0, monthlyContribution: contribution,
                    isLeftoverDestination: destination,
                    investmentTracking: tracking)
    }

    private func project(_ accounts: [AccountInfo], income: Double = 1_239)
        -> ProjectionAssumptions {
        let input = PortfolioInput(accounts: accounts, records: [],
                                   targetNetWorth: 0, monthlyNetIncome: income,
                                   projectionHorizonMonths: 1)
        return ProjectionEngine.project(input, records: [], from: Date()).assumptions
    }

    @Test("A transfer into an everyday current account is not investing")
    func currentAccountIsNotInvested() {
        let assumptions = project([
            account("Current", contribution: 1_239, usable: true, savings: false,
                    tracking: .excluded, destination: true),
            account("Brokerage", contribution: 100, usable: true, savings: true),
            account("Savings", contribution: 100, usable: true, savings: true),
        ])
        #expect(assumptions.totalInvestedPerMonth == 200)
    }

    @Test("Savings and investment accounts are both counted")
    func savingsAndInvestmentsCount() {
        let assumptions = project([
            account("Savings", contribution: 150, usable: true, savings: true),
            account("Brokerage", contribution: 50, usable: false, savings: false,
                    tracking: .included),
        ])
        #expect(assumptions.totalInvestedPerMonth == 200)
    }

    @Test("An account kept out of Investments and out of savings is not counted")
    func excludedAccountIsNotCounted() {
        let assumptions = project([
            account("Meal card", contribution: 224.40, usable: false, savings: false,
                    tracking: .excluded),
        ])
        #expect(assumptions.totalInvestedPerMonth == 0)
    }

    @Test("The leftover still balances against every contribution paid from salary")
    func leftoverStillBalances() {
        // The current account's transfer is not "invested", but it does leave
        // the salary — so it still comes off the leftover.
        let assumptions = project([
            account("Current", contribution: 300, usable: true, savings: false,
                    tracking: .excluded, destination: true),
            account("Brokerage", contribution: 100, usable: true, savings: true),
        ], income: 1_000)
        #expect(assumptions.totalInvestedPerMonth == 100)
        #expect(assumptions.leftoverPerMonth == 1_000 - 400)
    }

    @Test("Money is neither created nor destroyed by the split")
    func moneyIsConserved() {
        let accounts = [
            account("Current", contribution: 300, usable: true, savings: false,
                    tracking: .excluded, destination: true),
            account("Brokerage", contribution: 100, usable: true, savings: true),
        ]
        let input = PortfolioInput(accounts: accounts, records: [
            RecordInput(id: UUID(), date: Date(), createdAt: Date(),
                        balances: Dictionary(uniqueKeysWithValues:
                            accounts.map { ($0.id, 0.0) }))
        ], targetNetWorth: 0, monthlyNetIncome: 1_000, projectionHorizonMonths: 1)

        let projection = ProjectionEngine.project(
            input, records: LedgerEngine.derive(input), from: Date())
        // One month of income, no expenses: net worth rises by exactly income.
        let grown = projection.months.last!.netWorth - projection.months.first!.netWorth
        #expect(abs(grown - 1_000) < 0.000_1)
    }
}

@Suite("Income subtracted from itself")
struct LeftoverDestinationContributionTests {

    private func account(_ name: String, contribution: Double,
                         destination: Bool) -> AccountInfo {
        AccountInfo(id: UUID(), name: name, colorHex: "#1F6E8C", sortOrder: 0,
                    includeInUsable: true, countsAsSavings: false,
                    expectedAnnualReturn: 0, monthlyContribution: contribution,
                    isLeftoverDestination: destination,
                    investmentTracking: .excluded)
    }

    private func assumptions(_ accounts: [AccountInfo]) -> ProjectionAssumptions {
        ProjectionEngine.project(
            PortfolioInput(accounts: accounts, records: [], targetNetWorth: 0,
                           monthlyNetIncome: 1_239, projectionHorizonMonths: 1),
            records: [], from: Date()).assumptions
    }

    @Test("A contribution on the leftover destination is reported")
    func destinationContributionIsSurfaced() {
        let result = assumptions([account("Banco CTT", contribution: 1_239,
                                          destination: true)])
        #expect(result.leftoverDestinationContribution == 1_239)
        #expect(result.leftoverDestinationName == "Banco CTT")
    }

    @Test("It takes the whole contribution off the leftover, twice over")
    func itEatsTheLeftover() {
        let withIt = assumptions([account("Banco CTT", contribution: 1_239,
                                          destination: true)])
        let without = assumptions([account("Banco CTT", contribution: 0,
                                           destination: true)])
        // Income transferred out of the income it came from: with no expenses
        // it lands on exactly zero, and any expense at all pushes it negative.
        #expect(without.leftoverPerMonth == 1_239)
        #expect(withIt.leftoverPerMonth == 0)
        #expect(abs(without.leftoverPerMonth - withIt.leftoverPerMonth - 1_239) < 0.000_1)
    }

    @Test("With expenses on top it goes negative")
    func withExpensesItGoesNegative() {
        let accounts = [account("Banco CTT", contribution: 1_239, destination: true)]
        let input = PortfolioInput(
            accounts: accounts,
            records: [],
            expenses: [ExpenseInput(id: UUID(), name: "Rent", amount: 227.44,
                                    frequency: .monthly, accountID: nil)],
            targetNetWorth: 0, monthlyNetIncome: 1_239, projectionHorizonMonths: 1)
        let result = ProjectionEngine.project(input, records: [], from: Date()).assumptions
        #expect(abs(result.leftoverPerMonth + 227.44) < 0.000_1)
    }

    @Test("A destination with no contribution reports nothing to warn about")
    func nothingToWarnAbout() {
        let result = assumptions([account("Banco CTT", contribution: 0,
                                          destination: true)])
        #expect(result.leftoverDestinationContribution == 0)
    }

    @Test("A contribution elsewhere is not mistaken for this")
    func onlyTheDestinationCounts() {
        let result = assumptions([
            account("Banco CTT", contribution: 0, destination: true),
            account("Brokerage", contribution: 100, destination: false),
        ])
        #expect(result.leftoverDestinationContribution == 0)
        #expect(result.leftoverPerMonth == 1_239 - 100)
    }
}

@MainActor
@Suite("The leftover account's contribution is derived")
struct LeftoverContributionDerivedTests {

    @Test("Making an account the leftover destination clears its contribution")
    func settingDestinationClearsIt() throws {
        let context = try inMemoryContext()
        let main = Account(name: "Current", colorHex: "#1F6E8C", sortOrder: 0,
                           includeInUsable: true, countsAsSavings: false,
                           monthlyContribution: 1_239)
        context.insert(main)
        try context.save()

        AccountService.setLeftoverDestination(main, accounts: [main])
        #expect(main.isLeftoverDestination)
        #expect(main.monthlyContribution == 0)
    }

    @Test("Moving the destination elsewhere leaves the old one alone")
    func movingItDoesNotClearOthers() throws {
        let context = try inMemoryContext()
        let main = Account(name: "Current", colorHex: "#1F6E8C", sortOrder: 0,
                           includeInUsable: true, countsAsSavings: false)
        let savings = Account(name: "Savings", colorHex: "#7A5EA6", sortOrder: 1,
                              includeInUsable: true, countsAsSavings: true,
                              monthlyContribution: 100)
        context.insert(main); context.insert(savings)
        try context.save()

        AccountService.setLeftoverDestination(main, accounts: [main, savings])
        // The account that is not the destination keeps what it contributes.
        #expect(savings.monthlyContribution == 100)
    }

    @Test("A contribution left on the destination by an older version is cleared")
    func migrationClearsIt() throws {
        let context = try inMemoryContext()
        let main = Account(name: "Current", colorHex: "#1F6E8C", sortOrder: 0,
                           includeInUsable: true, countsAsSavings: false,
                           monthlyContribution: 1_239, isLeftoverDestination: true)
        context.insert(main)
        try context.save()

        SeedData.migrateLeftoverContribution(context)
        #expect(main.monthlyContribution == 0)
    }

    @Test("Clearing it puts the leftover back where it belongs")
    func leftoverRecovers() {
        let destination = AccountInfo(id: UUID(), name: "Current", colorHex: "#1F6E8C",
                                      sortOrder: 0, includeInUsable: true,
                                      countsAsSavings: false, expectedAnnualReturn: 0,
                                      monthlyContribution: 0,
                                      isLeftoverDestination: true,
                                      investmentTracking: .excluded)
        let input = PortfolioInput(accounts: [destination], records: [],
                                   targetNetWorth: 0, monthlyNetIncome: 1_239,
                                   projectionHorizonMonths: 1)
        let result = ProjectionEngine.project(input, records: [], from: Date()).assumptions
        #expect(result.leftoverPerMonth == 1_239)
        #expect(result.leftoverDestinationContribution == 0)
    }
}
