import Testing
import Foundation
import SwiftData
@testable import Ascend

@MainActor
@Test func exportThenRestoreRoundTripsEveryNumber() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source))

    let target = try inMemoryContext()
    try BackupService.restore(from: data, into: target)

    let input = PortfolioStore.input(
        accounts: try target.fetch(FetchDescriptor<Account>()),
        records: try target.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: target))
    let derived = LedgerEngine.derive(input)
    let metrics = DashboardMetrics.compute(records: derived)
    #expect(abs(metrics.currentNetWorth! - 3100) < 0.005)
    #expect(abs(metrics.averageSavingsRate! - 0.0721212121) < 0.0000001)
    #expect(try target.fetch(FetchDescriptor<Account>()).count == 4)
}

/// createdAt must survive the round trip, or the two records sharing
/// 01/07/2026 could swap and change the savings-rate column.
@MainActor
@Test func restorePreservesSameDateRecordOrder() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source))

    let target = try inMemoryContext()
    try BackupService.restore(from: data, into: target)
    let input = PortfolioStore.input(
        accounts: try target.fetch(FetchDescriptor<Account>()),
        records: try target.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: target))
    let derived = LedgerEngine.derive(input)
    #expect(abs(derived[0].total - 2100) < 0.005)
    #expect(abs(derived[1].changeAmount! - 100) < 0.0000001)
    #expect(abs(derived[3].savingsRate! - 0.08) < 0.0000001)
}

@MainActor
@Test func restoreReplacesExistingData() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source))

    let target = try inMemoryContext()
    SeedData.seedIfNeeded(target)
    _ = try AccountService.create(name: "Extra", category: nil,
                                  colorHex: "#123456", in: target)
    try BackupService.restore(from: data, into: target)
    #expect(try target.fetch(FetchDescriptor<Account>()).count == 4)
    #expect(try target.fetch(FetchDescriptor<BalanceRecord>()).count == 4)
}

@MainActor
@Test func backupPreservesAccountFlagsAndArchivedState() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    let mealCard = try source.fetch(FetchDescriptor<Account>()).first { $0.name == "Meal Card" }!
    try AccountService.archive(mealCard, in: source)

    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source))

    let target = try inMemoryContext()
    try BackupService.restore(from: data, into: target)
    let restored = try target.fetch(FetchDescriptor<Account>())
    #expect(restored.first { $0.name == "Meal Card" }?.isArchived == true)
    #expect(restored.first { $0.name == "Meal Card" }?.includeInUsable == false)
    #expect(restored.first { $0.name == "Brokerage" }?.expectedAnnualReturn == 0.06)
    #expect(restored.filter(\.isLeftoverDestination).count == 1)
    #expect(SeedData.settings(in: target).monthlyNetIncome == 2_000)
}

/// Side hustles and their earnings must survive export and import, or
/// duplicating a profile — which goes through the same format — would lose
/// the money they have recorded.
@Suite("Backups carry side hustles")
struct SideHustleBackupTests {
    @MainActor
    private func store() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ProfileStore.schema, configurations: config)
        return ModelContext(container)
    }

    @MainActor
    @Test("A hustle and its earnings come back as they went in")
    func roundTrip() throws {
        let context = try store()
        let hustle = try SideHustleService.create(name: "Freelance",
                                                  activity: .otherServices,
                                                  in: context)
        hustle.contributions = .charged
        hustle.monthsActive = 7
        let when = Calendar.current.date(from: DateComponents(year: 2026, month: 3,
                                                              day: 5, hour: 12))!
        try SideHustleService.record(amount: 1_234.56, on: when, note: "Logo",
                                     isPaid: false, for: hustle, in: context)

        let data = try BackupService.export(
            accounts: [], records: [], settings: SeedData.settings(in: context),
            sideHustles: SideHustleService.all(in: context))

        let restored = try store()
        try BackupService.restore(from: data, into: restored)
        let back = SideHustleService.all(in: restored)

        #expect(back.count == 1)
        #expect(back.first?.name == "Freelance")
        #expect(back.first?.activity == .otherServices)
        #expect(back.first?.contributions == .charged)
        #expect(back.first?.monthsActive == 7)
        #expect(back.first?.earnings?.count == 1)
        #expect(back.first?.earnings?.first?.amount == 1_234.56)
        #expect(back.first?.earnings?.first?.note == "Logo")
        #expect(back.first?.earnings?.first?.isPaid == false)
    }

    @MainActor
    @Test("A backup written before the screen existed still imports")
    func olderBackups() throws {
        let context = try store()
        let data = try BackupService.export(
            accounts: [], records: [], settings: SeedData.settings(in: context))
        // Strip the key entirely, the way a version 5 file has it.
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "sideHustles")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let restored = try store()
        try BackupService.restore(from: stripped, into: restored)
        #expect(SideHustleService.all(in: restored).isEmpty)
    }

    @MainActor
    @Test("Restoring replaces what was there rather than adding to it")
    func restoreReplaces() throws {
        let context = try store()
        try SideHustleService.create(name: "Old", in: context)
        let empty = try BackupService.export(
            accounts: [], records: [], settings: SeedData.settings(in: context),
            sideHustles: [])
        try BackupService.restore(from: empty, into: context)
        #expect(SideHustleService.all(in: context).isEmpty)
    }
}
