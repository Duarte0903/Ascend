import Foundation

/// One tracked holding: what you put in, what it is worth now, and the gap.
struct InvestmentHolding: Identifiable, Sendable {
    let accountID: UUID
    var id: UUID { accountID }
    let name: String
    let colorHex: String
    /// What you have put in, as you have recorded it.
    let invested: Double
    /// The latest recorded balance.
    let value: Double
    /// The first record this account appears in with a balance, which is how
    /// long it has been running. Balances cannot tell us the return over a
    /// period — deposits are inside them — but they can tell us the span.
    let trackedSince: Date?
    /// Years between that first record and the latest one.
    let years: Double?

    var profit: Double { value - invested }

    /// Total return since you started, with no time in it. nil when nothing has
    /// been invested — a return on zero is undefined, not infinite.
    var returnRate: Double? {
        invested > 0 ? profit / invested : nil
    }

    /// The same return expressed per year, so it can be judged against an
    /// annual benchmark. nil under a year of history: annualising a few weeks
    /// produces absurd figures, so it is better to say nothing.
    var annualisedReturn: Double? {
        InvestmentMetrics.annualise(returnRate, overYears: years)
    }

    /// Share of the tracked portfolio's current value.
    var share: Double = 0

    // MARK: - Looking forward

    /// The rate this account is expected to return, as set on Accounts. This is
    /// an assumption, unlike every figure above it, which is recorded history.
    var expectedAnnualReturn: Double = 0
    var monthlyContribution: Double = 0
    /// A date a payment falls on, and how often they recur.
    var interestDate: Date?
    var interestFrequency: InterestFrequency = .none
    /// What interest is taxed at as it is credited.
    var interestTaxRate: Double = 0

    /// The rate actually charged against this holding's growth.
    ///
    /// Interest is taxed when it is credited, so an account on a schedule earns
    /// net. An account whose gains are only taxed on sale is not taxed year by
    /// year — charging it annually would overstate the bill and depends on a
    /// sale date the app does not know.
    var appliedTaxRate: Double {
        interestFrequency.isScheduled ? min(max(0, interestTaxRate), 1) : 0
    }

    /// The balance compounded forward at the expected rate, with the monthly
    /// contribution added each month — the same arithmetic Projections uses, so
    /// the two screens cannot disagree about the same account.
    func projectedValue(months: Int) -> Double {
        guard months > 0 else { return value }
        // Tax comes off the growth, not off the balance: what is credited is
        // what compounds from then on.
        let gross = pow(1 + expectedAnnualReturn, 1.0 / 12.0)
        let monthlyGrowth = 1 + (gross - 1) * (1 - appliedTaxRate)
        var running = value
        for _ in 1...months {
            running = running * monthlyGrowth + monthlyContribution
        }
        return running
    }

    /// What you would have paid in over the period. Not return — this is your
    /// own money arriving, and mixing it into a projection makes an account you
    /// pay into look like it earns more than one you don't.
    func contributions(overMonths months: Int) -> Double {
        guard months > 0 else { return 0 }
        return monthlyContribution * Double(months)
    }

    /// What the account actually earns over the period: the projected value
    /// less what you started with and less what you put in.
    func growth(overMonths months: Int) -> Double {
        projectedValue(months: months) - value - contributions(overMonths: months)
    }

    /// What one payment should be worth at today's balance.
    ///
    /// The expected return is an *annual* figure, so a monthly payer credits a
    /// twelfth of it — not the whole rate twelve times. And it is the twelfth
    /// root, not a twelfth: the expected return is what a year actually yields,
    /// so twelve payments have to compound back to exactly it. Dividing by
    /// twelve instead would compound to 3,04% on a 3% account, quietly paying
    /// more than the account promises.
    var expectedInterestPerPayment: Double? {
        guard interestFrequency.isScheduled, interestFrequency.timesPerYear > 0,
              expectedAnnualReturn > 0, value > 0 else { return nil }
        return value * (pow(1 + expectedAnnualReturn,
                            1 / interestFrequency.timesPerYear) - 1)
    }

    /// What actually reaches the account, once the tax on interest is taken.
    var netInterestPerPayment: Double? {
        guard let gross = expectedInterestPerPayment else { return nil }
        return gross * (1 - appliedTaxRate)
    }

    /// The next payment due, today included.
    ///
    /// Walks forward from the anchor in whole steps of the frequency, so a
    /// quarterly account anchored in January pays in April, July and October —
    /// not on one anniversary a year.
    func nextInterest(after now: Date,
                      calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        guard let anchor = interestDate,
              let step = interestFrequency.monthsBetween, step > 0 else { return nil }

        let today = calendar.startOfDay(for: now)
        var candidate = calendar.startOfDay(for: anchor)
        guard candidate < today else { return candidate }

        // Jump most of the way in one go rather than stepping month by month
        // through what might be decades of an old anchor.
        let months = calendar.dateComponents([.month], from: candidate, to: today).month ?? 0
        if months >= step,
           let leap = calendar.date(byAdding: .month, value: (months / step) * step,
                                    to: candidate) {
            candidate = leap
        }
        while candidate < today {
            guard let next = calendar.date(byAdding: .month, value: step, to: candidate)
            else { return nil }
            candidate = next
        }
        return candidate
    }
}

struct InvestmentMetrics: Sendable {
    var holdings: [InvestmentHolding]
    var totalInvested: Double
    var totalValue: Double
    var totalProfit: Double
    /// Combined return since you started. nil when nothing is invested.
    var overallReturn: Double?
    /// That return per year. nil until there is a year of records to divide by.
    var annualisedReturn: Double?
    /// When the earliest tracked account first appears in the records.
    var trackedSince: Date?
    var years: Double?
    /// The return you are aiming to beat, as a fraction, per year.
    var target: Double
    /// Judged against the annualised return when there is one, since the target
    /// is an annual rate. Falls back to the total return, which flatters a long
    /// history — `comparingAnnualised` says which was used.
    var meetsTarget: Bool
    var comparingAnnualised: Bool
    /// What the portfolio would need to be worth to hit the target overall.
    var valueNeededForTarget: Double
    var amountToTarget: Double
    var best: InvestmentHolding?
    var worst: InvestmentHolding?

    /// Converts a total return into a per-year one. Refuses under a year, and
    /// refuses a loss of everything, where the maths has no real answer.
    static func annualise(_ total: Double?, overYears years: Double?) -> Double? {
        guard let total, let years, years >= 1, total > -1 else { return nil }
        return pow(1 + total, 1 / years) - 1
    }

    /// Holdings are the accounts whose tracking resolves to true: by default
    /// those counting toward the savings rate, plus or minus anything set
    /// explicitly.
    static func compute(accounts: [AccountInfo],
                        records: [DerivedRecord],
                        target: Double,
                        interestTaxRate: Double = 0) -> InvestmentMetrics {
        let tracked = accounts
            .filter { $0.investmentTracking.tracks(countsAsSavings: $0.countsAsSavings) }
            .sorted { $0.sortOrder < $1.sortOrder }
        let latest = records.last

        func firstAppearance(of accountID: UUID) -> Date? {
            records.first { $0.amount(for: accountID) != 0 }?.date
        }
        func span(from start: Date?) -> Double? {
            guard let start, let end = latest?.date, end > start else { return nil }
            return end.timeIntervalSince(start) / (365.25 * 24 * 60 * 60)
        }

        var holdings = tracked.map { account in
            let since = firstAppearance(of: account.id)
            return InvestmentHolding(accountID: account.id,
                                     name: account.name,
                                     colorHex: account.colorHex,
                                     invested: account.amountInvested,
                                     value: latest?.amount(for: account.id) ?? 0,
                                     trackedSince: since,
                                     years: span(from: since),
                                     expectedAnnualReturn: account.expectedAnnualReturn,
                                     monthlyContribution: account.monthlyContribution,
                                     interestDate: account.interestDate,
                                     interestFrequency: account.interestFrequency,
                                     interestTaxRate: interestTaxRate)
        }

        let totalValue = holdings.reduce(0) { $0 + $1.value }
        let totalInvested = holdings.reduce(0) { $0 + $1.invested }
        let totalProfit = totalValue - totalInvested

        for index in holdings.indices {
            holdings[index].share = totalValue == 0 ? 0 : holdings[index].value / totalValue
        }

        let overall: Double? = totalInvested > 0 ? totalProfit / totalInvested : nil
        // The portfolio has been running since its earliest holding appeared.
        let since = holdings.compactMap(\.trackedSince).min()
        let years = span(from: since)
        let annualised = annualise(overall, overYears: years)
        let needed = totalInvested * (1 + target)

        return InvestmentMetrics(
            holdings: holdings,
            totalInvested: totalInvested,
            totalValue: totalValue,
            totalProfit: totalProfit,
            overallReturn: overall,
            annualisedReturn: annualised,
            trackedSince: since,
            years: years,
            target: target,
            meetsTarget: (annualised ?? overall).map { $0 >= target } ?? false,
            comparingAnnualised: annualised != nil,
            valueNeededForTarget: needed,
            amountToTarget: needed - totalValue,
            best: holdings.filter { $0.returnRate != nil }
                .max { ($0.returnRate ?? 0) < ($1.returnRate ?? 0) },
            worst: holdings.filter { $0.returnRate != nil }
                .min { ($0.returnRate ?? 0) < ($1.returnRate ?? 0) })
    }
}
