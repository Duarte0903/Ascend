import Testing
import Foundation
import SwiftData
@testable import Ascend

@MainActor
private func store() throws -> ModelContext {
    let schema = Schema([Account.self, AccountCategory.self, BalanceRecord.self,
                         BalanceEntry.self, AppSettings.self])
    let context = ModelContext(try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    SeedData.seedIfNeeded(context)
    return context
}

@MainActor
private func categories(_ context: ModelContext) throws -> [AccountCategory] {
    try context.fetch(FetchDescriptor<AccountCategory>()).sorted { $0.sortOrder < $1.sortOrder }
}

@MainActor
@Test func seedingCreatesTheFourOriginalTypes() throws {
    let context = try store()
    #expect(try categories(context).map(\.name) == ["Main", "Savings", "Investment", "Restricted"])
    #expect(try categories(context).first { $0.name == "Restricted" }?.defaultIncludeInUsable == false)
    #expect(try categories(context).first { $0.name == "Savings" }?.defaultCountsAsSavings == true)
}

@MainActor
@Test func everySeededAccountIsAssignedAType() throws {
    let context = try store()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    #expect(accounts.allSatisfy { $0.categoryID != nil })
}

@MainActor
@Test func createsACustomType() throws {
    let context = try store()
    let crypto = try AccountService.createCategory(
        name: "Crypto", includeInUsable: true, countsAsSavings: true,
        annualReturn: 0.15, in: context)
    #expect(crypto.sortOrder == 4)
    #expect(try categories(context).count == 5)
}

@MainActor
@Test func rejectsEmptyAndDuplicateTypeNames() throws {
    let context = try store()
    #expect(throws: AccountError.emptyCategoryName) {
        _ = try AccountService.createCategory(name: "   ", includeInUsable: true,
                                             countsAsSavings: false, in: context)
    }
    #expect(throws: AccountError.duplicateCategoryName) {
        _ = try AccountService.createCategory(name: "savings", includeInUsable: true,
                                             countsAsSavings: false, in: context)
    }
}

/// A new account inherits its type's defaults at creation.
@MainActor
@Test func newAccountsInheritTypeDefaults() throws {
    let context = try store()
    let crypto = try AccountService.createCategory(
        name: "Crypto", includeInUsable: false, countsAsSavings: true,
        annualReturn: 0.15, in: context)

    let account = try AccountService.create(name: "Kraken", category: crypto,
                                            colorHex: "#123456", in: context)
    #expect(account.includeInUsable == false)
    #expect(account.countsAsSavings == true)
    #expect(abs(account.expectedAnnualReturn - 0.15) < 0.000001)
    #expect(account.categoryID == crypto.id)
}

/// …and then owns them. Editing the type later must not rewrite the account,
/// or a flag change would silently alter historical Usable and Savings Rate.
@MainActor
@Test func editingATypeDoesNotRewriteExistingAccounts() throws {
    let context = try store()
    let crypto = try AccountService.createCategory(
        name: "Crypto", includeInUsable: true, countsAsSavings: true, in: context)
    let account = try AccountService.create(name: "Kraken", category: crypto,
                                            colorHex: "#123456", in: context)

    crypto.defaultIncludeInUsable = false
    crypto.defaultCountsAsSavings = false

    #expect(account.includeInUsable == true)
    #expect(account.countsAsSavings == true)
}

@MainActor
@Test func typeInUseCannotBeDeleted() throws {
    let context = try store()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let investment = try categories(context).first { $0.name == "Investment" }!
    #expect(AccountService.accountsUsing(investment, accounts: accounts) == 1)
    #expect(throws: AccountError.categoryInUse(accounts: 1)) {
        try AccountService.deleteCategory(investment, accounts: accounts, in: context)
    }
}

@MainActor
@Test func unusedTypeIsDeletedAndOrderClosesUp() throws {
    let context = try store()
    let spare = try AccountService.createCategory(
        name: "Spare", includeInUsable: true, countsAsSavings: false, in: context)
    try AccountService.deleteCategory(spare, accounts: try context.fetch(FetchDescriptor<Account>()),
                                      in: context)
    let remaining = try categories(context)
    #expect(remaining.count == 4)
    #expect(remaining.map(\.sortOrder) == [0, 1, 2, 3])
}

@MainActor
@Test func reassigningATypeLeavesDerivedNumbersUntouched() throws {
    let context = try store()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    let settings = SeedData.settings(in: context)
    let before = LedgerEngine.derive(
        PortfolioStore.input(accounts: accounts, records: records, settings: settings)).last!

    let main = try categories(context).first { $0.name == "Main" }!
    AccountService.assign(accounts.first { $0.name == "XTB" }!, to: main, in: context)

    let after = LedgerEngine.derive(
        PortfolioStore.input(accounts: try context.fetch(FetchDescriptor<Account>()),
                             records: records, settings: settings)).last!
    #expect(abs(after.total - before.total) < 0.005)
    #expect(abs(after.usable - before.usable) < 0.005)
    #expect(abs(after.savingsRate! - before.savingsRate!) < 0.0000001)
}

/// Accounts written before categories existed must land on the right type.
@MainActor
@Test func migrationAssignsTypesFromTheOldKindField() throws {
    let schema = Schema([Account.self, AccountCategory.self, BalanceRecord.self,
                         BalanceEntry.self, AppSettings.self])
    let context = ModelContext(try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

    // A store as it would have looked before this change: no categories, and
    // accounts carrying only the legacy kind string.
    let legacy = Account(name: "Old Card", categoryID: nil, legacyKind: "restricted",
                         colorHex: "#A34A5E", sortOrder: 0,
                         includeInUsable: false, countsAsSavings: false)
    context.insert(legacy)
    try context.save()

    SeedData.migrateCategories(context)

    let assigned = try context.fetch(FetchDescriptor<AccountCategory>())
        .first { $0.id == legacy.categoryID }
    #expect(assigned?.name == "Restricted")
}

@MainActor
@Test func migrationIsIdempotent() throws {
    let context = try store()
    SeedData.migrateCategories(context)
    SeedData.migrateCategories(context)
    #expect(try categories(context).count == 4)
}

@MainActor
@Test func descriptionsPersistAndSeedWithMeaning() throws {
    let context = try store()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    #expect(accounts.allSatisfy { !$0.note.isEmpty })

    let edenred = accounts.first { $0.name == "Edenred" }!
    #expect(edenred.note.contains("Food only") || edenred.note.contains("food only"))

    edenred.note = "Updated note"
    try context.save()
    #expect(try context.fetch(FetchDescriptor<Account>())
        .first { $0.name == "Edenred" }?.note == "Updated note")
}

@MainActor
@Test func backupRoundTripsCategoriesAndDescriptions() throws {
    let source = try store()
    _ = try AccountService.createCategory(name: "Crypto", includeInUsable: true,
                                         countsAsSavings: true, annualReturn: 0.15, in: source)
    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source),
        categories: try source.fetch(FetchDescriptor<AccountCategory>()))

    let schema = Schema([Account.self, AccountCategory.self, BalanceRecord.self,
                         BalanceEntry.self, AppSettings.self])
    let target = ModelContext(try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    try BackupService.restore(from: data, into: target)

    #expect(try target.fetch(FetchDescriptor<AccountCategory>()).count == 5)
    #expect(try target.fetch(FetchDescriptor<AccountCategory>())
        .first { $0.name == "Crypto" }?.defaultAnnualReturn == 0.15)

    let restored = try target.fetch(FetchDescriptor<Account>())
    #expect(restored.first { $0.name == "XTB" }?.note.isEmpty == false)
    #expect(restored.allSatisfy { $0.categoryID != nil })
}
