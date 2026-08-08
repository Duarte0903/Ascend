import Foundation

/// What the engine needs to know about an account. Category and description are
/// presentation concerns and deliberately absent — no derived figure depends on
/// them, so they stay out of the calculation layer.
struct AccountInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
    var includeInUsable: Bool
    var countsAsSavings: Bool
    var expectedAnnualReturn: Double
    var monthlyContribution: Double
    var isLeftoverDestination: Bool
}

struct RecordInput: Identifiable, Hashable, Sendable {
    let id: UUID
    var date: Date
    /// Tiebreaker when two records share a date — the workbook has two rows on
    /// 01/07/2026, and their order decides the change and savings-rate columns.
    var createdAt: Date
    /// Missing entries read as 0.
    var balances: [UUID: Double]

    init(id: UUID, date: Date, createdAt: Date = .distantPast, balances: [UUID: Double]) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.balances = balances
    }

    func amount(for accountID: UUID) -> Double { balances[accountID] ?? 0 }
}

struct PortfolioInput: Sendable {
    var accounts: [AccountInfo]
    var records: [RecordInput]
    var expenses: [ExpenseInput]
    var targetNetWorth: Double
    var monthlyNetIncome: Double
    var projectionHorizonMonths: Int

    init(accounts: [AccountInfo], records: [RecordInput],
         expenses: [ExpenseInput] = [],
         targetNetWorth: Double, monthlyNetIncome: Double,
         projectionHorizonMonths: Int) {
        self.accounts = accounts
        self.records = records
        self.expenses = expenses
        self.targetNetWorth = targetNetWorth
        self.monthlyNetIncome = monthlyNetIncome
        self.projectionHorizonMonths = projectionHorizonMonths
    }

    /// Derived from the expense list, never typed — the Expenses screen is the
    /// single source of truth for what a month costs.
    var maxMonthlyExpenses: Double {
        expenses.reduce(0) { $0 + $1.monthlyAmount }
    }

    var activeAccountsSorted: [AccountInfo] {
        accounts.sorted { $0.sortOrder < $1.sortOrder }
    }
}
