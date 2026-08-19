import Foundation
import SwiftData
import Testing
@testable import Ascend

/// Exercises the parts that touch the filesystem: separate store files, what a
/// new profile is filled with, and whether edits survive a relaunch.
@MainActor
@Suite("Profile store")
struct ProfileStoreTests {

    /// A throwaway directory per test, so nothing here can see or damage the
    /// real profiles in Application Support.
    private func temporaryRoot() -> URL {
        let url = URL.temporaryDirectory.appending(path: "AscendTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func accountNames(in container: ModelContainer) -> [String] {
        let context = ModelContext(container)
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        return accounts.map(\.name).sorted()
    }

    @Test("A fresh install starts on one empty profile")
    func firstLaunch() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        #expect(store.registry.profiles.count == 1)
        #expect(accountNames(in: store.container).isEmpty)
    }

    @Test("Renaming a profile survives a relaunch")
    func renamePersists() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        store.rename(store.registry.activeID, to: "Household")
        #expect(store.registry.active.name == "Household")

        // A second store reads the same directory, exactly as a relaunch would.
        let reopened = ProfileStore(root: root)
        #expect(reopened.registry.active.name == "Household")
    }

    @Test("Colour and symbol changes survive a relaunch")
    func appearancePersists() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        store.setAppearance(store.registry.activeID, colorHex: "#A34A5E", symbol: "house.fill")

        let reopened = ProfileStore(root: root)
        #expect(reopened.registry.active.colorHex == "#A34A5E")
        #expect(reopened.registry.active.symbol == "house.fill")
    }

    @Test("A new empty profile really is empty, and becomes the open one")
    func createEmpty() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        store.create(name: "Work", colorHex: "#1F6E8C", symbol: "briefcase.fill", content: .empty)

        #expect(store.registry.profiles.count == 2)
        #expect(store.registry.active.name == "Work")
        #expect(accountNames(in: store.container).isEmpty)
        #expect(store.lastError == nil)
    }

    @Test("A sample profile arrives with accounts in it")
    func createWithSample() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        store.create(name: "Demo", colorHex: "#1F6E8C", symbol: "star.fill", content: .sample)
        #expect(!accountNames(in: store.container).isEmpty)
    }

    @Test("Copying a profile duplicates its accounts without linking them")
    func copyIsIndependent() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        store.create(name: "Source", colorHex: "#1F6E8C", symbol: "star.fill", content: .sample)
        let original = accountNames(in: store.container)
        let sourceID = store.registry.activeID

        store.create(name: "Copy", colorHex: "#7A5EA6", symbol: "leaf.fill", content: .copyOfCurrent)
        #expect(accountNames(in: store.container) == original)

        // Editing the copy must leave the source alone.
        let context = ModelContext(store.container)
        if let first = (try? context.fetch(FetchDescriptor<Account>()))?.first {
            first.name = "Renamed In Copy"
            try? context.save()
        }
        store.activate(sourceID)
        #expect(accountNames(in: store.container) == original)
    }

    @Test("Switching profiles swaps which accounts are visible")
    func switchingSwapsData() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        let emptyID = store.registry.activeID
        store.create(name: "Full", colorHex: "#1F6E8C", symbol: "star.fill", content: .sample)
        #expect(!accountNames(in: store.container).isEmpty)

        store.activate(emptyID)
        #expect(accountNames(in: store.container).isEmpty)
    }

    @Test("Deleting a profile removes its store file")
    func deleteRemovesFiles() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        store.create(name: "Doomed", colorHex: "#1F6E8C", symbol: "star.fill", content: .empty)
        let doomed = store.registry.active
        let file = root.appending(path: "Profiles").appending(path: doomed.fileName)
        #expect(FileManager.default.fileExists(atPath: file.path))

        store.delete(doomed.id)
        #expect(store.registry.profiles.count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Metadata survives a relaunch, and drives the currency symbol")
    func metadataPersists() {
        let root = temporaryRoot()
        defer {
            Money.symbol = Money.defaultSymbol
            try? FileManager.default.removeItem(at: root)
        }

        let store = ProfileStore(root: root)
        store.update(store.registry.activeID) {
            $0.note = "Household books"
            $0.ownerName = "Alex"
            $0.currencySymbol = "£"
        }
        #expect(Money.symbol == "£")
        #expect(Money.currency(1000).hasSuffix("£"))

        let reopened = ProfileStore(root: root)
        #expect(reopened.registry.active.note == "Household books")
        #expect(reopened.registry.active.ownerName == "Alex")
        #expect(reopened.registry.active.currencySymbol == "£")
    }

    @Test("Switching profiles switches the currency with it")
    func currencyFollowsProfile() {
        let root = temporaryRoot()
        defer {
            Money.symbol = Money.defaultSymbol
            try? FileManager.default.removeItem(at: root)
        }

        let store = ProfileStore(root: root)
        let euro = store.registry.activeID
        store.create(name: "UK", colorHex: "#1F6E8C", symbol: "star.fill", content: .empty)
        store.update(store.registry.activeID) { $0.currencySymbol = "£" }
        #expect(Money.symbol == "£")

        store.activate(euro)
        #expect(Money.symbol == Money.defaultSymbol)
    }

    @Test("The only profile cannot be deleted, and says so")
    func lastProfileProtected() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(root: root)
        store.delete(store.registry.activeID)
        #expect(store.registry.profiles.count == 1)
        #expect(store.lastError != nil)
    }
}
