import Foundation

/// Where the income is taxed. The islands apply a reduction to the mainland
/// rates rather than publishing an unrelated set of brackets.
enum TaxRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case mainland, madeira, azores

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mainland: "Mainland"
        case .madeira: "Madeira"
        case .azores: "Azores"
        }
    }
}

/// One slice of the progressive scale. `upperLimit` is nil for the top band,
/// which has no ceiling.
struct TaxBracket: Codable, Sendable, Equatable {
    var upperLimit: Double?
    var rate: Double
}

/// Income above `floor` carries `rate` on top of the ordinary scale.
struct SolidarityBand: Codable, Sendable, Equatable {
    var floor: Double
    var rate: Double
}

/// Every figure the calculation depends on, in one editable value.
///
/// Deliberately data rather than code: Portuguese rates change every year with
/// the Orçamento do Estado, and a table baked into the binary goes quietly
/// wrong each January. This one is stored, editable, and stamped with the year
/// it describes so a stale table is visible rather than silent.
struct TaxYear: Codable, Sendable, Equatable {
    /// The key a previous version wrote the deduction under, read once so an
    /// edited figure carries over into the multiple.
    private enum LegacyKey: String, CodingKey { case specificDeduction }


    var year: Int
    var brackets: [TaxBracket]
    /// Employee social security, taken off the gross before IRS.
    var socialSecurityRate: Double
    /// The specific deduction as a multiple of the social support index,
    /// which is how it is set — so the deduction follows the index rather than
    /// being a second figure to look up and keep in step with it.
    var specificDeductionMultiple: Double
    var solidarityBands: [SolidarityBand]
    /// Indexante dos Apoios Sociais, which the young-taxpayer cap is a multiple of.
    var socialSupportIndex: Double
    /// The share of income exempt in each year of the young-taxpayer scheme,
    /// first year first.
    var youngExemptionShares: [Double]
    /// The exemption is capped at this many times the social support index.
    var youngExemptionCapMultiple: Double
    var creditPerDependent: Double
    /// Meal allowance is exempt up to a daily limit, and the limit is higher
    /// when it is paid onto a card than in cash. Anything above the limit is
    /// ordinary salary: taxed, and charged social security.
    var mealAllowanceCashLimit: Double
    var mealAllowanceCardLimit: Double
    /// Portugal pays fourteen times a year: twelve months plus holiday and
    /// Christmas subsidies. Getting this wrong misstates everything downstream.
    var paymentsPerYear: Int
    /// How much the mainland scale is reduced by, per region.
    var regionalReduction: [String: Double]

    /// Category A specific deduction. The actual rule takes the greater of
    /// this and the social security actually paid.
    var specificDeduction: Double { socialSupportIndex * specificDeductionMultiple }

    func reduction(for region: TaxRegion) -> Double {
        regionalReduction[region.rawValue] ?? 0
    }

    /// Puts the bands in order and guarantees exactly one open-ended top band,
    /// whichever order they were edited in.
    ///
    /// The scale walks the bands in sequence, so an out-of-order limit would
    /// silently stop it partway and leave income above that point untaxed.
    func normalised() -> TaxYear {
        var copy = self
        let finite = brackets
            .filter { $0.upperLimit != nil }
            .sorted { ($0.upperLimit ?? 0) < ($1.upperLimit ?? 0) }
        let top = brackets.first { $0.upperLimit == nil }
            ?? TaxBracket(upperLimit: nil, rate: brackets.last?.rate ?? 0)
        copy.brackets = finite + [top]
        return copy
    }

    /// Whether the bands are already in order with a single open-ended top.
    var bandsAreOrdered: Bool { brackets == normalised().brackets }

    /// Adds a band just below the open-ended top one, which is the only place
    /// a new band can go without leaving a gap.
    mutating func addBracket() {
        let highest = brackets.compactMap(\.upperLimit).max() ?? 0
        let insertAt = max(0, brackets.count - 1)
        let rate = brackets.indices.contains(insertAt) ? brackets[insertAt].rate : 0
        brackets.insert(TaxBracket(upperLimit: highest + 5_000, rate: rate), at: insertAt)
    }

    /// Removes a band. The open-ended top one stays: without it, income above
    /// the highest limit would not be taxed at all.
    mutating func removeBracket(at index: Int) {
        guard brackets.indices.contains(index),
              brackets[index].upperLimit != nil,
              brackets.count > 1 else { return }
        brackets.remove(at: index)
    }

    /// Which year of the young-taxpayer scheme this tax year is.
    ///
    /// The scheme runs for a number of *fiscal years claimed*, not calendar
    /// years elapsed: a year with no qualifying income consumes none of them,
    /// it just pushes the end further out. So the count walks the years and
    /// skips the ones that were never claimed.
    ///
    /// Nil before it starts, in a year that was skipped, and once the taper has
    /// been used up — so the exemption stops on its own.
    func youngTaxpayerYear(startingIn firstYear: Int, skipping skipped: Set<Int> = []) -> Int? {
        guard firstYear > 0, year >= firstYear, !skipped.contains(year) else { return nil }
        let claimed = (firstYear...year).count { !skipped.contains($0) }
        guard claimed >= 1, claimed <= youngExemptionShares.count else { return nil }
        return claimed
    }

    /// The fiscal year the last claim falls in. Later than a simple span
    /// whenever years were skipped along the way.
    func youngTaxpayerFinalYear(startingIn firstYear: Int,
                                skipping skipped: Set<Int> = []) -> Int {
        guard firstYear > 0 else { return firstYear }
        var claimed = 0
        var candidate = firstYear
        // Bounded: even skipping every other year, the taper is used up long
        // before this. The guard is here so a pathological set cannot hang.
        let limit = firstYear + youngExemptionShares.count * 4
        while candidate <= limit {
            if !skipped.contains(candidate) {
                claimed += 1
                if claimed == youngExemptionShares.count { return candidate }
            }
            candidate += 1
        }
        return limit
    }

    /// Drops skipped years the scheme never reaches.
    ///
    /// Marking a year unclaimed pushes the last claim out by one, which brings
    /// another year into range — so clicking along the row walks the range
    /// outward and can strand entries past the end, where they are invisible
    /// but still counted. Walking the claims forward and keeping only the skips
    /// met on the way is what makes the set mean what it says.
    func prunedSkips(startingIn firstYear: Int, skipping skipped: Set<Int>) -> Set<Int> {
        guard firstYear > 0, !skipped.isEmpty else { return [] }
        var claims = 0
        var kept: Set<Int> = []
        var candidate = firstYear
        let limit = firstYear + youngExemptionShares.count * 4
        while claims < youngExemptionShares.count && candidate <= limit {
            if skipped.contains(candidate) { kept.insert(candidate) } else { claims += 1 }
            candidate += 1
        }
        return kept
    }

    /// Every fiscal year the scheme touches, claimed or skipped.
    func youngTaxpayerYears(startingIn firstYear: Int, skipping skipped: Set<Int> = []) -> [Int] {
        guard firstYear > 0 else { return [] }
        return Array(firstYear...youngTaxpayerFinalYear(startingIn: firstYear, skipping: skipped))
    }

    func mealAllowanceLimit(onCard: Bool) -> Double {
        onCard ? mealAllowanceCardLimit : mealAllowanceCashLimit
    }

    /// Decoded field by field so a table saved before a figure existed still
    /// loads, keeping the rest of the edits rather than throwing them away and
    /// silently reverting to the built-in table.
    init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TaxYear.portugalDefaults
        year = try box.decodeIfPresent(Int.self, forKey: .year) ?? fallback.year
        brackets = try box.decodeIfPresent([TaxBracket].self,
                                           forKey: .brackets) ?? fallback.brackets
        socialSecurityRate = try box.decodeIfPresent(Double.self, forKey: .socialSecurityRate)
            ?? fallback.socialSecurityRate
        socialSupportIndex = try box.decodeIfPresent(Double.self, forKey: .socialSupportIndex)
            ?? fallback.socialSupportIndex
        // A table written when the deduction was its own figure keeps whatever
        // was set: the multiple is worked back out of it, so an edited value
        // survives the change rather than snapping to the default.
        let legacyBox = try decoder.container(keyedBy: LegacyKey.self)
        if let multiple = try box.decodeIfPresent(Double.self,
                                                  forKey: .specificDeductionMultiple) {
            specificDeductionMultiple = multiple
        } else if let legacy = try legacyBox.decodeIfPresent(
                    Double.self, forKey: .specificDeduction),
                  socialSupportIndex > 0 {
            specificDeductionMultiple = legacy / socialSupportIndex
        } else {
            specificDeductionMultiple = fallback.specificDeductionMultiple
        }
        // A table written when the deduction was its own figure keeps whatever
        // was set: the multiple is worked back out of it, so an edited value
        // survives the change rather than snapping to the default.
        solidarityBands = try box.decodeIfPresent([SolidarityBand].self, forKey: .solidarityBands)
            ?? fallback.solidarityBands
        youngExemptionShares = try box.decodeIfPresent([Double].self,
                                                       forKey: .youngExemptionShares)
            ?? fallback.youngExemptionShares
        youngExemptionCapMultiple = try box.decodeIfPresent(
            Double.self, forKey: .youngExemptionCapMultiple) ?? fallback.youngExemptionCapMultiple
        creditPerDependent = try box.decodeIfPresent(Double.self, forKey: .creditPerDependent)
            ?? fallback.creditPerDependent
        mealAllowanceCashLimit = try box.decodeIfPresent(
            Double.self, forKey: .mealAllowanceCashLimit) ?? fallback.mealAllowanceCashLimit
        mealAllowanceCardLimit = try box.decodeIfPresent(
            Double.self, forKey: .mealAllowanceCardLimit) ?? fallback.mealAllowanceCardLimit
        paymentsPerYear = try box.decodeIfPresent(Int.self, forKey: .paymentsPerYear)
            ?? fallback.paymentsPerYear
        regionalReduction = try box.decodeIfPresent([String: Double].self,
                                                    forKey: .regionalReduction)
            ?? fallback.regionalReduction
    }

    init(year: Int, brackets: [TaxBracket], socialSecurityRate: Double,
         specificDeductionMultiple: Double, solidarityBands: [SolidarityBand],
         socialSupportIndex: Double, youngExemptionShares: [Double],
         youngExemptionCapMultiple: Double, creditPerDependent: Double,
         mealAllowanceCashLimit: Double, mealAllowanceCardLimit: Double,
         paymentsPerYear: Int, regionalReduction: [String: Double]) {
        self.year = year
        self.brackets = brackets
        self.socialSecurityRate = socialSecurityRate
        self.specificDeductionMultiple = specificDeductionMultiple
        self.solidarityBands = solidarityBands
        self.socialSupportIndex = socialSupportIndex
        self.youngExemptionShares = youngExemptionShares
        self.youngExemptionCapMultiple = youngExemptionCapMultiple
        self.creditPerDependent = creditPerDependent
        self.mealAllowanceCashLimit = mealAllowanceCashLimit
        self.mealAllowanceCardLimit = mealAllowanceCardLimit
        self.paymentsPerYear = paymentsPerYear
        self.regionalReduction = regionalReduction
    }

    /// The figures the app ships with. A starting point to check against the
    /// Orçamento do Estado, not authority — every one of them is editable for
    /// exactly that reason.
    ///
    /// Confirmed for 2026: the escalões and the meal allowance limits. The
    /// card limit is the cash one plus 70%, so the two move together.
    ///
    /// Carried over from 2025 and still to be checked: the specific deduction,
    /// the social support index, the dependent credit and the solidarity
    /// floors.
    static let portugalDefaults = TaxYear(
        year: 2026,
        // The 2026 escalões. Each rate is the taxa normal — the rate on the
        // slice inside that band. The published taxa média for each band falls
        // out of these, which `TaxEngineTests` checks band by band.
        brackets: [
            TaxBracket(upperLimit: 8_342, rate: 0.125),
            TaxBracket(upperLimit: 12_587, rate: 0.157),
            TaxBracket(upperLimit: 17_838, rate: 0.212),
            TaxBracket(upperLimit: 23_089, rate: 0.241),
            TaxBracket(upperLimit: 29_397, rate: 0.311),
            TaxBracket(upperLimit: 43_090, rate: 0.349),
            TaxBracket(upperLimit: 46_566, rate: 0.431),
            TaxBracket(upperLimit: 86_634, rate: 0.446),
            TaxBracket(upperLimit: nil, rate: 0.480),
        ],
        socialSecurityRate: 0.11,
        specificDeductionMultiple: 8.54,
        solidarityBands: [
            SolidarityBand(floor: 80_000, rate: 0.025),
            SolidarityBand(floor: 250_000, rate: 0.050),
        ],
        socialSupportIndex: 522.50,
        youngExemptionShares: [1.0, 0.75, 0.75, 0.75, 0.5, 0.5, 0.5, 0.25, 0.25, 0.25],
        youngExemptionCapMultiple: 55,
        creditPerDependent: 600,
        mealAllowanceCashLimit: 6.15,
        mealAllowanceCardLimit: 10.46,
        paymentsPerYear: 14,
        regionalReduction: ["mainland": 0, "madeira": 0.20, "azores": 0.30])
}

struct TaxInput: Sendable, Equatable {
    var grossAnnual: Double
    var region: TaxRegion
    var dependents: Int
    /// Couples may be assessed together, which halves the income, taxes it,
    /// and doubles the result — worth something whenever the two earn unequally.
    var jointTaxation: Bool
    /// 1 through 10 while the young-taxpayer exemption applies, nil otherwise.
    var youngTaxpayerYear: Int?
    /// Health, education, housing and the rest, already totalled.
    var otherCredits: Double
    /// Meal allowance, as it is actually paid: a rate per working day.
    var mealAllowancePerDay: Double
    /// Days actually worked in the year — weekdays less holidays and vacation.
    /// `WorkingCalendar` works this out; it is not twelve months of anything.
    var mealAllowanceDaysPerYear: Double
    var mealAllowanceOnCard: Bool
    /// Whether the tax is taken monthly before the money reaches the bank,
    /// which is how employment income normally works. Off means the whole
    /// year's tax falls due after the annual return instead.
    var withholdingAtSource: Bool
    /// The rate withheld, when it is known from a payslip. Zero means it is
    /// not, and the year's assessment stands in for it.
    ///
    /// Withholding is not the tax: it is a running instalment against it, and
    /// any difference comes back — or falls due — after the annual return.
    var withholdingRate: Double
    /// Whether the allowance should count toward income that can be spent on
    /// anything. Off by default: a meal card buys food and nothing else, so
    /// treating it as free cash overstates what is actually available.
    var mealAllowanceSpendable: Bool
    var table: TaxYear

    init(grossAnnual: Double,
         region: TaxRegion = .mainland,
         dependents: Int = 0,
         jointTaxation: Bool = false,
         youngTaxpayerYear: Int? = nil,
         otherCredits: Double = 0,
         mealAllowancePerDay: Double = 0,
         mealAllowanceDaysPerYear: Double = 0,
         mealAllowanceOnCard: Bool = true,
         mealAllowanceSpendable: Bool = false,
         withholdingAtSource: Bool = true,
         withholdingRate: Double = 0,
         table: TaxYear = .portugalDefaults) {
        self.grossAnnual = grossAnnual
        self.region = region
        self.dependents = dependents
        self.jointTaxation = jointTaxation
        self.youngTaxpayerYear = youngTaxpayerYear
        self.otherCredits = otherCredits
        self.mealAllowancePerDay = mealAllowancePerDay
        self.mealAllowanceDaysPerYear = mealAllowanceDaysPerYear
        self.mealAllowanceOnCard = mealAllowanceOnCard
        self.mealAllowanceSpendable = mealAllowanceSpendable
        self.withholdingAtSource = withholdingAtSource
        self.withholdingRate = withholdingRate
        self.table = table
    }
}

/// What one band actually cost, so the result can be shown as a breakdown
/// rather than a single number to be taken on trust.
struct BracketSlice: Sendable, Equatable {
    var lowerLimit: Double
    var upperLimit: Double?
    var rate: Double
    var amountTaxed: Double
    var tax: Double
}

struct TaxAssessment: Sendable, Equatable {
    /// Base salary alone, which is what the scale is worked out from.
    var grossAnnual: Double
    /// Everything the employer pays over the year, salary and allowance
    /// together. Not the same as income for IRS: the exempt part of the
    /// allowance is never declared, so it is in this figure and not in
    /// `taxableIncome`.
    var totalGrossAnnual: Double
    /// The whole meal allowance for the year, and how it splits.
    var mealAllowanceGross: Double
    var mealAllowanceExempt: Double
    /// The part above the daily limit, which is taxed like salary.
    var mealAllowanceTaxable: Double
    var socialSecurity: Double
    var exemptIncome: Double
    var specificDeduction: Double
    var taxableIncome: Double
    var slices: [BracketSlice]
    var taxBeforeCredits: Double
    var solidaritySurcharge: Double
    var credits: Double
    var taxDue: Double
    var netAnnual: Double
    /// Spread evenly across the calendar, which is the figure a monthly budget
    /// needs — not what lands in the bank in a month with a subsidy in it.
    var netMonthly: Double
    /// What one of the year's payments is worth.
    var netPerPayment: Double
    /// What the employer holds back over the year at the withholding rate.
    var withheldAnnual: Double
    /// Withheld less the tax actually due: positive is a refund coming back,
    /// negative is a balance still to pay.
    var withholdingBalance: Double
    /// What actually reaches you across the year, at the withholding rate
    /// rather than the assessment.
    var takeHomeAnnual: Double
    var takeHomeMonthly: Double
    /// The single figure the rest of the app budgets on: what actually
    /// reaches you over the year, less anything that cannot be spent freely.
    ///
    /// Anything on screen calling itself spendable derives from this one, so
    /// two places cannot quote the same thing on different bases.
    var budgetAnnualIncome: Double
    var budgetMonthlyIncome: Double
    /// Net less the meal allowance, which is the figure a budget should use
    /// when the allowance lands on a card that only buys food.
    var spendableNetAnnual: Double
    var spendableNetMonthly: Double
    /// Everything taken, over everything received. Social security counts: it
    /// leaves too.
    var effectiveRate: Double
    /// What the next euro earned would cost: the band it lands in, plus any
    /// solidarity surcharge, plus social security — which is charged on the
    /// whole salary with no ceiling. Comparable with `effectiveRate`, which
    /// counts the same things.
    var marginalRate: Double
}

/// Estimates Portuguese personal income tax on employment income.
///
/// An estimate, not a return: withholding through the year and the final
/// assessment differ, and the mínimo de existência and several less common
/// reliefs are not modelled.
enum TaxEngine {

    static func assess(_ input: TaxInput) -> TaxAssessment {
        let table = input.table
        let salary = max(0, input.grossAnnual)
        let meal = mealAllowance(input)

        // Only the part of the allowance above the daily limit is income; the
        // rest is invisible to both social security and IRS.
        let employmentIncome = salary + meal.taxable

        let socialSecurity = employmentIncome * table.socialSecurityRate
        let exempt = youngExemption(gross: employmentIncome, input: input)

        // The specific deduction is the greater of the fixed figure and what
        // was actually paid in social security.
        let specific = max(table.specificDeduction, socialSecurity)
        let taxable = max(0, employmentIncome - exempt - specific)

        // Joint assessment taxes half the income and doubles the result, so a
        // couple is not pushed up the scale by pooling.
        let divisor: Double = input.jointTaxation ? 2 : 1
        let slices = self.slices(on: taxable / divisor, brackets: table.brackets)
        let scaleTax = slices.reduce(0) { $0 + $1.tax } * divisor

        let reduced = scaleTax * (1 - table.reduction(for: input.region))
        let solidarity = solidaritySurcharge(on: taxable, bands: table.solidarityBands)

        let credits = Double(max(0, input.dependents)) * table.creditPerDependent
            + max(0, input.otherCredits)
        // Credits reduce the bill to zero and no further: they are not a refund.
        let due = max(0, reduced + solidarity - credits)

        // The allowance is received in full: tax on the excess comes out of
        // the salary, not off the card.
        let net = salary + meal.gross - socialSecurity - due
        let received = salary + meal.gross
        let payments = max(1, table.paymentsPerYear)
        let spendable = input.mealAllowanceSpendable ? net : net - meal.gross

        // Withholding runs on the same income IRS does — the exempt part of
        // the allowance is invisible to it too.
        let rate = max(0, min(1, input.withholdingRate))
        // Nothing is held back when there is no withholding. Otherwise a known
        // rate is used, and failing that the assumption is that what is taken
        // matches what is due — which brings take-home back to the assessment.
        let withheld: Double
        if !input.withholdingAtSource {
            withheld = 0
        } else {
            withheld = rate > 0 ? employmentIncome * rate : due
        }
        let takeHome = salary + meal.gross - socialSecurity - withheld
        let spendableTakeHome = input.mealAllowanceSpendable
            ? takeHome : takeHome - meal.gross

        return TaxAssessment(
            grossAnnual: salary,
            totalGrossAnnual: received,
            mealAllowanceGross: meal.gross,
            mealAllowanceExempt: meal.exempt,
            mealAllowanceTaxable: meal.taxable,
            socialSecurity: socialSecurity,
            exemptIncome: exempt,
            specificDeduction: specific,
            taxableIncome: taxable,
            // Reported undivided, so the breakdown adds up to the tax charged.
            slices: input.jointTaxation ? slices.map { doubled($0) } : slices,
            taxBeforeCredits: reduced,
            solidaritySurcharge: solidarity,
            credits: min(credits, reduced + solidarity),
            taxDue: due,
            netAnnual: net,
            netMonthly: net / 12,
            // The allowance is paid per working day, not with the salary, so a
            // payment is worth the salary part alone.
            netPerPayment: (net - meal.gross) / Double(payments),
            withheldAnnual: withheld,
            withholdingBalance: withheld - due,
            takeHomeAnnual: takeHome,
            takeHomeMonthly: takeHome / 12,
            // Always what actually arrives: with withholding on and no rate
            // given this is the assessment anyway, and with it off the tax has
            // not been taken yet.
            budgetAnnualIncome: spendableTakeHome,
            budgetMonthlyIncome: spendableTakeHome / 12,
            spendableNetAnnual: spendable,
            spendableNetMonthly: spendable / 12,
            effectiveRate: received > 0 ? (socialSecurity + due) / received : 0,
            marginalRate: marginalRate(on: taxable / divisor, input: input))
    }

    /// What the meal allowance actually costs in tax and contributions: this
    /// assessment against the same one with no allowance at all.
    ///
    /// There is no flat rate on the allowance — the part above the daily limit
    /// is ordinary salary, so what it costs depends on the band it lands in.
    /// This turns that into one number to check a payslip against.
    static func mealAllowanceCost(_ input: TaxInput)
        -> (amount: Double, shareOfAllowance: Double, shareOfExcess: Double) {
        let with = assess(input)
        guard with.mealAllowanceGross > 0 else { return (0, 0, 0) }

        var bare = input
        bare.mealAllowancePerDay = 0
        // Terminates: the second assessment has no allowance, so it cannot
        // come back through here.
        let without = assess(bare)

        let cost = (with.socialSecurity + with.taxDue) - (without.socialSecurity + without.taxDue)
        return (amount: cost,
                shareOfAllowance: cost / with.mealAllowanceGross,
                shareOfExcess: with.mealAllowanceTaxable > 0
                    ? cost / with.mealAllowanceTaxable : 0)
    }

    /// Splits the year's meal allowance into the part below the daily limit
    /// and the part above it, which is ordinary salary.
    static func mealAllowance(_ input: TaxInput)
        -> (gross: Double, exempt: Double, taxable: Double) {
        let perDay = max(0, input.mealAllowancePerDay)
        let days = max(0, input.mealAllowanceDaysPerYear)
        guard perDay > 0, days > 0 else { return (0, 0, 0) }

        // The limit is a daily one, so it has to be applied per day and then
        // multiplied up. Comparing yearly totals against it would be wrong.
        let limit = input.table.mealAllowanceLimit(onCard: input.mealAllowanceOnCard)
        let exemptPerDay = min(perDay, limit)
        return (gross: perDay * days,
                exempt: exemptPerDay * days,
                taxable: (perDay - exemptPerDay) * days)
    }

    /// The share of income the young-taxpayer scheme exempts this year, capped
    /// at its multiple of the social support index.
    private static func youngExemption(gross: Double, input: TaxInput) -> Double {
        guard let year = input.youngTaxpayerYear,
              year >= 1, year <= input.table.youngExemptionShares.count else { return 0 }
        let share = input.table.youngExemptionShares[year - 1]
        let cap = input.table.youngExemptionCapMultiple * input.table.socialSupportIndex
        return min(gross * share, cap)
    }

    /// Walks the scale, taxing each band on the part of the income that falls
    /// inside it. Bands the income never reaches are left out.
    static func slices(on income: Double, brackets: [TaxBracket]) -> [BracketSlice] {
        var result: [BracketSlice] = []
        var lower: Double = 0
        for bracket in brackets {
            guard income > lower else { break }
            let ceiling = bracket.upperLimit ?? .greatestFiniteMagnitude
            let amount = min(income, ceiling) - lower
            guard amount > 0 else { break }
            result.append(BracketSlice(lowerLimit: lower,
                                       upperLimit: bracket.upperLimit,
                                       rate: bracket.rate,
                                       amountTaxed: amount,
                                       tax: amount * bracket.rate))
            lower = ceiling
        }
        return result
    }

    private static func doubled(_ slice: BracketSlice) -> BracketSlice {
        var copy = slice
        copy.amountTaxed *= 2
        copy.tax *= 2
        return copy
    }

    private static func solidaritySurcharge(on income: Double,
                                            bands: [SolidarityBand]) -> Double {
        // Each band charges only the part of the income above its own floor,
        // so a higher band never re-charges what a lower one already did.
        let sorted = bands.sorted { $0.floor < $1.floor }
        var total: Double = 0
        for (index, band) in sorted.enumerated() {
            guard income > band.floor else { break }
            let ceiling = index + 1 < sorted.count ? sorted[index + 1].floor : income
            total += (min(income, ceiling) - band.floor) * band.rate
        }
        return total
    }

    private static func marginalRate(on income: Double, input: TaxInput) -> Double {
        let table = input.table
        let scale = table.brackets.first { income <= ($0.upperLimit ?? .greatestFiniteMagnitude) }?
            .rate ?? table.brackets.last?.rate ?? 0
        let solidarity = table.solidarityBands
            .sorted { $0.floor < $1.floor }
            .last { income > $0.floor }?.rate ?? 0
        return scale * (1 - table.reduction(for: input.region))
            + solidarity
            + table.socialSecurityRate
    }
}
