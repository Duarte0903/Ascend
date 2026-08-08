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
    #expect(abs(metrics.currentNetWorth! - 8409.74) < 0.005)
    #expect(abs(metrics.averageSavingsRate! - 0.008642763) < 0.0000001)
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
    #expect(abs(derived[0].total - 7465.01) < 0.005)
    #expect(abs(derived[1].savingsRate! - 0.0066979147) < 0.0000001)
    #expect(abs(derived[4].savingsRate! - 0.0278704688) < 0.0000001)
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
    #expect(try target.fetch(FetchDescriptor<BalanceRecord>()).count == 5)
}

@MainActor
@Test func backupPreservesAccountFlagsAndArchivedState() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    let edenred = try source.fetch(FetchDescriptor<Account>()).first { $0.name == "Edenred" }!
    try AccountService.archive(edenred, in: source)

    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source))

    let target = try inMemoryContext()
    try BackupService.restore(from: data, into: target)
    let restored = try target.fetch(FetchDescriptor<Account>())
    #expect(restored.first { $0.name == "Edenred" }?.isArchived == true)
    #expect(restored.first { $0.name == "Edenred" }?.includeInUsable == false)
    #expect(restored.first { $0.name == "XTB" }?.expectedAnnualReturn == 0.07)
    #expect(restored.filter(\.isLeftoverDestination).count == 1)
    #expect(SeedData.settings(in: target).monthlyNetIncome == 1_117)
}
