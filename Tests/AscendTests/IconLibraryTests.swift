import Testing
import Foundation
import SwiftData
import AppKit
@testable import Ascend

@MainActor
private func store() throws -> ModelContext {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    return context
}

@MainActor
private func account(_ context: ModelContext, _ name: String) throws -> Account {
    try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.name == name })
}

private func image(_ colour: NSColor) -> Data {
    let image = NSImage(size: NSSize(width: 120, height: 120))
    image.lockFocus()
    colour.setFill()
    NSRect(x: 0, y: 0, width: 120, height: 120).fill()
    image.unlockFocus()
    return AccountIconStyle.thumbnailData(from: image)!
}

@MainActor
@Test func libraryIsEmptyWhenNoAccountHasAnImage() throws {
    let context = try store()
    #expect(AccountService.iconLibrary(
        accounts: try context.fetch(FetchDescriptor<Account>())).isEmpty)
}

@MainActor
@Test func libraryListsEachDistinctImageOnce() throws {
    let context = try store()
    let logo = image(.systemBlue)
    let other = image(.systemOrange)

    try account(context, "Current Account").iconData = logo
    try account(context, "Savings").iconData = logo        // same bank
    try account(context, "Brokerage").iconData = other
    try context.save()

    let library = AccountService.iconLibrary(
        accounts: try context.fetch(FetchDescriptor<Account>()))
    #expect(library.count == 2, "the shared logo should collapse into one entry")
}

/// The picker says which accounts already use an image, so reusing one is an
/// informed choice.
@MainActor
@Test func libraryNamesTheAccountsUsingEachImage() throws {
    let context = try store()
    let logo = image(.systemBlue)
    try account(context, "Current Account").iconData = logo
    try account(context, "Savings").iconData = logo
    try context.save()

    let library = AccountService.iconLibrary(
        accounts: try context.fetch(FetchDescriptor<Account>()))
    let entry = try #require(library.first)
    #expect(entry.usedBy == ["Current Account", "Savings"])
}

@MainActor
@Test func libraryFollowsAccountOrder() throws {
    let context = try store()
    try account(context, "Brokerage").iconData = image(.systemOrange)
    try account(context, "Current Account").iconData = image(.systemBlue)
    try context.save()

    let library = AccountService.iconLibrary(
        accounts: try context.fetch(FetchDescriptor<Account>()))
    // Current Account sorts first, so its image leads.
    #expect(library.first?.usedBy == ["Current Account"])
    #expect(library.last?.usedBy == ["Brokerage"])
}

@MainActor
@Test func reusingAnImageGivesTheAccountItsOwnCopy() throws {
    let context = try store()
    let source = try account(context, "Current Account")
    let target = try account(context, "Savings")
    source.iconData = image(.systemBlue)
    try context.save()

    AccountService.reuseIcon(try #require(source.iconData), for: target, in: context)
    #expect(target.iconData == source.iconData)

    // Copies, not a shared reference: clearing one leaves the other intact.
    AccountService.clearIcon(for: source, in: context)
    #expect(source.iconData == nil)
    #expect(target.iconData != nil)
}

/// Deleting an account cannot blank another account's icon.
@MainActor
@Test func deletingAnAccountLeavesAReusedImageAlone() throws {
    let context = try store()
    let source = try account(context, "Brokerage")
    let target = try account(context, "Savings")
    source.iconData = image(.systemBlue)
    try context.save()
    AccountService.reuseIcon(try #require(source.iconData), for: target, in: context)

    AccountService.delete(source, records: try context.fetch(FetchDescriptor<BalanceRecord>()),
                          in: context)
    #expect(try account(context, "Savings").iconData != nil)
}

/// Importing the same file twice must produce identical bytes, or the library
/// would show visual duplicates.
@Test func theSameSourceImageAlwaysEncodesIdentically() {
    let first = image(.systemPink)
    let second = image(.systemPink)
    #expect(first == second)
}
