import Testing
import Foundation
import SwiftData
@testable import Ascend

@MainActor
func inMemoryContext() throws -> ModelContext {
    let schema = Schema([Account.self, AccountCategory.self, BalanceRecord.self, BalanceEntry.self, AppSettings.self])
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
    #expect(records.count == 5)
    #expect(accounts.filter(\.isLeftoverDestination).count == 1)
    #expect(accounts.first { $0.name == "Edenred" }?.includeInUsable == false)
    #expect(accounts.first { $0.name == "XTB" }?.countsAsSavings == true)
}

@MainActor
@Test func seedingIsIdempotent() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    SeedData.seedIfNeeded(context)
    #expect(try context.fetch(FetchDescriptor<Account>()).count == 4)
}

@MainActor
@Test func seededDataReproducesTheWorkbookNumbers() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))

    let derived = LedgerEngine.derive(input)
    let metrics = DashboardMetrics.compute(records: derived)
    #expect(abs(metrics.currentNetWorth! - 8409.74) < 0.005)
    #expect(abs(metrics.usableCash! - 8132.11) < 0.005)
    #expect(abs(metrics.averageChange! - 236.1825) < 0.005)
    #expect(abs(metrics.averageSavingsRate! - 0.008642763) < 0.0000001)
    #expect(abs(derived[4].savingsRate! - 0.0278704688) < 0.0000001)
}

@MainActor
@Test func seededProjectionReachesTheGoalInEighteenMonths() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    let projection = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                              from: Date())
    #expect(projection.monthsToGoal == 18)
    #expect(abs(projection.assumptions.leftoverPerMonth - 717) < 0.01)
}
