import Testing
import Foundation
@testable import Ascend

private let tol = 0.005

@Test func derivesTotalsForEveryWorkbookRecord() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(d.count == 5)
    let expected = [7465.01, 7465.01, 7495.01, 7495.03, 8409.74]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i].total - e) < tol, "record \(i + 1) total")
    }
}

@Test func usableExcludesRestrictedAccounts() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let expected = [7196.58, 7196.58, 7226.58, 7226.60, 8132.11]
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
    let expected: [Double] = [0.00, 30.00, 0.02, 914.71]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i + 1].changeAmount! - e) < tol, "record \(i + 2) change")
    }
}

@Test func derivesChangePercent() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(abs(d[4].changePercent! - 0.1220427) < 0.00001)
}

/// The workbook's least obvious formula: the increase in savings-flagged
/// accounts, over the PREVIOUS total. Record 5: (100.25 + 108.64) / 7495.03.
@Test func savingsRateUsesSavingsAccountDeltaOverPreviousTotal() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(abs(d[1].savingsRate! - 0.0066979147) < 0.0000001)
    #expect(abs(d[2].savingsRate! - 0.0) < 0.0000001)
    #expect(abs(d[4].savingsRate! - 0.0278704688) < 0.0000001)
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
    #expect(abs(d[0].total - 7465.01) < tol)
    #expect(abs(d[4].total - 8409.74) < tol)
}

/// Two records share 01/07/2026; the one created first must come first, or the
/// change and savings-rate columns would flip.
@Test func sameDateRecordsKeepCreationOrder() {
    var input = WorkbookFixture.portfolio
    input.records = input.records.reversed()
    let d = LedgerEngine.derive(input)
    #expect(abs(d[0].amount(for: WorkbookFixture.cttID) - 6285.73) < tol)
    #expect(abs(d[1].amount(for: WorkbookFixture.cttID) - 6235.73) < tol)
    #expect(abs(d[1].savingsRate! - 0.0066979147) < 0.0000001)
}

@Test func missingBalanceEntriesReadAsZero() {
    var input = WorkbookFixture.portfolio
    input.records = [RecordInput(id: UUID(), date: WorkbookFixture.date(1, 7, 2026),
                                 balances: [WorkbookFixture.cttID: 100])]
    let d = LedgerEngine.derive(input)
    #expect(d[0].total == 100)
}
