import Foundation

struct ProjectionAssumptions: Sendable {
    var monthlyNetIncome: Double
    var maxMonthlyExpenses: Double
    /// Sum of every account's monthly contribution — derived, never typed.
    var totalInvestedPerMonth: Double
    /// income - expenses - contributions — derived, never typed.
    var leftoverPerMonth: Double
    /// (income - expenses) / income — derived, never typed.
    var savingsRateOfIncome: Double
    var horizonMonths: Int
    var hasLeftoverDestination: Bool
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
        let totalInvested = accounts.reduce(0) { $0 + $1.monthlyContribution }
        let leftover = input.monthlyNetIncome - input.maxMonthlyExpenses - totalInvested
        let leftoverID = accounts.first(where: \.isLeftoverDestination)?.id

        let assumptions = ProjectionAssumptions(
            monthlyNetIncome: input.monthlyNetIncome,
            maxMonthlyExpenses: input.maxMonthlyExpenses,
            totalInvestedPerMonth: totalInvested,
            leftoverPerMonth: leftover,
            savingsRateOfIncome: input.monthlyNetIncome == 0
                ? 0
                : (input.monthlyNetIncome - input.maxMonthlyExpenses) / input.monthlyNetIncome,
            horizonMonths: input.projectionHorizonMonths,
            hasLeftoverDestination: leftoverID != nil)

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

        if input.projectionHorizonMonths >= 1 {
            for month in 1...input.projectionHorizonMonths {
                for account in accounts {
                    let monthlyGrowth = pow(1 + account.expectedAnnualReturn, 1.0 / 12.0)
                    var value = (balances[account.id] ?? 0) * monthlyGrowth
                    value += account.monthlyContribution
                    if account.id == leftoverID { value += leftover }
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
