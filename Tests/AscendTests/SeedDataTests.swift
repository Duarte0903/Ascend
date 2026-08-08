import Testing
import Foundation
import SwiftData
@testable import Ascend

@MainActor
func inMemoryContext() throws -> ModelContext {
    let schema = Schema([Account.self, AccountCategory.self, BalanceRecord.self, BalanceEntry.self,
                         AppSettings.self, Expense.self, ExpenseCategory.self])
    let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
}

@MainActor
@Test func seedingCreatesTheWorkbookContents() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)

    let accounts = try context.fetch(FetchDescriptor<Account>())
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(accounts.count == 4)
    #expect(records.count == 4)
    #expect(accounts.filter(\.isLeftoverDestination).count == 1)
    #expect(accounts.first { $0.name == "Meal Card" }?.includeInUsable == false)
    #expect(accounts.first { $0.name == "Brokerage" }?.countsAsSavings == true)
}

@MainActor
@Test func seedingIsIdempotent() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    SeedData.seedIfNeeded(context)
    #expect(try context.fetch(FetchDescriptor<Account>()).count == 4)
}

@MainActor
@Test func seededDataReproducesTheSampleNumbers() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context),
        expenses: try context.fetch(FetchDescriptor<Expense>()))

    let derived = LedgerEngine.derive(input)
    let metrics = DashboardMetrics.compute(records: derived)
    #expect(abs(metrics.currentNetWorth! - 3100) < 0.005)
    #expect(abs(metrics.usableCash! - 3000) < 0.005)
    #expect(abs(metrics.averageChange! - 333.3333333) < 0.005)
    #expect(abs(metrics.averageSavingsRate! - 0.0721212121) < 0.0000001)
    #expect(abs(derived[3].savingsRate! - 0.08) < 0.0000001)
}

@MainActor
@Test func seededProjectionReachesTheGoalInFiveMonths() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context),
        expenses: try context.fetch(FetchDescriptor<Expense>()))
    let projection = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                              from: Date())
    #expect(projection.monthsToGoal == 5)
    #expect(abs(projection.assumptions.leftoverPerMonth - 1200) < 0.01)
}
