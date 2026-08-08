import Testing
import Foundation
import SwiftData
import AppKit
@testable import Ascend

// MARK: - The default symbol

/// Derived from the account's own flags, not its category name, so renaming or
/// inventing a type can never leave an account with a misleading icon.
@Test func defaultSymbolFollowsTheAccountsFlags() {
    #expect(AccountIconStyle.defaultSymbol(includeInUsable: true, countsAsSavings: false,
                                           expectedAnnualReturn: 0) == "building.columns")
    #expect(AccountIconStyle.defaultSymbol(includeInUsable: true, countsAsSavings: true,
                                           expectedAnnualReturn: 0) == "banknote")
    #expect(AccountIconStyle.defaultSymbol(includeInUsable: true, countsAsSavings: true,
                                           expectedAnnualReturn: 0.06) == "chart.line.uptrend.xyaxis")
    // Not spendable — a voucher or food card — regardless of anything else.
    #expect(AccountIconStyle.defaultSymbol(includeInUsable: false, countsAsSavings: false,
                                           expectedAnnualReturn: 0) == "creditcard")
    #expect(AccountIconStyle.defaultSymbol(includeInUsable: false, countsAsSavings: true,
                                           expectedAnnualReturn: 0.06) == "creditcard")
}

/// Every seeded account resolves to a symbol, so a fresh install never shows a
/// blank square.
@MainActor
@Test func everySeededAccountHasAnIcon() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    for account in try context.fetch(FetchDescriptor<Account>()) {
        #expect(account.iconData == nil, "seeded accounts ship without custom images")
        let symbol = AccountIconStyle.defaultSymbol(
            includeInUsable: account.includeInUsable,
            countsAsSavings: account.countsAsSavings,
            expectedAnnualReturn: account.expectedAnnualReturn)
        #expect(!symbol.isEmpty)
        #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                "\(symbol) is not a real system symbol")
    }
}

// MARK: - Downscaling

private func solidImage(width: Int, height: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
}

/// A dropped-in logo can be several megabytes; storing it raw would bloat the
/// store and every backup.
@Test func oversizedImagesAreDownscaled() throws {
    let data = try #require(AccountIconStyle.thumbnailData(from: solidImage(width: 2000,
                                                                           height: 1000)))
    let rep = try #require(NSBitmapImageRep(data: data))
    #expect(rep.pixelsWide == Int(AccountIconStyle.maximumPixelSize))
    #expect(rep.pixelsHigh == Int(AccountIconStyle.maximumPixelSize / 2))
    // A flat 2000×1000 PNG re-encoded small should be far under a megabyte.
    #expect(data.count < 200_000)
}

@Test func aspectRatioSurvivesDownscaling() throws {
    let data = try #require(AccountIconStyle.thumbnailData(from: solidImage(width: 600,
                                                                           height: 900)))
    let rep = try #require(NSBitmapImageRep(data: data))
    // The long edge hits the limit exactly; the short edge follows the ratio,
    // rounded to a whole pixel.
    #expect(rep.pixelsHigh == Int(AccountIconStyle.maximumPixelSize))
    let ratio = Double(rep.pixelsWide) / Double(rep.pixelsHigh)
    #expect(abs(ratio - 600.0 / 900.0) < 0.01)
}

/// Already-small images are left at their own size rather than being blown up.
@Test func smallImagesAreNotEnlarged() throws {
    let data = try #require(AccountIconStyle.thumbnailData(from: solidImage(width: 48,
                                                                           height: 48)))
    let rep = try #require(NSBitmapImageRep(data: data))
    #expect(rep.pixelsWide == 48)
    #expect(rep.pixelsHigh == 48)
}

@Test func aZeroSizedImageIsRejectedRatherThanCrashing() {
    #expect(AccountIconStyle.thumbnailData(from: NSImage(size: .zero)) == nil)
}

@Test func aNonImageFileIsRejected() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ascend-not-an-image-\(UUID().uuidString).txt")
    try "definitely not an image".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(AccountIconStyle.thumbnailData(fromFileAt: url) == nil)
}

// MARK: - Service and persistence

@MainActor
@Test func settingAnIconStoresADownscaledCopyAndClearingRestoresTheDefault() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let account = try #require(try context.fetch(FetchDescriptor<Account>())
        .first { $0.name == "Current Account" })

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ascend-icon-\(UUID().uuidString).png")
    let source = try #require(AccountIconStyle.thumbnailData(from: solidImage(width: 800,
                                                                             height: 800)))
    try source.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(AccountService.setIcon(fromFileAt: url, for: account, in: context))
    #expect(account.iconData != nil)

    AccountService.clearIcon(for: account, in: context)
    #expect(account.iconData == nil)
}

@MainActor
@Test func aNonImageFileLeavesTheAccountUnchanged() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let account = try #require(try context.fetch(FetchDescriptor<Account>()).first)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ascend-bad-\(UUID().uuidString).txt")
    try "nope".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(AccountService.setIcon(fromFileAt: url, for: account, in: context) == false)
    #expect(account.iconData == nil)
}

@MainActor
@Test func backupRoundTripsAccountIcons() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    let account = try #require(try source.fetch(FetchDescriptor<Account>())
        .first { $0.name == "Brokerage" })
    account.iconData = AccountIconStyle.thumbnailData(from: solidImage(width: 300, height: 300))
    try source.save()
    let originalCount = try #require(account.iconData?.count)

    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source),
        categories: try source.fetch(FetchDescriptor<AccountCategory>()),
        expenses: try source.fetch(FetchDescriptor<Expense>()),
        expenseCategories: try source.fetch(FetchDescriptor<ExpenseCategory>()))

    let target = try inMemoryContext()
    try BackupService.restore(from: data, into: target)

    let restored = try context(target, named: "Brokerage")
    #expect(restored.iconData?.count == originalCount)
    // Accounts without an icon stay without one rather than gaining an empty blob.
    let plain = try context(target, named: "Current Account")
    #expect(plain.iconData == nil)
}

@MainActor
private func context(_ context: ModelContext, named name: String) throws -> Account {
    try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.name == name })
}
