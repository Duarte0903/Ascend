import Testing
@testable import Ascend

private let tol = 0.005

@Test func computesAllNineDashboardKPIs() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let m = DashboardMetrics.compute(records: d)
    #expect(abs(m.currentNetWorth! - 3100) < tol)
    #expect(abs(m.usableCash! - 3000) < tol)
    #expect(abs(m.latestChangeAmount! - 600) < tol)
    #expect(abs(m.latestChangePercent! - 0.24) < 0.00001)
    #expect(abs(m.totalGrowth! - 1000) < tol)
    #expect(abs(m.bestChange! - 600) < tol)
    #expect(abs(m.averageChange! - 333.3333333) < tol)
    #expect(m.recordCount == 4)
    #expect(abs(m.averageSavingsRate! - 0.0721212121) < 0.0000001)
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
    #expect(abs(m.currentNetWorth! - 2100) < tol)
    #expect(m.totalGrowth! == 0)
    #expect(m.averageChange == nil)
    #expect(m.bestChange == nil)
    #expect(m.recordCount == 1)
}
