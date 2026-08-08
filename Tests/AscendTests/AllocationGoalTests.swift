import Testing
@testable import Ascend

private let tol = 0.005

@Test func allocationSplitsLatestRecordByAccount() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let a = AllocationMetrics.compute(accounts: WorkbookFixture.accounts, records: d)
    #expect(a.slices.count == 4)
    #expect(abs(a.total - 3100) < tol)
    #expect(abs(a.usable - 3000) < tol)

    let expected: [(String, Double, Double)] = [
        ("Current Account", 1500, 0.4838709677),
        ("Savings", 800, 0.2580645161),
        ("Brokerage", 700, 0.2258064516),
        ("Meal Card", 100, 0.0322580645),
    ]
    for (name, amount, share) in expected {
        let slice = a.slices.first { $0.name == name }!
        #expect(abs(slice.amount - amount) < tol, "\(name) amount")
        #expect(abs(slice.share - share) < 0.00001, "\(name) share")
    }
}

@Test func allocationSharesSumToOne() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let a = AllocationMetrics.compute(accounts: WorkbookFixture.accounts, records: d)
    #expect(abs(a.slices.reduce(0) { $0 + $1.share } - 1.0) < 0.000001)
}

@Test func allocationOfEmptyPortfolioIsEmpty() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let a = AllocationMetrics.compute(accounts: input.accounts,
                                      records: LedgerEngine.derive(input))
    #expect(a.slices.isEmpty)
    #expect(a.total == 0)
}

@Test func computesGoalProgress() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let g = GoalMetrics.compute(target: 10_000,
                                dashboard: DashboardMetrics.compute(records: d))
    #expect(abs(g.remaining - 6_900) < tol)
    #expect(abs(g.progress! - 0.31) < 0.00001)
    #expect(g.estimatedRecordsToGoal == 21)
}

@Test func goalReachedClampsRemainingToZero() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let g = GoalMetrics.compute(target: 2_000,
                                dashboard: DashboardMetrics.compute(records: d))
    #expect(g.remaining == 0)
    #expect(g.progress! > 1.0)
    #expect(g.estimatedRecordsToGoal == 0)
}

@Test func estimateIsUndefinedWhenAverageChangeIsNotPositive() {
    var input = WorkbookFixture.portfolio
    input.records = Array(WorkbookFixture.records.prefix(1))
    let g = GoalMetrics.compute(target: 10_000,
                                dashboard: DashboardMetrics.compute(records: LedgerEngine.derive(input)))
    #expect(g.estimatedRecordsToGoal == nil)
}
