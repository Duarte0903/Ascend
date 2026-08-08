import Testing
@testable import FinanceTracker

private let tol = 0.005

@Test func computesAllNineDashboardKPIs() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let m = DashboardMetrics.compute(records: d)
    #expect(abs(m.currentNetWorth! - 8409.74) < tol)
    #expect(abs(m.usableCash! - 8132.11) < tol)
    #expect(abs(m.latestChangeAmount! - 914.71) < tol)
    #expect(abs(m.latestChangePercent! - 0.1220427) < 0.00001)
    #expect(abs(m.totalGrowth! - 944.73) < tol)
    #expect(abs(m.bestChange! - 914.71) < tol)
    #expect(abs(m.averageChange! - 236.1825) < tol)
    #expect(m.recordCount == 5)
    #expect(abs(m.averageSavingsRate! - 0.008642763) < 0.0000001)
}

@Test func emptyPortfolioYieldsUndefinedKPIs() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let m = DashboardMetrics.compute(records: LedgerEngine.derive(input))
    #expect(m.currentNetWorth == nil)
    #expect(m.averageChange == nil)
    #expect(m.recordCount == 0)
}

@Test func singleRecordHasNetWorthButNoChangeStatistics() {
    var input = WorkbookFixture.portfolio
    input.records = [WorkbookFixture.records[0]]
    let m = DashboardMetrics.compute(records: LedgerEngine.derive(input))
    #expect(abs(m.currentNetWorth! - 7465.01) < tol)
    #expect(m.totalGrowth! == 0)
    #expect(m.averageChange == nil)
    #expect(m.bestChange == nil)
    #expect(m.recordCount == 1)
}
