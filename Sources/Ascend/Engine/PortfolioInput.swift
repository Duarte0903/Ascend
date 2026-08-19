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
    /// What has been put into this account, for measuring profit. Balances
    /// alone cannot separate growth from deposits.
    var amountInvested: Double
    /// Whether this account shows on the Investments screen.
    var investmentTracking: InvestmentTracking

    init(id: UUID, name: String, colorHex: String, sortOrder: Int,
         includeInUsable: Bool, countsAsSavings: Bool,
         expectedAnnualReturn: Double, monthlyContribution: Double,
         isLeftoverDestination: Bool, amountInvested: Double = 0,
         investmentTracking: InvestmentTracking = .auto) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.includeInUsable = includeInUsable
        self.countsAsSavings = countsAsSavings
        self.expectedAnnualReturn = expectedAnnualReturn
        self.monthlyContribution = monthlyContribution
        self.isLeftoverDestination = isLeftoverDestination
        self.amountInvested = amountInvested
        self.investmentTracking = investmentTracking
    }
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
    /// The combined return the tracked investments are aiming to beat.
    var investmentReturnTarget: Double

    init(accounts: [AccountInfo], records: [RecordInput],
         expenses: [ExpenseInput] = [],
         targetNetWorth: Double, monthlyNetIncome: Double,
         projectionHorizonMonths: Int,
         investmentReturnTarget: Double = 0.03) {
        self.accounts = accounts
        self.records = records
        self.expenses = expenses
        self.targetNetWorth = targetNetWorth
        self.monthlyNetIncome = monthlyNetIncome
        self.projectionHorizonMonths = projectionHorizonMonths
        self.investmentReturnTarget = investmentReturnTarget
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
