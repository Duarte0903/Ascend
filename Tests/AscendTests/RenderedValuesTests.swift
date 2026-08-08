import Testing
import Foundation
import SwiftData
@testable import Ascend

/// Asserts the exact strings the screens display for the sample portfolio a
/// fresh install starts with. This is the numeric half of visual verification:
/// it catches formatting and rounding regressions the engine tests cannot.
private let nnbsp = "\u{202F}"
private func eur(_ s: String) -> String { s.replacingOccurrences(of: " ", with: nnbsp) }

@MainActor
private func seeded() throws -> (PortfolioInput, [DerivedRecord]) {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context),
        expenses: try context.fetch(FetchDescriptor<Expense>()))
    return (input, LedgerEngine.derive(input))
}

@MainActor
@Test func dashboardRendersTheSampleValues() throws {
    let (_, derived) = try seeded()
    let m = DashboardMetrics.compute(records: derived)

    #expect(Money.currency(m.currentNetWorth) == eur("3 100 €"))
    #expect(Money.currency(m.usableCash) == eur("3 000 €"))
    #expect(Money.currency(m.latestChangeAmount) == eur("600 €"))
    #expect(Money.percent(m.latestChangePercent) == eur("24,0 %"))
    #expect(Money.currency(m.totalGrowth) == eur("1 000 €"))
    #expect(Money.currency(m.bestChange) == eur("600 €"))
    #expect(Money.currency(m.averageChange) == eur("333 €"))
    #expect("\(m.recordCount)" == "4")
    #expect(Money.percent(m.averageSavingsRate) == eur("7,2 %"))
}

@MainActor
@Test func balancesRowsRenderTheSampleValues() throws {
    let (_, derived) = try seeded()

    // The first record has nothing to compare against.
    #expect(Money.currency(derived[0].changeAmount) == "—")
    #expect(Money.percent(derived[0].changePercent) == "—")
    #expect(Money.percent(derived[0].savingsRate) == "—")

    let last = derived[3]
    #expect(Money.currency(last.total) == eur("3 100 €"))
    #expect(Money.currency(last.usable) == eur("3 000 €"))
    #expect(Money.currency(last.changeAmount) == eur("600 €"))
    #expect(Money.percent(last.changePercent) == eur("24,0 %"))
    #expect(Money.percent(last.savingsRate) == eur("8,0 %"))

    // Middle rows.
    #expect(Money.currency(derived[2].changeAmount) == eur("300 €"))
    #expect(Money.percent(derived[2].changePercent) == eur("13,6 %"))
    #expect(Money.currency(derived[1].changeAmount) == eur("100 €"))
    #expect(Money.percent(derived[1].savingsRate) == eur("0,0 %"))

    // Cents render when asked for, in the editable columns.
    #expect(Money.currency(derived[0].total, decimals: 2) == eur("2 100,00 €"))
}

@MainActor
@Test func allocationRendersTheSampleShares() throws {
    let (input, derived) = try seeded()
    let a = AllocationMetrics.compute(accounts: input.accounts, records: derived)

    let expected = [("Current Account", "1 500 €", "48,4 %"),
                    ("Savings", "800 €", "25,8 %"),
                    ("Brokerage", "700 €", "22,6 %"),
                    ("Meal Card", "100 €", "3,2 %")]
    for (name, amount, share) in expected {
        let slice = a.slices.first { $0.name == name }!
        #expect(Money.currency(slice.amount) == eur(amount), "\(name) amount")
        #expect(Money.percent(slice.share) == eur(share), "\(name) share")
    }
    #expect(Money.currency(a.total) == eur("3 100 €"))
    #expect(Money.currency(a.usable) == eur("3 000 €"))
}

@MainActor
@Test func goalsRenderTheSampleValues() throws {
    let (input, derived) = try seeded()
    let dashboard = DashboardMetrics.compute(records: derived)
    let g = GoalMetrics.compute(target: input.targetNetWorth, dashboard: dashboard)

    #expect(Money.currency(g.target) == eur("10 000 €"))
    #expect(Money.currency(g.current) == eur("3 100 €"))
    #expect(Money.currency(g.remaining) == eur("6 900 €"))
    #expect(Money.percent(g.progress) == eur("31,0 %"))
    #expect(Money.currency(dashboard.averageChange) == eur("333 €"))
    #expect(g.estimatedRecordsToGoal.map(String.init) == "21")
}

@MainActor
@Test func projectionsRenderTheSampleValues() throws {
    let (input, derived) = try seeded()
    let p = ProjectionEngine.project(input, records: derived,
                                     from: WorkbookFixture.date(1, 4, 2026))

    #expect(Money.currency(p.assumptions.monthlyNetIncome) == eur("2 000 €"))
    #expect(Money.currency(p.assumptions.maxMonthlyExpenses) == eur("500 €"))
    #expect(Money.currency(p.assumptions.totalInvestedPerMonth) == eur("300 €"))
    #expect(Money.currency(p.assumptions.leftoverPerMonth) == eur("1 200 €"))
    #expect(Money.percent(p.assumptions.savingsRateOfIncome) == eur("75,0 %"))
    #expect(p.monthsToGoal.map(String.init) == "5")

    // Month 1, per account.
    let accountsByName = Dictionary(uniqueKeysWithValues: input.accounts.map { ($0.name, $0.id) })
    let month1 = p.months[1]
    #expect(Money.currency(month1.balances[accountsByName["Current Account"]!]) == eur("2 700 €"))
    #expect(Money.currency(month1.balances[accountsByName["Savings"]!]) == eur("951 €"))
    #expect(Money.currency(month1.balances[accountsByName["Brokerage"]!]) == eur("853 €"))
    #expect(Money.currency(month1.balances[accountsByName["Meal Card"]!]) == eur("100 €"))

    // Month 0 mirrors the latest record.
    #expect(Money.currency(p.months[0].netWorth) == eur("3 100 €"))
    #expect(Money.currency(p.months[0].usable) == eur("3 000 €"))
}
