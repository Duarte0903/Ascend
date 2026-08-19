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
    /// What Projections was told to assume, used whenever tax is switched off.
    var typedMonthlyNetIncome: Double
    /// Present once the Tax screen is on, and then it wins.
    var tax: TaxInput?
    var projectionHorizonMonths: Int
    /// The combined return the tracked investments are aiming to beat.
    var investmentReturnTarget: Double

    init(accounts: [AccountInfo], records: [RecordInput],
         expenses: [ExpenseInput] = [],
         targetNetWorth: Double, monthlyNetIncome: Double,
         projectionHorizonMonths: Int,
         investmentReturnTarget: Double = 0.03,
         tax: TaxInput? = nil) {
        self.accounts = accounts
        self.records = records
        self.expenses = expenses
        self.targetNetWorth = targetNetWorth
        self.typedMonthlyNetIncome = monthlyNetIncome
        self.tax = tax
        self.projectionHorizonMonths = projectionHorizonMonths
        self.investmentReturnTarget = investmentReturnTarget
    }

    /// Derived from the expense list, never typed — the Expenses screen is the
    /// single source of truth for what a month costs.
    var maxMonthlyExpenses: Double {
        expenses.reduce(0) { $0 + $1.monthlyAmount }
    }

    /// Worked out from the salary once the Tax screen is on, exactly as
    /// expenses are worked out from the Expenses screen, and typed only while
    /// it is off. Spread over twelve months rather than the fourteen payments,
    /// because a month's budget is a month's budget.
    var monthlyNetIncome: Double {
        guard let tax else { return typedMonthlyNetIncome }
        // The budget figure, not the total: it is already spendable-only — a
        // meal card cannot pay rent — and already on whichever basis was asked
        // for, withholding or assessment.
        return TaxEngine.assess(tax).budgetMonthlyIncome
    }

    /// Whether the figure above is calculated rather than typed, so screens can
    /// show it as derived instead of offering an edit that would be ignored.
    var derivesNetIncome: Bool { tax != nil }

    var activeAccountsSorted: [AccountInfo] {
        accounts.sorted { $0.sortOrder < $1.sortOrder }
    }
}
