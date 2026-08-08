import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

/// Asserts the exact strings the screens display, against the values printed in
/// net_worth_tracker_pro.pdf. This is the numeric half of visual verification:
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
        settings: SeedData.settings(in: context))
    return (input, LedgerEngine.derive(input))
}

@MainActor
@Test func dashboardRendersThePdfValues() throws {
    let (_, derived) = try seeded()
    let m = DashboardMetrics.compute(records: derived)

    #expect(Money.currency(m.currentNetWorth) == eur("8 410 €"))
    #expect(Money.currency(m.usableCash) == eur("8 132 €"))
    #expect(Money.currency(m.latestChangeAmount) == eur("915 €"))
    #expect(Money.percent(m.latestChangePercent) == eur("12,2 %"))
    #expect(Money.currency(m.totalGrowth) == eur("945 €"))
    #expect(Money.currency(m.bestChange) == eur("915 €"))
    #expect(Money.currency(m.averageChange) == eur("236 €"))
    #expect("\(m.recordCount)" == "5")
    #expect(Money.percent(m.averageSavingsRate) == eur("0,9 %"))
}

@MainActor
@Test func balancesRowsRenderThePdfValues() throws {
    let (_, derived) = try seeded()

    // The first record has nothing to compare against.
    #expect(Money.currency(derived[0].changeAmount) == "—")
    #expect(Money.percent(derived[0].changePercent) == "—")
    #expect(Money.percent(derived[0].savingsRate) == "—")

    // Final row, as printed in the workbook.
    let last = derived[4]
    #expect(Money.currency(last.total) == eur("8 410 €"))
    #expect(Money.currency(last.usable) == eur("8 132 €"))
    #expect(Money.currency(last.changeAmount) == eur("915 €"))
    #expect(Money.percent(last.changePercent) == eur("12,2 %"))
    #expect(Money.percent(last.savingsRate) == eur("2,8 %"))

    // Middle rows.
    #expect(Money.currency(derived[2].changeAmount) == eur("30 €"))
    #expect(Money.percent(derived[2].changePercent) == eur("0,4 %"))
    #expect(Money.currency(derived[1].changeAmount) == eur("0 €"))
    #expect(Money.percent(derived[1].savingsRate) == eur("0,7 %"))

    // Cents are preserved in the editable columns.
    #expect(Money.currency(derived[0].total, decimals: 2) == eur("7 465,01 €"))
}

@MainActor
@Test func allocationRendersThePdfShares() throws {
    let (input, derived) = try seeded()
    let a = AllocationMetrics.compute(accounts: input.accounts, records: derived)

    let expected = [("Banco CTT", "6 962 €", "82,8 %"),
                    ("Revolut", "350 €", "4,2 %"),
                    ("XTB", "819 €", "9,7 %"),
                    ("Edenred", "278 €", "3,3 %")]
    for (name, amount, share) in expected {
        let slice = a.slices.first { $0.name == name }!
        #expect(Money.currency(slice.amount) == eur(amount), "\(name) amount")
        #expect(Money.percent(slice.share) == eur(share), "\(name) share")
    }
    #expect(Money.currency(a.total) == eur("8 410 €"))
    #expect(Money.currency(a.usable) == eur("8 132 €"))
}

@MainActor
@Test func goalsRenderThePdfValues() throws {
    let (input, derived) = try seeded()
    let dashboard = DashboardMetrics.compute(records: derived)
    let g = GoalMetrics.compute(target: input.targetNetWorth, dashboard: dashboard)

    #expect(Money.currency(g.target) == eur("25 000 €"))
    #expect(Money.currency(g.current) == eur("8 410 €"))
    #expect(Money.currency(g.remaining) == eur("16 590 €"))
    #expect(Money.percent(g.progress) == eur("33,6 %"))
    #expect(Money.currency(dashboard.averageChange) == eur("236 €"))
    #expect(g.estimatedRecordsToGoal.map(String.init) == "71")
}

@MainActor
@Test func projectionsRenderThePdfValues() throws {
    let (input, derived) = try seeded()
    let p = ProjectionEngine.project(input, records: derived,
                                     from: WorkbookFixture.date(8, 8, 2026))

    #expect(Money.currency(p.assumptions.monthlyNetIncome) == eur("1 117 €"))
    #expect(Money.currency(p.assumptions.maxMonthlyExpenses) == eur("200 €"))
    #expect(Money.currency(p.assumptions.totalInvestedPerMonth) == eur("200 €"))
    #expect(Money.currency(p.assumptions.leftoverPerMonth) == eur("717 €"))
    #expect(Money.percent(p.assumptions.savingsRateOfIncome) == eur("82,1 %"))
    #expect(p.monthsToGoal.map(String.init) == "18")

    // Month 1, exactly as the workbook prints its per-account columns.
    let accountsByName = Dictionary(uniqueKeysWithValues: input.accounts.map { ($0.name, $0.id) })
    let month1 = p.months[1]
    #expect(Money.currency(month1.balances[accountsByName["Banco CTT"]!]) == eur("7 679 €"))
    #expect(Money.currency(month1.balances[accountsByName["Revolut"]!]) == eur("451 €"))
    #expect(Money.currency(month1.balances[accountsByName["XTB"]!]) == eur("924 €"))
    #expect(Money.currency(month1.balances[accountsByName["Edenred"]!]) == eur("278 €"))

    // Month 0 mirrors the latest record.
    #expect(Money.currency(p.months[0].netWorth) == eur("8 410 €"))
    #expect(Money.currency(p.months[0].usable) == eur("8 132 €"))
}
