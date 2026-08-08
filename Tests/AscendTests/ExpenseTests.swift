import Testing
import Foundation
import SwiftData
@testable import Ascend

@MainActor
private func store(seeded: Bool = true) throws -> ModelContext {
    let schema = Schema([Account.self, AccountCategory.self, BalanceRecord.self,
                         BalanceEntry.self, AppSettings.self, Expense.self,
                         ExpenseCategory.self])
    let context = ModelContext(try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    if seeded { SeedData.seedIfNeeded(context) }
    return context
}

@MainActor
private func expenses(_ context: ModelContext) throws -> [Expense] {
    try context.fetch(FetchDescriptor<Expense>()).sorted { $0.sortOrder < $1.sortOrder }
}

// MARK: - Frequency normalisation

@Test func normalisesEachFrequencyToAMonthlyAmount() {
    let monthly = ExpenseInput(id: UUID(), name: "Phone", amount: 15, frequency: .monthly)
    let quarterly = ExpenseInput(id: UUID(), name: "Water", amount: 60, frequency: .quarterly)
    let yearly = ExpenseInput(id: UUID(), name: "Insurance", amount: 240, frequency: .yearly)

    #expect(abs(monthly.monthlyAmount - 15) < 0.000001)
    #expect(abs(quarterly.monthlyAmount - 20) < 0.000001)
    #expect(abs(yearly.monthlyAmount - 20) < 0.000001)
}

/// The yearly column: what twelve months of a commitment actually costs,
/// whatever its billing rhythm.
@Test func reportsAYearlyCostPerExpense() {
    let phone = ExpenseInput(id: UUID(), name: "Phone", amount: 15, frequency: .monthly)
    let water = ExpenseInput(id: UUID(), name: "Water", amount: 60, frequency: .quarterly)
    let insurance = ExpenseInput(id: UUID(), name: "Insurance", amount: 240, frequency: .yearly)

    #expect(abs(phone.yearlyAmount - 180) < 0.000001)
    #expect(abs(water.yearlyAmount - 240) < 0.000001)
    // A yearly bill costs exactly its own amount over a year.
    #expect(abs(insurance.yearlyAmount - 240) < 0.000001)
}

@Test func pausedExpensesCostNothingOverAYear() {
    let paused = ExpenseInput(id: UUID(), name: "Gym", amount: 30, isActive: false)
    #expect(paused.yearlyAmount == 0)
}

/// The column footer must agree with the hero figure above it.
@Test func yearlyColumnSumsToTheYearlyTotal() {
    let items = WorkbookFixture.expenses
    let metrics = ExpenseMetrics.compute(expenses: items, categoryNames: [:])
    let columnSum = items.reduce(0) { $0 + $1.yearlyAmount }
    #expect(abs(columnSum - metrics.yearlyTotal) < 0.000001)
    #expect(abs(metrics.yearlyTotal - 6000) < 0.005)
}

@Test func pausedExpensesStopCounting() {
    var expense = ExpenseInput(id: UUID(), name: "Gym", amount: 30)
    #expect(expense.monthlyAmount == 30)
    expense.isActive = false
    #expect(expense.monthlyAmount == 0)
}

// MARK: - Totals and grouping

@Test func totalsMonthlyAndYearly() {
    let items = [
        ExpenseInput(id: UUID(), name: "Rent", amount: 550),
        ExpenseInput(id: UUID(), name: "Insurance", amount: 240, frequency: .yearly),
        ExpenseInput(id: UUID(), name: "Paused", amount: 999, isActive: false),
    ]
    let metrics = ExpenseMetrics.compute(expenses: items, categoryNames: [:])
    #expect(abs(metrics.monthlyTotal - 570) < 0.000001)
    #expect(abs(metrics.yearlyTotal - 6840) < 0.000001)
    #expect(metrics.activeCount == 2)
    #expect(metrics.pausedCount == 1)
    #expect(metrics.largest?.name == "Rent")
}

@Test func groupsByCategoryWithSharesSummingToOne() {
    let housing = UUID(), transport = UUID()
    let items = [
        ExpenseInput(id: UUID(), name: "Rent", amount: 600, categoryID: housing),
        ExpenseInput(id: UUID(), name: "Insurance", amount: 1200, frequency: .yearly,
                     categoryID: housing),
        ExpenseInput(id: UUID(), name: "Pass", amount: 100, categoryID: transport),
    ]
    let metrics = ExpenseMetrics.compute(
        expenses: items,
        categoryNames: [housing: "Housing", transport: "Transport"],
        categoryOrder: [housing, transport])

    #expect(metrics.byCategory.count == 2)
    #expect(metrics.byCategory[0].name == "Housing")
    #expect(abs(metrics.byCategory[0].monthlyAmount - 700) < 0.000001)
    #expect(metrics.byCategory[0].count == 2)
    #expect(abs(metrics.byCategory.reduce(0) { $0 + $1.share } - 1.0) < 0.000001)
}

@Test func expensesWithNoCategoryLandInTheirOwnBucketLast() {
    let housing = UUID()
    let items = [
        ExpenseInput(id: UUID(), name: "Loose", amount: 40),
        ExpenseInput(id: UUID(), name: "Rent", amount: 500, categoryID: housing),
    ]
    let metrics = ExpenseMetrics.compute(expenses: items,
                                        categoryNames: [housing: "Housing"],
                                        categoryOrder: [housing])
    #expect(metrics.byCategory.last?.name == "Uncategorised")
    #expect(metrics.byCategory.last?.categoryID == nil)
}

// MARK: - The link to projections

/// The whole point: the expense list, not a typed field, decides what a month
/// costs in Projections.
@Test func portfolioExpensesDriveMaxMonthlyExpenses() {
    var input = WorkbookFixture.portfolio
    #expect(abs(input.maxMonthlyExpenses - 500) < 0.005)

    input.expenses.append(ExpenseInput(id: UUID(), name: "Gym", amount: 30))
    #expect(abs(input.maxMonthlyExpenses - 530) < 0.005)
}

@Test func addingAnExpenseReducesTheProjectedLeftover() {
    var input = WorkbookFixture.portfolio
    let before = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                          from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(before.assumptions.leftoverPerMonth - 1200) < 0.005)

    input.expenses.append(ExpenseInput(id: UUID(), name: "Gym", amount: 30))
    let after = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                         from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(after.assumptions.maxMonthlyExpenses - 530) < 0.005)
    #expect(abs(after.assumptions.leftoverPerMonth - 1170) < 0.005)
    // Less left over each month means the goal arrives no sooner.
    #expect((after.monthsToGoal ?? 0) >= (before.monthsToGoal ?? 0))
}

@Test func pausingAnExpenseFreesUpTheLeftover() {
    var input = WorkbookFixture.portfolio
    input.expenses = input.expenses.map { expense in
        var copy = expense
        if copy.id == WorkbookFixture.rentID { copy.isActive = false }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.maxMonthlyExpenses - 100) < 0.005)
    #expect(abs(p.assumptions.leftoverPerMonth - 1600) < 0.005)
}

@Test func noExpensesMeansAMonthCostsNothing() {
    var input = WorkbookFixture.portfolio
    input.expenses = []
    #expect(input.maxMonthlyExpenses == 0)
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.leftoverPerMonth - 1700) < 0.005)
}

// MARK: - Service

@MainActor
@Test func createsRenamesAndDeletesExpenses() throws {
    let context = try store()
    let before = try expenses(context).count
    let gym = try ExpenseService.create(name: "Gym", amount: 30, in: context)
    #expect(try expenses(context).count == before + 1)

    try ExpenseService.rename(gym, to: "Climbing gym", in: context)
    #expect(gym.name == "Climbing gym")

    #expect(throws: ExpenseError.emptyName) {
        try ExpenseService.rename(gym, to: "   ", in: context)
    }

    ExpenseService.delete(gym, in: context)
    #expect(try expenses(context).count == before)
}

@MainActor
@Test func rejectsEmptyAndDuplicateCategoryNames() throws {
    let context = try store()
    #expect(throws: ExpenseError.emptyCategoryName) {
        _ = try ExpenseService.createCategory(name: " ", colorHex: "#123456", in: context)
    }
    #expect(throws: ExpenseError.duplicateCategoryName) {
        _ = try ExpenseService.createCategory(name: "housing", colorHex: "#123456", in: context)
    }
}

@MainActor
@Test func categoryInUseCannotBeDeleted() throws {
    let context = try store()
    let all = try context.fetch(FetchDescriptor<ExpenseCategory>())
    let housing = all.first { $0.name == "Housing" }!
    let inUse = ExpenseService.expensesUsing(housing, expenses: try expenses(context))
    #expect(inUse == 2)  // Rent and Home insurance
    #expect(throws: ExpenseError.categoryInUse(expenses: inUse)) {
        try ExpenseService.deleteCategory(housing, expenses: try expenses(context), in: context)
    }
}

@MainActor
@Test func unusedCategoryIsDeletedAndOrderClosesUp() throws {
    let context = try store()
    let spare = try ExpenseService.createCategory(name: "Spare", colorHex: "#123456",
                                                 in: context)
    try ExpenseService.deleteCategory(spare, expenses: try expenses(context), in: context)
    let remaining = try context.fetch(FetchDescriptor<ExpenseCategory>())
        .sorted { $0.sortOrder < $1.sortOrder }
    #expect(remaining.map(\.sortOrder) == Array(0..<remaining.count))
}

// MARK: - The paying account

/// A new expense is paid from the main account — the one receiving the monthly
/// leftover — unless told otherwise.
@MainActor
@Test func newExpensesDefaultToTheMainAccount() throws {
    let context = try store()
    let main = try context.fetch(FetchDescriptor<Account>())
        .first { $0.isLeftoverDestination }!

    let gym = try ExpenseService.create(name: "Gym", amount: 30, in: context)
    #expect(gym.accountID == main.id)
}

@MainActor
@Test func anExplicitPayingAccountWins() throws {
    let context = try store()
    let brokerage = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Brokerage" }!
    let gym = try ExpenseService.create(name: "Gym", amount: 30,
                                        accountID: brokerage.id, in: context)
    #expect(gym.accountID == brokerage.id)
}

@MainActor
@Test func reassigningThePayingAccount() throws {
    let context = try store()
    let gym = try ExpenseService.create(name: "Gym", amount: 30, in: context)
    let savings = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Savings" }!

    ExpenseService.assign(gym, toAccount: savings, in: context)
    #expect(gym.accountID == savings.id)

    ExpenseService.assign(gym, toAccount: nil, in: context)
    #expect(gym.accountID == nil)
}

/// With no leftover destination set, the default falls back rather than failing.
@MainActor
@Test func defaultAccountFallsBackToTheFirstActiveOne() throws {
    let context = try store()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    AccountService.setLeftoverDestination(nil, accounts: accounts)
    try context.save()

    let first = accounts.sorted { $0.sortOrder < $1.sortOrder }.first!
    #expect(ExpenseService.defaultAccountID(in: context) == first.id)
}

@MainActor
@Test func seededExpensesArePaidFromTheMainAccount() throws {
    let context = try store()
    let main = try context.fetch(FetchDescriptor<Account>())
        .first { $0.isLeftoverDestination }!
    #expect(try expenses(context).allSatisfy { $0.accountID == main.id })
}

@MainActor
@Test func migrationAssignsAPayingAccountToOlderExpenses() throws {
    let context = try store()
    let orphan = Expense(name: "Old expense", amount: 25, accountID: nil, sortOrder: 99)
    context.insert(orphan)
    try context.save()
    #expect(orphan.accountID == nil)

    SeedData.migrateExpenseAccounts(context)

    let main = try context.fetch(FetchDescriptor<Account>())
        .first { $0.isLeftoverDestination }!
    #expect(orphan.accountID == main.id)
}

/// Reassigning who pays cannot change what a month costs in total.
@Test func thePayingAccountDoesNotChangeTheMonthlyTotal() {
    var input = WorkbookFixture.portfolio
    let before = input.maxMonthlyExpenses
    input.expenses = input.expenses.map { expense in
        var copy = expense
        copy.accountID = WorkbookFixture.brokerageID
        return copy
    }
    #expect(abs(input.maxMonthlyExpenses - before) < 0.000001)
}

// MARK: - The paying account in projections

private func projected(_ input: PortfolioInput) -> Projection {
    ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                             from: WorkbookFixture.date(8, 8, 2026))
}

/// Moving an expense onto another account debits that account and leaves more
/// in the main one.
@Test func assigningAnExpenseShiftsItBetweenAccounts() {
    var input = WorkbookFixture.portfolio
    let before = projected(input).months[1]
    #expect(abs(before.balances[WorkbookFixture.currentID]! - 2700) < 0.01)
    #expect(abs(before.balances[WorkbookFixture.brokerageID]! - 853.41) < 0.01)

    // Put the 400 €/month rent on the brokerage instead of the main account.
    input.expenses = input.expenses.map { expense in
        var copy = expense
        if copy.id == WorkbookFixture.rentID { copy.accountID = WorkbookFixture.brokerageID }
        return copy
    }

    let after = projected(input).months[1]
    // Main keeps the 400 it no longer pays.
    #expect(abs(after.balances[WorkbookFixture.currentID]! - 3100) < 0.01)
    // The brokerage pays it instead.
    #expect(abs(after.balances[WorkbookFixture.brokerageID]! - 453.41) < 0.01)
}

/// In the first month, only the split moves — the same money leaves either way,
/// so net worth is untouched. This is the guard against double-deducting an
/// expense or losing one.
@Test func whoPaysLeavesTheFirstMonthsNetWorthUnchanged() {
    var input = WorkbookFixture.portfolio
    let baseline = projected(input).months[1].netWorth

    for target in [WorkbookFixture.brokerageID, WorkbookFixture.savingsID,
                   WorkbookFixture.mealCardID] {
        input.expenses = WorkbookFixture.expenses.map { expense in
            var copy = expense
            copy.accountID = target
            return copy
        }
        #expect(abs(projected(input).months[1].netWorth - baseline) < 0.01,
                "month 1 moved when paying from \(target)")
    }
}

/// Beyond month one it *should* diverge: money spent out of an account earning
/// 7 % stops compounding there, while the same money spent from a 0 % current
/// account costs no growth. Paying bills from investments is genuinely worse
/// long-term, and the forecast has to show that.
@Test func payingFromAnInvestmentAccountCostsFutureGrowth() {
    var fromMain = WorkbookFixture.portfolio
    fromMain.expenses = WorkbookFixture.expenses.map { expense in
        var copy = expense
        copy.accountID = WorkbookFixture.currentID  // 0 % current account
        return copy
    }

    var fromInvestment = WorkbookFixture.portfolio
    fromInvestment.expenses = WorkbookFixture.expenses.map { expense in
        var copy = expense
        copy.accountID = WorkbookFixture.brokerageID  // 7 % a year
        return copy
    }

    let mainPath = projected(fromMain)
    let investmentPath = projected(fromInvestment)

    // Identical at month 1, then the investment route falls behind.
    #expect(abs(mainPath.months[1].netWorth - investmentPath.months[1].netWorth) < 0.01)
    #expect(investmentPath.months[12].netWorth < mainPath.months[12].netWorth)
    #expect(investmentPath.months[60].netWorth < mainPath.months[60].netWorth)

    // And the gap widens the longer it runs.
    let gapAtYear = mainPath.months[12].netWorth - investmentPath.months[12].netWorth
    let gapAtFive = mainPath.months[60].netWorth - investmentPath.months[60].netWorth
    #expect(gapAtFive > gapAtYear)
}

/// Paying from a flat, restricted account costs no growth, so it matches the
/// 0 % current account exactly.
@Test func payingFromTwoZeroGrowthAccountsGivesTheSamePath() {
    func path(payingFrom target: UUID) -> [Double] {
        var input = WorkbookFixture.portfolio
        input.expenses = WorkbookFixture.expenses.map { expense in
            var copy = expense
            copy.accountID = target
            return copy
        }
        return projected(input).months.map(\.netWorth)
    }

    let viaMain = path(payingFrom: WorkbookFixture.currentID)
    let viaRestricted = path(payingFrom: WorkbookFixture.mealCardID)
    for (index, value) in viaRestricted.enumerated() {
        #expect(abs(value - viaMain[index]) < 0.01, "month \(index) diverged")
    }
}

/// An expense pointing nowhere, or at an account that no longer exists, must
/// still be paid — otherwise the forecast quietly gains money.
@Test func unresolvedExpensesFallBackToTheMainAccount() {
    var input = WorkbookFixture.portfolio
    input.expenses = input.expenses.map { expense in
        var copy = expense
        copy.accountID = UUID()  // an account that is not in the portfolio
        return copy
    }
    let p = projected(input)
    #expect(abs(p.assumptions.unassignedMonthlyExpenses - 500) < 0.005)
    #expect(abs(p.assumptions.monthlyExpensesByAccount[WorkbookFixture.currentID]! - 500) < 0.005)
    #expect(abs(p.months[1].balances[WorkbookFixture.currentID]! - 2700) < 0.01)
}

@Test func reportsWhatEachAccountPays() {
    var input = WorkbookFixture.portfolio
    input.expenses = [
        ExpenseInput(id: UUID(), name: "Rent", amount: 180,
                     accountID: WorkbookFixture.currentID),
        ExpenseInput(id: UUID(), name: "Broker fee", amount: 12,
                     accountID: WorkbookFixture.brokerageID),
        ExpenseInput(id: UUID(), name: "Lunch", amount: 90,
                     accountID: WorkbookFixture.mealCardID),
    ]
    let byAccount = projected(input).assumptions.monthlyExpensesByAccount
    #expect(abs(byAccount[WorkbookFixture.currentID]! - 180) < 0.005)
    #expect(abs(byAccount[WorkbookFixture.brokerageID]! - 12) < 0.005)
    #expect(abs(byAccount[WorkbookFixture.mealCardID]! - 90) < 0.005)
    #expect(byAccount[WorkbookFixture.savingsID] == nil)
}

/// A restricted card that pays more than it receives goes negative, and the
/// forecast says so rather than clamping at zero.
@Test func anAccountPayingMoreThanItReceivesGoesNegative() {
    var input = WorkbookFixture.portfolio
    input.expenses = [
        ExpenseInput(id: UUID(), name: "Lunch", amount: 60,
                     accountID: WorkbookFixture.mealCardID),
    ]
    let p = projected(input)
    // The meal card starts at 100, receives nothing, and pays 60 a month.
    #expect(abs(p.months[1].balances[WorkbookFixture.mealCardID]! - 40) < 0.01)
    #expect(p.months[2].balances[WorkbookFixture.mealCardID]! < 0)
}

/// A paused expense is not debited from anyone.
@Test func pausedExpensesAreNotDebitedFromTheirAccount() {
    var input = WorkbookFixture.portfolio
    input.expenses = [
        ExpenseInput(id: UUID(), name: "Gym", amount: 40,
                     accountID: WorkbookFixture.brokerageID, isActive: false),
    ]
    let p = projected(input)
    #expect(p.assumptions.monthlyExpensesByAccount.isEmpty)
    #expect(abs(p.months[1].balances[WorkbookFixture.brokerageID]! - 853.41) < 0.01)
}

// MARK: - Seeding and migration

/// The seeded commitments must add up to the workbook's original figure, or the
/// PDF-fidelity assertions elsewhere would quietly drift.
@MainActor
@Test func seededExpensesTotalFiveHundredAMonth() throws {
    let context = try store()
    let metrics = ExpenseMetrics.compute(
        expenses: try expenses(context).map { $0.toInput() }, categoryNames: [:])
    #expect(abs(metrics.monthlyTotal - 500) < 0.005)
    #expect(try expenses(context).allSatisfy { $0.categoryID != nil })
}

/// A store predating the screen keeps its number: the old typed figure becomes
/// one expense of the same amount.
@MainActor
@Test func migrationTurnsTheOldTypedFigureIntoOneExpense() throws {
    let context = try store(seeded: false)
    context.insert(AppSettings(targetNetWorth: 10_000, monthlyNetIncome: 2_000,
                               maxMonthlyExpenses: 340, projectionHorizonMonths: 60))
    try context.save()

    SeedData.migrateExpenses(context)

    let migrated = try expenses(context)
    #expect(migrated.count == 1)
    #expect(abs(migrated[0].amount - 340) < 0.005)
    #expect(migrated[0].frequency == .monthly)
    #expect(migrated[0].categoryID != nil)

    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context),
        expenses: migrated)
    #expect(abs(input.maxMonthlyExpenses - 340) < 0.005)
}

@MainActor
@Test func migrationDoesNotDuplicateOnASecondRun() throws {
    let context = try store()
    let before = try expenses(context).count
    SeedData.migrateExpenses(context)
    SeedData.migrateExpenses(context)
    #expect(try expenses(context).count == before)
}

// MARK: - Backup

@MainActor
@Test func backupRoundTripsExpensesAndTheirCategories() throws {
    let source = try store()
    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source),
        categories: try source.fetch(FetchDescriptor<AccountCategory>()),
        expenses: try source.fetch(FetchDescriptor<Expense>()),
        expenseCategories: try source.fetch(FetchDescriptor<ExpenseCategory>()))

    let target = try store(seeded: false)
    try BackupService.restore(from: data, into: target)

    let restored = try expenses(target)
    #expect(restored.count == 4)
    #expect(restored.allSatisfy { $0.accountID != nil })
    #expect(restored.contains { $0.frequency == .yearly })
    #expect(try target.fetch(FetchDescriptor<ExpenseCategory>()).count == 6)

    let metrics = ExpenseMetrics.compute(expenses: restored.map { $0.toInput() },
                                         categoryNames: [:])
    #expect(abs(metrics.monthlyTotal - 500) < 0.005)
}
