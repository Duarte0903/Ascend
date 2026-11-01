import Foundation

/// What a side hustle does, which is what sets the slice of its income that
/// is taxed at all under the regime simplificado.
///
/// The coefficient is the whole mechanism: the rest of the money is treated
/// as the cost of earning it, without receipts being asked for.
enum SideHustleActivity: String, CaseIterable, Identifiable, Sendable, Codable {
    /// The listed professions — consulting, design, writing, teaching.
    case professionalServices
    /// Services outside that list.
    case otherServices
    /// Selling things, and food and lodging.
    case goods
    /// Royalties and other intellectual property.
    case intellectualProperty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .professionalServices: "Professional services"
        case .otherServices: "Other services"
        case .goods: "Selling goods"
        case .intellectualProperty: "Intellectual property"
        }
    }

    /// The share of the income that counts as profit and is taxed.
    var coefficient: Double {
        switch self {
        case .professionalServices: 0.75
        case .otherServices: 0.35
        case .goods: 0.15
        case .intellectualProperty: 0.95
        }
    }

    /// The share that counts toward independent-worker contributions, which
    /// is a different fraction from the taxable one.
    var contributionShare: Double {
        switch self {
        case .goods: 0.20
        default: 0.70
        }
    }

    var caption: String {
        "\(Money.percent(coefficient)) of what you invoice is taxed; the rest is treated as the cost of earning it."
    }
}

/// Whether contributions are charged, when that is not left to the rules.
enum SideHustleContributions: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Work it out: exempt while the rules say so, charged otherwise.
    case automatic
    case exempt
    case charged

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Work it out"
        case .exempt: "Exempt"
        case .charged: "Charged"
        }
    }
}

/// One payment received, as it was invoiced.
struct SideHustleEarningInput: Identifiable, Hashable, Sendable {
    let id: UUID
    var date: Date
    /// What was invoiced, before anything is taken.
    var amount: Double
    var note: String
    /// Whether the money has actually arrived.
    ///
    /// Categoria B is taxed when it is received, not when it is billed, so an
    /// invoice still waiting owes nothing yet.
    var isPaid: Bool

    init(id: UUID = UUID(), date: Date, amount: Double, note: String = "",
         isPaid: Bool = true) {
        self.id = id
        self.date = date
        self.amount = amount
        self.note = note
        self.isPaid = isPaid
    }
}

struct SideHustleInput: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var activity: SideHustleActivity
    var contributions: SideHustleContributions
    var isArchived: Bool
    var sortOrder: Int
    var earnings: [SideHustleEarningInput]

    init(id: UUID = UUID(), name: String, colorHex: String = "#7A5EA6",
         activity: SideHustleActivity = .professionalServices,
         contributions: SideHustleContributions = .automatic,
         isArchived: Bool = false, sortOrder: Int = 0,
         earnings: [SideHustleEarningInput] = []) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.activity = activity
        self.contributions = contributions
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.earnings = earnings
    }
}

/// The rules the year is judged against, kept apart from the hustles so one
/// set of figures covers all of them.
struct SideHustleRules: Sendable, Hashable {
    /// The IRS rate the next euro of income meets. Side-hustle profit is not
    /// taxed on a scale of its own: it is added to everything else earned, so
    /// what it costs is the rate at the top of the pile.
    var marginalIRSRate: Double
    /// True when the rate above came from the Tax screen rather than typed.
    var derivesIRSRate: Bool
    /// Independent-worker contributions, which are not the employee rate.
    var contributionRate: Double
    /// Published yearly, and what the exemption ceiling is measured in.
    var socialSupportIndex: Double
    /// Whether there is a salary paying contributions already. It is one of
    /// the two conditions for the exemption.
    var hasEmployment: Bool
    /// Months of the year the hustle was actually running, used to average
    /// the income the exemption ceiling is tested against.
    var monthsActive: Int
    /// The share of profit IRS Jovem leaves untaxed this year.
    ///
    /// Article 12.º-B exempts income from categories A and B alike, so side
    /// work is covered on the same terms as the salary — nothing about it
    /// being invoiced rather than paid changes that.
    var youngExemptionShare: Double
    /// What is left of the year's exemption once the salary has taken its
    /// part. The cap, 55 times the index, is one allowance across both
    /// categories rather than one each.
    var youngExemptionRemaining: Double

    init(marginalIRSRate: Double = 0, derivesIRSRate: Bool = false,
         contributionRate: Double = 0.214, socialSupportIndex: Double = 522.50,
         hasEmployment: Bool = false, monthsActive: Int = 12,
         youngExemptionShare: Double = 0,
         youngExemptionRemaining: Double = 0) {
        self.marginalIRSRate = marginalIRSRate
        self.derivesIRSRate = derivesIRSRate
        self.contributionRate = contributionRate
        self.socialSupportIndex = socialSupportIndex
        self.hasEmployment = hasEmployment
        self.monthsActive = monthsActive
        self.youngExemptionShare = youngExemptionShare
        self.youngExemptionRemaining = youngExemptionRemaining
    }

    /// Below this a month, an employed person pays no contributions on the
    /// side work. Four times the index, which is the published threshold.
    var exemptionCeiling: Double { Money.cents(socialSupportIndex * 4) }
}

/// Why contributions came out the way they did, so a zero can be explained
/// rather than looking like a figure that failed to compute.
enum SideHustleContributionBasis: String, Sendable, Hashable {
    case charged
    case exemptBelowCeiling
    case exemptBySetting
    case chargedBySetting
    case noIncome
}

struct SideHustleAssessment: Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var activity: SideHustleActivity
    /// What was actually received in the year, which is what is taxed.
    var gross: Double
    /// Billed but still waiting. Owes nothing until it arrives.
    var outstanding: Double
    /// Received and outstanding together: everything billed.
    var invoiced: Double
    /// The part the coefficient leaves, before IRS Jovem.
    var taxableProfit: Double
    /// What IRS Jovem leaves untaxed, capped by whatever the salary left of
    /// the year's allowance.
    var youngExemption: Double
    /// Profit less that exemption: what IRS is actually charged on.
    var taxedProfit: Double
    var irs: Double
    /// What contributions are reckoned on, before the rate.
    var contributionBase: Double
    var contributions: Double
    var contributionBasis: SideHustleContributionBasis
    /// The monthly average the exemption ceiling is tested against.
    var monthlyRelevantIncome: Double
    var totalTax: Double
    /// What is left once IRS and contributions are set aside.
    var net: Double
    /// Everything taken, over everything invoiced.
    var effectiveRate: Double
    var earningCount: Int
}

/// Estimates what a side hustle costs in tax under the Portuguese regime
/// simplificado for Categoria B.
///
/// An estimate, not a return. The coefficient is applied without the
/// minimum-expenses adjustment, VAT is not modelled, and IRS is reckoned at
/// the rate the next euro meets rather than by re-running the whole scale.
enum SideHustleEngine {

    static func assess(_ hustle: SideHustleInput,
                       rules: SideHustleRules,
                       year: Int,
                       calendar: Calendar = .current) -> SideHustleAssessment {
        let earnings = self.earnings(of: hustle, in: year, calendar: calendar)
        // Only money that has arrived is taxed; the rest is simply owed.
        let gross = Money.cents(earnings.filter(\.isPaid)
            .reduce(0) { $0 + max(0, $1.amount) })
        let outstanding = Money.cents(earnings.filter { !$0.isPaid }
            .reduce(0) { $0 + max(0, $1.amount) })
        let profit = Money.cents(gross * hustle.activity.coefficient)
        // IRS Jovem covers categories A and B alike, and the cap is shared:
        // what the salary has already used is gone before this is reached.
        let share = max(0, min(1, rules.youngExemptionShare))
        let exemption = Money.cents(min(profit * share,
                                        max(0, rules.youngExemptionRemaining)))
        let taxed = Money.cents(max(0, profit - exemption))
        let irs = Money.cents(taxed * max(0, min(1, rules.marginalIRSRate)))

        let base = Money.cents(gross * hustle.activity.contributionShare)
        let months = max(1, rules.monthsActive)
        let monthly = Money.cents(base / Double(months))

        let basis = contributionBasis(hustle: hustle, rules: rules,
                                      gross: gross, monthly: monthly)
        let contributions = basis == .charged || basis == .chargedBySetting
            ? Money.cents(base * max(0, rules.contributionRate)) : 0

        let total = Money.cents(irs + contributions)
        return SideHustleAssessment(
            id: hustle.id,
            name: hustle.name,
            colorHex: hustle.colorHex,
            activity: hustle.activity,
            gross: gross,
            outstanding: outstanding,
            invoiced: Money.cents(gross + outstanding),
            taxableProfit: profit,
            youngExemption: exemption,
            taxedProfit: taxed,
            irs: irs,
            contributionBase: base,
            contributions: contributions,
            contributionBasis: basis,
            monthlyRelevantIncome: monthly,
            totalTax: total,
            net: Money.cents(gross - total),
            effectiveRate: gross > 0 ? total / gross : 0,
            earningCount: earnings.count)
    }

    /// Everything invoiced in one calendar year, newest first.
    static func earnings(of hustle: SideHustleInput, in year: Int,
                         calendar: Calendar = .current) -> [SideHustleEarningInput] {
        hustle.earnings
            .filter { calendar.component(.year, from: $0.date) == year }
            .sorted { $0.date > $1.date }
    }

    /// Every year that has something in it, newest first.
    static func years(in hustles: [SideHustleInput],
                      calendar: Calendar = .current) -> [Int] {
        Set(hustles.flatMap(\.earnings).map { calendar.component(.year, from: $0.date) })
            .sorted(by: >)
    }

    private static func contributionBasis(hustle: SideHustleInput,
                                          rules: SideHustleRules,
                                          gross: Double,
                                          monthly: Double) -> SideHustleContributionBasis {
        guard gross > 0 else { return .noIncome }
        switch hustle.contributions {
        case .exempt: return .exemptBySetting
        case .charged: return .chargedBySetting
        case .automatic:
            // A salary already paying contributions, and side work small
            // enough, means nothing further is due on the side work.
            if rules.hasEmployment, monthly <= rules.exemptionCeiling {
                return .exemptBelowCeiling
            }
            return .charged
        }
    }
}

/// Every hustle for one year, plus the totals that only make sense together.
struct SideHustleYear: Sendable {
    var year: Int
    var hustles: [SideHustleAssessment]
    var gross: Double
    var outstanding: Double
    var invoiced: Double
    /// What IRS Jovem took off across all of them, which is what the salary
    /// left of the year's one allowance.
    var youngExemption: Double
    var irs: Double
    var contributions: Double
    var totalTax: Double
    var net: Double
    var effectiveRate: Double

    static func compute(_ hustles: [SideHustleInput],
                        rules: SideHustleRules,
                        year: Int,
                        calendar: Calendar = .current) -> SideHustleYear {
        // One allowance, handed out in order rather than to each in full:
        // giving every hustle the whole remaining cap would exempt the same
        // money several times over.
        var remaining = rules.youngExemptionRemaining
        var assessments: [SideHustleAssessment] = []
        for hustle in hustles.filter({ !$0.isArchived })
            .sorted(by: { $0.sortOrder < $1.sortOrder }) {
            var scoped = rules
            scoped.youngExemptionRemaining = remaining
            let assessment = SideHustleEngine.assess(hustle, rules: scoped,
                                                     year: year, calendar: calendar)
            remaining = Money.cents(max(0, remaining - assessment.youngExemption))
            assessments.append(assessment)
        }
        let gross = Money.cents(assessments.reduce(0) { $0 + $1.gross })
        let outstanding = Money.cents(assessments.reduce(0) { $0 + $1.outstanding })
        let exemption = Money.cents(assessments.reduce(0) { $0 + $1.youngExemption })
        let irs = Money.cents(assessments.reduce(0) { $0 + $1.irs })
        let contributions = Money.cents(assessments.reduce(0) { $0 + $1.contributions })
        let total = Money.cents(irs + contributions)
        return SideHustleYear(year: year, hustles: assessments, gross: gross,
                              outstanding: outstanding,
                              invoiced: Money.cents(gross + outstanding),
                              youngExemption: exemption,
                              irs: irs, contributions: contributions,
                              totalTax: total, net: Money.cents(gross - total),
                              effectiveRate: gross > 0 ? total / gross : 0)
    }
}
