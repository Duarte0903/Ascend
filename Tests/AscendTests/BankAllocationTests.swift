import Foundation
import SwiftData
import Testing
@testable import Ascend

@Suite("Money by bank")
struct BankAllocationTests {

    private let ctt = BankInfo(id: UUID(), name: "Banco CTT", colorHex: "#1F6E8C", sortOrder: 0)
    private let novo = BankInfo(id: UUID(), name: "Novo Banco", colorHex: "#7A5EA6", sortOrder: 1)

    private func account(_ name: String, bank: BankInfo?, order: Int) -> AccountInfo {
        AccountInfo(id: UUID(), name: name, colorHex: "#1F6E8C", sortOrder: order,
                    includeInUsable: true, countsAsSavings: false,
                    expectedAnnualReturn: 0, monthlyContribution: 0,
                    isLeftoverDestination: false, bankID: bank?.id)
    }

    private func metrics(_ accounts: [AccountInfo], amounts: [Double],
                         banks: [BankInfo]) -> AllocationMetrics {
        let balances = Dictionary(uniqueKeysWithValues:
            zip(accounts.map(\.id), amounts))
        let input = PortfolioInput(
            accounts: accounts,
            records: [RecordInput(id: UUID(), date: Date(), createdAt: Date(),
                                  balances: balances)],
            targetNetWorth: 0, monthlyNetIncome: 0, projectionHorizonMonths: 1)
        return AllocationMetrics.compute(accounts: accounts,
                                         records: LedgerEngine.derive(input),
                                         banks: banks)
    }

    @Test("Accounts at the same bank are added together")
    func accountsGroupByBank() {
        let accounts = [account("Current", bank: ctt, order: 0),
                        account("Savings", bank: ctt, order: 1)]
        let result = metrics(accounts, amounts: [1_000, 500], banks: [ctt, novo])

        #expect(result.byBank.count == 1)
        #expect(result.byBank[0].name == "Banco CTT")
        #expect(result.byBank[0].amount == 1_500)
        #expect(result.byBank[0].accountCount == 2)
    }

    @Test("Each bank's share is of the whole, and they add up to it")
    func sharesAddUp() {
        let accounts = [account("A", bank: ctt, order: 0),
                        account("B", bank: novo, order: 1)]
        let result = metrics(accounts, amounts: [750, 250], banks: [ctt, novo])

        #expect(abs(result.byBank[0].share - 0.75) < 0.000_1)
        #expect(abs(result.byBank[1].share - 0.25) < 0.000_1)
        #expect(abs(result.byBank.reduce(0) { $0 + $1.amount } - result.total) < 0.000_1)
    }

    @Test("Accounts with no bank are gathered under one heading, last")
    func unbankedIsItsOwnGroup() {
        let accounts = [account("Broker", bank: nil, order: 0),
                        account("Current", bank: ctt, order: 1)]
        let result = metrics(accounts, amounts: [300, 700], banks: [ctt])

        #expect(result.byBank.map(\.name) == ["Banco CTT", "No bank"])
        #expect(result.byBank.last?.bankID == nil)
        #expect(result.byBank.last?.amount == 300)
    }

    @Test("With every account banked, there is no unbanked row")
    func noEmptyUnbankedRow() {
        let accounts = [account("Current", bank: ctt, order: 0)]
        let result = metrics(accounts, amounts: [1_000], banks: [ctt])
        #expect(result.byBank.count == 1)
        #expect(result.byBank.allSatisfy { $0.bankID != nil })
    }

    @Test("A bank holding nothing is left out rather than shown as zero")
    func unusedBankIsOmitted() {
        let accounts = [account("Current", bank: ctt, order: 0)]
        let result = metrics(accounts, amounts: [1_000], banks: [ctt, novo])
        #expect(result.byBank.map(\.name) == ["Banco CTT"])
    }

    @Test("Banks appear in their own order, not the accounts'")
    func banksKeepTheirOrder() {
        let accounts = [account("At Novo", bank: novo, order: 0),
                        account("At CTT", bank: ctt, order: 1)]
        let result = metrics(accounts, amounts: [100, 100], banks: [ctt, novo])
        #expect(result.byBank.map(\.name) == ["Banco CTT", "Novo Banco"])
    }

    @Test("An account pointing at a deleted bank counts as unbanked, not lost")
    func danglingBankIsNotLost() {
        let accounts = [account("Orphan", bank: novo, order: 0),
                        account("Current", bank: ctt, order: 1)]
        // Novo Banco is gone from the list, but its account still holds money.
        let result = metrics(accounts, amounts: [400, 600], banks: [ctt])

        #expect(result.byBank.map(\.name) == ["Banco CTT", "No bank"])
        #expect(abs(result.byBank.reduce(0) { $0 + $1.amount } - 1_000) < 0.000_1)
    }

    @Test("With no records at all there is nothing to group")
    func noRecords() {
        let result = AllocationMetrics.compute(accounts: [], records: [], banks: [ctt])
        #expect(result.byBank.isEmpty)
    }
}

@MainActor
@Suite("Managing banks")
struct BankServiceTests {

    private func context() throws -> ModelContext { try inMemoryContext() }

    @Test("A bank is created with a name and keeps its order")
    func createsInOrder() throws {
        let context = try context()
        let first = try BankService.create(name: "Banco CTT", colorHex: "#1F6E8C",
                                           in: context)
        let second = try BankService.create(name: "Novo Banco", colorHex: "#7A5EA6",
                                            in: context)
        #expect(first.sortOrder < second.sortOrder)
        #expect(BankService.all(in: context).map(\.name) == ["Banco CTT", "Novo Banco"])
    }

    @Test("A blank name is refused")
    func refusesBlankName() throws {
        let context = try context()
        #expect(throws: BankError.emptyName) {
            try BankService.create(name: "   ", colorHex: "#1F6E8C", in: context)
        }
    }

    @Test("A duplicate name is refused, whatever the casing")
    func refusesDuplicate() throws {
        let context = try context()
        try BankService.create(name: "Banco CTT", colorHex: "#1F6E8C", in: context)
        #expect(throws: BankError.duplicateName) {
            try BankService.create(name: "banco ctt", colorHex: "#7A5EA6", in: context)
        }
    }

    @Test("Renaming to another bank's name is refused, to itself is fine")
    func renaming() throws {
        let context = try context()
        let ctt = try BankService.create(name: "Banco CTT", colorHex: "#1F6E8C", in: context)
        try BankService.create(name: "Novo Banco", colorHex: "#7A5EA6", in: context)

        #expect(throws: BankError.duplicateName) {
            try BankService.rename(ctt, to: "Novo Banco", in: context)
        }
        try BankService.rename(ctt, to: "Banco CTT", in: context)
        #expect(ctt.name == "Banco CTT")
    }

    @Test("Deleting a bank keeps its accounts, simply unbanked")
    func deletingKeepsAccounts() throws {
        let context = try context()
        let bank = try BankService.create(name: "Banco CTT", colorHex: "#1F6E8C",
                                          in: context)
        let account = Account(name: "Current", colorHex: "#1F6E8C", sortOrder: 0,
                              includeInUsable: true, countsAsSavings: false)
        account.bankID = bank.id
        context.insert(account)
        try context.save()

        BankService.delete(bank, accounts: [account], in: context)
        #expect(account.bankID == nil)
        #expect(BankService.all(in: context).isEmpty)
        // The account itself is untouched.
        #expect(account.name == "Current")
    }

    @Test("The count of accounts at a bank ignores archived ones")
    func countIgnoresArchived() throws {
        let context = try context()
        let bank = try BankService.create(name: "Banco CTT", colorHex: "#1F6E8C",
                                          in: context)
        let live = Account(name: "Current", colorHex: "#1F6E8C", sortOrder: 0,
                           includeInUsable: true, countsAsSavings: false)
        let old = Account(name: "Closed", colorHex: "#1F6E8C", sortOrder: 1,
                          includeInUsable: true, countsAsSavings: false)
        live.bankID = bank.id
        old.bankID = bank.id
        old.isArchived = true
        context.insert(live); context.insert(old)
        try context.save()

        #expect(BankService.accountsAt(bank, accounts: [live, old]) == 1)
    }
}
