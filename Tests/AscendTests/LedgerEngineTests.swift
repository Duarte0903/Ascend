import Testing
import Foundation
@testable import Ascend

private let tol = 0.005

@Test func derivesTotalsForEverySampleRecord() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(d.count == 4)
    let expected: [Double] = [2100, 2200, 2500, 3100]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i].total - e) < tol, "record \(i + 1) total")
    }
}

@Test func usableExcludesRestrictedAccounts() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let expected: [Double] = [2000, 2100, 2400, 3000]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i].usable - e) < tol, "record \(i + 1) usable")
    }
}

@Test func firstRecordHasNoChangeOrSavingsRate() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(d[0].changeAmount == nil)
    #expect(d[0].changePercent == nil)
    #expect(d[0].savingsRate == nil)
}

@Test func derivesChangeAmounts() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let expected: [Double] = [100, 300, 600]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i + 1].changeAmount! - e) < tol, "record \(i + 2) change")
    }
}

@Test func derivesChangePercent() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    // 600 on a previous total of 2 500.
    #expect(abs(d[3].changePercent! - 0.24) < 0.00001)
}

/// The least obvious formula: the increase in savings-flagged accounts, over
/// the PREVIOUS total. Record 4: (100 + 100) / 2 500 = 8 %.
@Test func savingsRateUsesSavingsAccountDeltaOverPreviousTotal() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(abs(d[1].savingsRate! - 0.0) < 0.0000001)
    #expect(abs(d[2].savingsRate! - 0.13636364) < 0.0000001)
    #expect(abs(d[3].savingsRate! - 0.08) < 0.0000001)
}

@Test func percentagesAreNilWhenPreviousTotalIsZero() {
    let a = WorkbookFixture.accounts[0]
    let input = PortfolioInput(
        accounts: [a],
        records: [
            RecordInput(id: UUID(), date: WorkbookFixture.date(1, 1, 2026), balances: [a.id: 0]),
            RecordInput(id: UUID(), date: WorkbookFixture.date(2, 1, 2026), balances: [a.id: 100]),
        ],
        targetNetWorth: 1000, monthlyNetIncome: 0, projectionHorizonMonths: 12)
    let d = LedgerEngine.derive(input)
    #expect(d[1].changeAmount == 100)
    #expect(d[1].changePercent == nil)
    #expect(d[1].savingsRate == nil)
}

@Test func recordsAreSortedOldestFirstRegardlessOfInputOrder() {
    var input = WorkbookFixture.portfolio
    input.records = input.records.reversed()
    let d = LedgerEngine.derive(input)
    #expect(abs(d[0].total - 2100) < tol)
    #expect(abs(d[3].total - 3100) < tol)
}

@Test func missingBalanceEntriesReadAsZero() {
    var input = WorkbookFixture.portfolio
    input.records = [RecordInput(id: UUID(), date: WorkbookFixture.date(1, 3, 2026),
                                 balances: [WorkbookFixture.currentID: 100])]
    let d = LedgerEngine.derive(input)
    #expect(d[0].total == 100)
}
