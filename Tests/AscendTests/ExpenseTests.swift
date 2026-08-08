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
    #expect(abs(input.maxMonthlyExpenses - 200) < 0.005)

    input.expenses.append(ExpenseInput(id: UUID(), name: "Gym", amount: 30))
    #expect(abs(input.maxMonthlyExpenses - 230) < 0.005)
}

@Test func addingAnExpenseReducesTheProjectedLeftover() {
    var input = WorkbookFixture.portfolio
    let before = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                          from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(before.assumptions.leftoverPerMonth - 717) < 0.005)

    input.expenses.append(ExpenseInput(id: UUID(), name: "Gym", amount: 30))
    let after = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                         from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(after.assumptions.maxMonthlyExpenses - 230) < 0.005)
    #expect(abs(after.assumptions.leftoverPerMonth - 687) < 0.005)
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
    #expect(abs(p.assumptions.maxMonthlyExpenses - 20) < 0.005)
    #expect(abs(p.assumptions.leftoverPerMonth - 897) < 0.005)
}

@Test func noExpensesMeansAMonthCostsNothing() {
    var input = WorkbookFixture.portfolio
    input.expenses = []
    #expect(input.maxMonthlyExpenses == 0)
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.leftoverPerMonth - 917) < 0.005)
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

// MARK: - Seeding and migration

/// The seeded commitments must add up to the workbook's original figure, or the
/// PDF-fidelity assertions elsewhere would quietly drift.
@MainActor
@Test func seededExpensesTotalTheOriginalTwoHundred() throws {
    let context = try store()
    let metrics = ExpenseMetrics.compute(
        expenses: try expenses(context).map { $0.toInput() }, categoryNames: [:])
    #expect(abs(metrics.monthlyTotal - 200) < 0.005)
    #expect(try expenses(context).allSatisfy { $0.categoryID != nil })
}

/// A store predating the screen keeps its number: the old typed figure becomes
/// one expense of the same amount.
@MainActor
@Test func migrationTurnsTheOldTypedFigureIntoOneExpense() throws {
    let context = try store(seeded: false)
    context.insert(AppSettings(targetNetWorth: 25_000, monthlyNetIncome: 1_117,
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
    #expect(restored.count == 6)
    #expect(restored.contains { $0.frequency == .yearly })
    #expect(try target.fetch(FetchDescriptor<ExpenseCategory>()).count == 6)

    let metrics = ExpenseMetrics.compute(expenses: restored.map { $0.toInput() },
                                         categoryNames: [:])
    #expect(abs(metrics.monthlyTotal - 200) < 0.005)
}
