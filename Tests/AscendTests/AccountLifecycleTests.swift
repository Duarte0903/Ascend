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
    _ = try AccountService.create(name: "Trade Republic", kind: .investment,
                                  colorHex: "#00838F", in: context)
    #expect(abs(try netWorth(context) - before) < 0.005)
}

@MainActor
@Test func newAccountsReadAsZeroInExistingRecords() throws {
    let context = try seededContext()
    let account = try AccountService.create(name: "Trade Republic", kind: .investment,
                                            colorHex: "#00838F", in: context)
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(records.allSatisfy { $0.amount(for: account.id) == 0 })
}

@MainActor
@Test func createdAccountsInheritTypeDefaults() throws {
    let context = try seededContext()
    let restricted = try AccountService.create(name: "Meal card", kind: .restricted,
                                               colorHex: "#AD1457", in: context)
    #expect(restricted.includeInUsable == false)
    #expect(restricted.countsAsSavings == false)

    let savings = try AccountService.create(name: "Emergency", kind: .savings,
                                            colorHex: "#00695C", in: context)
    #expect(savings.includeInUsable == true)
    #expect(savings.countsAsSavings == true)
}

@MainActor
@Test func rejectsEmptyAndDuplicateNames() throws {
    let context = try seededContext()
    #expect(throws: AccountError.emptyName) {
        _ = try AccountService.create(name: "  ", kind: .main, colorHex: "#000000", in: context)
    }
    #expect(throws: AccountError.duplicateName) {
        _ = try AccountService.create(name: "revolut", kind: .savings,
                                      colorHex: "#000000", in: context)
    }
}

@MainActor
@Test func archivingPreservesHistoricalTotals() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let edenred = accounts.first { $0.name == "Edenred" }!
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    let settings = SeedData.settings(in: context)
    let before = LedgerEngine.derive(
        PortfolioStore.historicalInput(accounts: accounts, records: records,
                                       settings: settings)).last!.total

    try AccountService.archive(edenred, in: context)

    let after = LedgerEngine.derive(
        PortfolioStore.historicalInput(
            accounts: try context.fetch(FetchDescriptor<Account>()),
            records: try context.fetch(FetchDescriptor<BalanceRecord>()),
            settings: settings)).last!.total
    #expect(abs(after - before) < 0.005)
    #expect(edenred.isArchived)
    #expect(edenred.archivedAt != nil)
}

@MainActor
@Test func cannotArchiveTheLeftoverDestination() throws {
    let context = try seededContext()
    let ctt = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Banco CTT" }!
    #expect(throws: AccountError.cannotArchiveLeftoverDestination) {
        try AccountService.archive(ctt, in: context)
    }
}

@MainActor
@Test func cannotArchiveTheLastActiveAccount() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let ctt = accounts.first { $0.name == "Banco CTT" }!
    AccountService.setLeftoverDestination(nil, accounts: accounts)
    for account in accounts where account.id != ctt.id {
        try AccountService.archive(account, in: context)
    }
    #expect(throws: AccountError.cannotArchiveLastAccount) {
        try AccountService.archive(ctt, in: context)
    }
}

@MainActor
@Test func leftoverDestinationIsExclusive() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let revolut = accounts.first { $0.name == "Revolut" }!
    AccountService.setLeftoverDestination(revolut, accounts: accounts)
    #expect(accounts.filter(\.isLeftoverDestination).count == 1)
    #expect(revolut.isLeftoverDestination)
}

@MainActor
@Test func togglingIncludeInUsableFlowsThroughToEveryRecord() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    accounts.first { $0.name == "Edenred" }!.includeInUsable = true
    let input = PortfolioStore.input(
        accounts: accounts,
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    let derived = LedgerEngine.derive(input)
    #expect(abs(derived.last!.usable - 8409.74) < 0.005)
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
    let revolut = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Revolut" }!
    #expect(throws: AccountError.duplicateName) {
        try AccountService.rename(revolut, to: "XTB", in: context)
    }
    try AccountService.rename(revolut, to: "Revolut", in: context)
    #expect(revolut.name == "Revolut")
    try AccountService.rename(revolut, to: "Revolut Savings", in: context)
    #expect(revolut.name == "Revolut Savings")
}

@MainActor
@Test func movingAnAccountReordersColumnsWithoutGaps() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let xtb = accounts.first { $0.name == "XTB" }!

    AccountService.move(xtb, by: -1, accounts: accounts, in: context)

    let order = try context.fetch(FetchDescriptor<Account>())
        .sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
    #expect(order == ["Banco CTT", "XTB", "Revolut", "Edenred"])
    #expect(order.indices.allSatisfy { index in
        try! context.fetch(FetchDescriptor<Account>())
            .sorted { $0.sortOrder < $1.sortOrder }[index].sortOrder == index
    })
}

@MainActor
@Test func movingBeyondTheEndsIsRefused() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let first = accounts.first { $0.name == "Banco CTT" }!
    let last = accounts.first { $0.name == "Edenred" }!

    #expect(AccountService.canMove(first, by: -1, accounts: accounts) == false)
    #expect(AccountService.canMove(last, by: 1, accounts: accounts) == false)

    AccountService.move(first, by: -1, accounts: accounts, in: context)
    let order = try context.fetch(FetchDescriptor<Account>())
        .sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
    #expect(order == ["Banco CTT", "Revolut", "XTB", "Edenred"])
}

@MainActor
@Test func reorderingDoesNotChangeAnyDerivedNumber() throws {
    let context = try seededContext()
    let before = try netWorth(context)
    let accounts = try context.fetch(FetchDescriptor<Account>())
    AccountService.move(accounts.first { $0.name == "Edenred" }!, by: -1,
                        accounts: accounts, in: context)
    #expect(abs(try netWorth(context) - before) < 0.005)

    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    #expect(abs(LedgerEngine.derive(input).last!.usable - 8132.11) < 0.005)
}

@MainActor
@Test func hardDeleteRemovesTheAccountAndItsEntries() throws {
    let context = try seededContext()
    let edenred = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Edenred" }!
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(AccountService.affectedRecordCount(for: edenred, records: records) == 5)

    AccountService.delete(edenred, records: records, in: context)

    #expect(try context.fetch(FetchDescriptor<Account>()).count == 3)
    let after = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(after.allSatisfy { $0.amount(for: edenred.id) == 0 })
    let input = PortfolioStore.input(accounts: try context.fetch(FetchDescriptor<Account>()),
                                     records: after, settings: SeedData.settings(in: context))
    #expect(abs(LedgerEngine.derive(input).last!.total - 8132.11) < 0.005)
}
