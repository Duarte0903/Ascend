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
                        target: Double) -> InvestmentMetrics {
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
                                     years: span(from: since))
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
