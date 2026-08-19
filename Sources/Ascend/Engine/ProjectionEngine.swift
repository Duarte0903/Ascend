import Foundation

struct ProjectionAssumptions: Sendable {
    var monthlyNetIncome: Double
    /// True when income came from the tax estimate rather than being typed, so
    /// screens can show it as worked out instead of offering a dead edit.
    var derivesNetIncome: Bool = false
    var maxMonthlyExpenses: Double
    /// Sum of every account's monthly contribution — derived, never typed.
    var totalInvestedPerMonth: Double
    /// income - expenses - contributions — derived, never typed.
    var leftoverPerMonth: Double
    /// (income - expenses) / income — derived, never typed.
    var savingsRateOfIncome: Double
    var horizonMonths: Int
    var hasLeftoverDestination: Bool
    /// What each account pays out per month, after resolving every expense to
    /// the account responsible for it.
    var monthlyExpensesByAccount: [UUID: Double]
    /// Expenses whose account is missing or archived, and so fall back to the
    /// leftover destination.
    var unassignedMonthlyExpenses: Double
}

struct ProjectionMonth: Identifiable, Sendable {
    var id: Int { month }
    let month: Int
    let date: Date
    let balances: [UUID: Double]
    let netWorth: Double
    let usable: Double
}

struct Projection: Sendable {
    var assumptions: ProjectionAssumptions
    var months: [ProjectionMonth]
    var monthsToGoal: Int?

    func netWorth(atMonth month: Int) -> Double? {
        months.first { $0.month == month }?.netWorth
    }
}

enum ProjectionEngine {
    /// Compounds each account at its own annual rate, monthly, then adds its
    /// fixed contribution. The leftover destination additionally receives
    /// income - expenses - contributions.
    static func project(_ input: PortfolioInput,
                        records: [DerivedRecord],
                        from startDate: Date) -> Projection {
        let accounts = input.activeAccountsSorted

        // Only accounts that hold spendable or saved money count as investing
        // your income. A contribution to an account that is neither — a
        // food-only card, say — is funded from outside your salary, so it must
        // not be deducted from it, or the leftover would be understated.
        let fundedFromIncome = accounts.filter { $0.includeInUsable || $0.countsAsSavings }
        let totalInvested = fundedFromIncome.reduce(0) { $0 + $1.monthlyContribution }
        let leftover = input.monthlyNetIncome - input.maxMonthlyExpenses - totalInvested
        let leftoverID = accounts.first(where: \.isLeftoverDestination)?.id

        // Each expense is debited from the account that pays it. Anything
        // pointing at a missing or archived account falls back to the leftover
        // destination, so no expense can quietly go unpaid and inflate the
        // forecast.
        let knownIDs = Set(accounts.map(\.id))
        var expensesByAccount: [UUID: Double] = [:]
        var unassigned: Double = 0
        for expense in input.expenses where expense.isActive {
            let resolved = expense.accountID.flatMap { knownIDs.contains($0) ? $0 : nil }
            if resolved == nil { unassigned += expense.monthlyAmount }
            if let target = resolved ?? leftoverID {
                expensesByAccount[target, default: 0] += expense.monthlyAmount
            }
        }

        let assumptions = ProjectionAssumptions(
            monthlyNetIncome: input.monthlyNetIncome,
            derivesNetIncome: input.derivesNetIncome,
            maxMonthlyExpenses: input.maxMonthlyExpenses,
            totalInvestedPerMonth: totalInvested,
            leftoverPerMonth: leftover,
            savingsRateOfIncome: input.monthlyNetIncome == 0
                ? 0
                : (input.monthlyNetIncome - input.maxMonthlyExpenses) / input.monthlyNetIncome,
            horizonMonths: input.projectionHorizonMonths,
            hasLeftoverDestination: leftoverID != nil,
            monthlyExpensesByAccount: expensesByAccount,
            unassignedMonthlyExpenses: unassigned)

        guard let latest = records.last else {
            return Projection(assumptions: assumptions, months: [], monthsToGoal: nil)
        }

        let usableIDs = Set(accounts.filter(\.includeInUsable).map(\.id))
        let calendar = Calendar(identifier: .gregorian)

        func snapshot(month: Int, balances: [UUID: Double]) -> ProjectionMonth {
            let netWorth = balances.values.reduce(0, +)
            let usable = balances.filter { usableIDs.contains($0.key) }.values.reduce(0, +)
            let date = calendar.date(byAdding: .month, value: month, to: startDate) ?? startDate
            return ProjectionMonth(month: month, date: date, balances: balances,
                                   netWorth: netWorth, usable: usable)
        }

        var balances = Dictionary(uniqueKeysWithValues:
            accounts.map { ($0.id, latest.amount(for: $0.id)) })
        var months = [snapshot(month: 0, balances: balances)]
        var monthsToGoal: Int? = months[0].netWorth >= input.targetNetWorth ? 0 : nil

        // Income lands in the leftover destination, less what is transferred out
        // as contributions. Expenses are deliberately *not* deducted here —
        // each account pays its own below, and taking them off twice would
        // understate every month.
        let surplusToDestination = input.monthlyNetIncome - totalInvested

        if input.projectionHorizonMonths >= 1 {
            for month in 1...input.projectionHorizonMonths {
                for account in accounts {
                    let monthlyGrowth = pow(1 + account.expectedAnnualReturn, 1.0 / 12.0)
                    var value = (balances[account.id] ?? 0) * monthlyGrowth
                    value += account.monthlyContribution
                    if account.id == leftoverID { value += surplusToDestination }
                    value -= expensesByAccount[account.id] ?? 0
                    balances[account.id] = value
                }
                let snap = snapshot(month: month, balances: balances)
                months.append(snap)
                if monthsToGoal == nil, snap.netWorth >= input.targetNetWorth {
                    monthsToGoal = month
                }
            }
        }

        return Projection(assumptions: assumptions, months: months, monthsToGoal: monthsToGoal)
    }
}
