import Testing
import Foundation
import SwiftData
@testable import Ascend

@MainActor
private func seededContext() throws -> ModelContext {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    return context
}

@MainActor
func category(_ name: String, in context: ModelContext) -> AccountCategory? {
    (try? context.fetch(FetchDescriptor<AccountCategory>()))?.first { $0.name == name }
}

@MainActor
private func netWorth(_ context: ModelContext) throws -> Double {
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    return LedgerEngine.derive(input).last?.total ?? 0
}

@MainActor
@Test func addingAnAccountLeavesHistoricalTotalsUnchanged() throws {
    let context = try seededContext()
    let before = try netWorth(context)
    _ = try AccountService.create(name: "Pension", category: category("Investment", in: context),
                                  colorHex: "#00838F", in: context)
    #expect(abs(try netWorth(context) - before) < 0.005)
}

@MainActor
@Test func newAccountsReadAsZeroInExistingRecords() throws {
    let context = try seededContext()
    let account = try AccountService.create(name: "Pension", category: category("Investment", in: context),
                                            colorHex: "#00838F", in: context)
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(records.allSatisfy { $0.amount(for: account.id) == 0 })
}

@MainActor
@Test func createdAccountsInheritTypeDefaults() throws {
    let context = try seededContext()
    let restricted = try AccountService.create(name: "Lunch card", category: category("Restricted", in: context),
                                               colorHex: "#AD1457", in: context)
    #expect(restricted.includeInUsable == false)
    #expect(restricted.countsAsSavings == false)

    let savings = try AccountService.create(name: "Emergency", category: category("Savings", in: context),
                                            colorHex: "#00695C", in: context)
    #expect(savings.includeInUsable == true)
    #expect(savings.countsAsSavings == true)
}

@MainActor
@Test func rejectsEmptyAndDuplicateNames() throws {
    let context = try seededContext()
    #expect(throws: AccountError.emptyName) {
        _ = try AccountService.create(name: "  ", category: nil, colorHex: "#000000", in: context)
    }
    #expect(throws: AccountError.duplicateName) {
        _ = try AccountService.create(name: "savings", category: nil,
                                      colorHex: "#000000", in: context)
    }
}

@MainActor
@Test func archivingPreservesHistoricalTotals() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let mealCard = accounts.first { $0.name == "Meal Card" }!
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    let settings = SeedData.settings(in: context)
    let before = LedgerEngine.derive(
        PortfolioStore.historicalInput(accounts: accounts, records: records,
                                       settings: settings)).last!.total

    try AccountService.archive(mealCard, in: context)

    let after = LedgerEngine.derive(
        PortfolioStore.historicalInput(
            accounts: try context.fetch(FetchDescriptor<Account>()),
            records: try context.fetch(FetchDescriptor<BalanceRecord>()),
            settings: settings)).last!.total
    #expect(abs(after - before) < 0.005)
    #expect(mealCard.isArchived)
    #expect(mealCard.archivedAt != nil)
}

@MainActor
@Test func cannotArchiveTheLeftoverDestination() throws {
    let context = try seededContext()
    let current = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Current Account" }!
    #expect(throws: AccountError.cannotArchiveLeftoverDestination) {
        try AccountService.archive(current, in: context)
    }
}

@MainActor
@Test func cannotArchiveTheLastActiveAccount() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let current = accounts.first { $0.name == "Current Account" }!
    AccountService.setLeftoverDestination(nil, accounts: accounts)
    for account in accounts where account.id != current.id {
        try AccountService.archive(account, in: context)
    }
    #expect(throws: AccountError.cannotArchiveLastAccount) {
        try AccountService.archive(current, in: context)
    }
}

@MainActor
@Test func leftoverDestinationIsExclusive() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let savings = accounts.first { $0.name == "Savings" }!
    AccountService.setLeftoverDestination(savings, accounts: accounts)
    #expect(accounts.filter(\.isLeftoverDestination).count == 1)
    #expect(savings.isLeftoverDestination)
}

@MainActor
@Test func togglingIncludeInUsableFlowsThroughToEveryRecord() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    accounts.first { $0.name == "Meal Card" }!.includeInUsable = true
    let input = PortfolioStore.input(
        accounts: accounts,
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    let derived = LedgerEngine.derive(input)
    #expect(abs(derived.last!.usable - 3100) < 0.005)
}

@MainActor
@Test func togglingCountsAsSavingsFlowsThroughToSavingsRate() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    for account in accounts { account.countsAsSavings = false }
    let input = PortfolioStore.input(
        accounts: accounts,
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    #expect(LedgerEngine.derive(input).last!.savingsRate == 0)
}

@MainActor
@Test func renamingRejectsCollisionsButAllowsSelf() throws {
    let context = try seededContext()
    let savings = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Savings" }!
    #expect(throws: AccountError.duplicateName) {
        try AccountService.rename(savings, to: "Brokerage", in: context)
    }
    try AccountService.rename(savings, to: "Savings", in: context)
    #expect(savings.name == "Savings")
    try AccountService.rename(savings, to: "Rainy Day", in: context)
    #expect(savings.name == "Rainy Day")
}

@MainActor
@Test func movingAnAccountReordersColumnsWithoutGaps() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let brokerage = accounts.first { $0.name == "Brokerage" }!

    AccountService.move(brokerage, by: -1, accounts: accounts, in: context)

    let order = try context.fetch(FetchDescriptor<Account>())
        .sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
    #expect(order == ["Current Account", "Brokerage", "Savings", "Meal Card"])
    #expect(order.indices.allSatisfy { index in
        try! context.fetch(FetchDescriptor<Account>())
            .sorted { $0.sortOrder < $1.sortOrder }[index].sortOrder == index
    })
}

@MainActor
@Test func movingBeyondTheEndsIsRefused() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let first = accounts.first { $0.name == "Current Account" }!
    let last = accounts.first { $0.name == "Meal Card" }!

    #expect(AccountService.canMove(first, by: -1, accounts: accounts) == false)
    #expect(AccountService.canMove(last, by: 1, accounts: accounts) == false)

    AccountService.move(first, by: -1, accounts: accounts, in: context)
    let order = try context.fetch(FetchDescriptor<Account>())
        .sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
    #expect(order == ["Current Account", "Savings", "Brokerage", "Meal Card"])
}

@MainActor
@Test func reorderingDoesNotChangeAnyDerivedNumber() throws {
    let context = try seededContext()
    let before = try netWorth(context)
    let accounts = try context.fetch(FetchDescriptor<Account>())
    AccountService.move(accounts.first { $0.name == "Meal Card" }!, by: -1,
                        accounts: accounts, in: context)
    #expect(abs(try netWorth(context) - before) < 0.005)

    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    #expect(abs(LedgerEngine.derive(input).last!.usable - 3000) < 0.005)
}

@MainActor
@Test func hardDeleteRemovesTheAccountAndItsEntries() throws {
    let context = try seededContext()
    let mealCard = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Meal Card" }!
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(AccountService.affectedRecordCount(for: mealCard, records: records) == 4)

    AccountService.delete(mealCard, records: records, in: context)

    #expect(try context.fetch(FetchDescriptor<Account>()).count == 3)
    let after = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(after.allSatisfy { $0.amount(for: mealCard.id) == 0 })
    let input = PortfolioStore.input(accounts: try context.fetch(FetchDescriptor<Account>()),
                                     records: after, settings: SeedData.settings(in: context))
    #expect(abs(LedgerEngine.derive(input).last!.total - 3000) < 0.005)
}
