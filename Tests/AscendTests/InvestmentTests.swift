import Testing
import Foundation
import SwiftData
@testable import Ascend

private let tol = 0.005

private func metrics(_ input: PortfolioInput) -> InvestmentMetrics {
    InvestmentMetrics.compute(accounts: input.accounts,
                              records: LedgerEngine.derive(input),
                              target: input.investmentReturnTarget)
}

// MARK: - Scope

/// Only accounts flagged as counting toward the savings rate are tracked, so
/// renaming an account type can never silently change what is measured.
@Test func tracksOnlySavingsAndInvestmentAccounts() {
    let m = metrics(WorkbookFixture.portfolio)
    #expect(m.holdings.map(\.name) == ["Savings", "Brokerage"])
    #expect(!m.holdings.contains { $0.name == "Current Account" })
    #expect(!m.holdings.contains { $0.name == "Meal Card" })
}

@Test func flaggingAnAccountAddsItToTheTracked() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.currentID {
            copy.countsAsSavings = true
            copy.amountInvested = 1_000
        }
        return copy
    }
    let m = metrics(input)
    #expect(m.holdings.count == 3)
    // Current Account: 1 500 value against 1 000 invested.
    let current = m.holdings.first { $0.name == "Current Account" }!
    #expect(abs(current.profit - 500) < tol)
}

// MARK: - Profit and return

@Test func computesProfitPerHolding() {
    let m = metrics(WorkbookFixture.portfolio)
    let savings = m.holdings.first { $0.name == "Savings" }!
    let brokerage = m.holdings.first { $0.name == "Brokerage" }!

    // Savings: 800 now against 750 put in.
    #expect(abs(savings.invested - 750) < tol)
    #expect(abs(savings.value - 800) < tol)
    #expect(abs(savings.profit - 50) < tol)
    #expect(abs(savings.returnRate! - 50.0 / 750.0) < 0.000001)

    // Brokerage: 700 now against 600 put in.
    #expect(abs(brokerage.profit - 100) < tol)
    #expect(abs(brokerage.returnRate! - 100.0 / 600.0) < 0.000001)
}

@Test func combinesIntoOnePortfolioReturn() {
    let m = metrics(WorkbookFixture.portfolio)
    #expect(abs(m.totalInvested - 1_350) < tol)
    #expect(abs(m.totalValue - 1_500) < tol)
    #expect(abs(m.totalProfit - 150) < tol)
    #expect(abs(m.overallReturn! - 150.0 / 1_350.0) < 0.000001)
}

/// The combined return is profit over what was put in — not the average of the
/// individual returns, which would weight a tiny holding the same as a large one.
@Test func combinedReturnIsMoneyWeightedNotAnAverageOfRates() {
    let m = metrics(WorkbookFixture.portfolio)
    let rates = m.holdings.compactMap(\.returnRate)
    let naiveAverage = rates.reduce(0, +) / Double(rates.count)
    #expect(abs(naiveAverage - 0.11667) < 0.001)
    #expect(abs(m.overallReturn! - 0.11111) < 0.001)
    #expect(m.overallReturn! != naiveAverage)
}

@Test func sharesAreOfCurrentValueAndSumToOne() {
    let m = metrics(WorkbookFixture.portfolio)
    #expect(abs(m.holdings.first { $0.name == "Savings" }!.share - 800.0 / 1_500.0) < 0.000001)
    #expect(abs(m.holdings.reduce(0) { $0 + $1.share } - 1) < 0.000001)
}

@Test func namesTheBestAndWorstPerformer() {
    let m = metrics(WorkbookFixture.portfolio)
    #expect(m.best?.name == "Brokerage")
    #expect(m.worst?.name == "Savings")
}

// MARK: - The target

@Test func meetsTheTargetWhenTheReturnClearsIt() {
    var input = WorkbookFixture.portfolio
    input.investmentReturnTarget = 0.03
    let m = metrics(input)
    #expect(m.meetsTarget)
    // 1 350 invested needs 1 390.50 to hit 3 %; the portfolio is worth more.
    #expect(abs(m.valueNeededForTarget - 1_390.5) < tol)
    #expect(m.amountToTarget < 0, "already past the target")
}

@Test func fallsShortWhenTheTargetIsHigherThanTheReturn() {
    var input = WorkbookFixture.portfolio
    input.investmentReturnTarget = 0.25
    let m = metrics(input)
    #expect(!m.meetsTarget)
    #expect(abs(m.valueNeededForTarget - 1_687.5) < tol)
    #expect(abs(m.amountToTarget - 187.5) < tol, "still 187.50 to go")
}

/// A return on nothing is undefined, not zero and not infinite — it must not
/// render as a number, and the target cannot be "met" by investing nothing.
@Test func nothingInvestedLeavesTheReturnUndefined() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        copy.amountInvested = 0
        return copy
    }
    let m = metrics(input)
    #expect(m.overallReturn == nil)
    #expect(m.meetsTarget == false)
    #expect(m.holdings.allSatisfy { $0.returnRate == nil })
    #expect(Money.percent(m.overallReturn) == "—")
}

@Test func aLossReadsAsANegativeReturn() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.brokerageID { copy.amountInvested = 900 }
        return copy
    }
    let m = metrics(input)
    let brokerage = m.holdings.first { $0.name == "Brokerage" }!
    #expect(abs(brokerage.profit - -200) < tol)
    #expect(brokerage.returnRate! < 0)
    #expect(!m.meetsTarget)
}

@Test func noRecordsMeansEverythingIsWorthNothingYet() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let m = metrics(input)
    #expect(m.totalValue == 0)
    #expect(abs(m.totalProfit - -1_350) < tol)
}

// MARK: - Persistence

@MainActor
@Test func seededAccountsCarryACostBasisAndTarget() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context),
        expenses: try context.fetch(FetchDescriptor<Expense>()))

    #expect(abs(input.investmentReturnTarget - 0.03) < 0.000001)
    let m = metrics(input)
    #expect(abs(m.totalInvested - 1_350) < tol)
    #expect(abs(m.totalValue - 1_500) < tol)
    #expect(m.meetsTarget)
}

@MainActor
@Test func backupRoundTripsTheCostBasisAndTarget() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    SeedData.settings(in: source).investmentReturnTarget = 0.07
    try source.save()

    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source),
        categories: try source.fetch(FetchDescriptor<AccountCategory>()),
        expenses: try source.fetch(FetchDescriptor<Expense>()),
        expenseCategories: try source.fetch(FetchDescriptor<ExpenseCategory>()))

    let target = try inMemoryContext()
    try BackupService.restore(from: data, into: target)

    let restored = try target.fetch(FetchDescriptor<Account>())
    #expect(restored.first { $0.name == "Savings" }?.amountInvested == 750)
    #expect(restored.first { $0.name == "Brokerage" }?.amountInvested == 600)
    #expect(abs(SeedData.settings(in: target).investmentReturnTarget - 0.07) < 0.000001)
}

// MARK: - Bringing an untracked earner in

/// An account earning a return but not flagged is invisible to the totals.
/// Flagging it must fold it in — value, invested and the combined return all move.
@Test func trackingAPreviouslyExcludedSavingsAccountFoldsItIn() {
    var input = WorkbookFixture.portfolio
    let before = metrics(input)
    #expect(before.holdings.count == 2)
    #expect(abs(before.totalValue - 1_500) < tol)

    // The current account starts untracked; give it a return and include it.
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.currentID {
            copy.expectedAnnualReturn = 0.03
            copy.countsAsSavings = true
            copy.amountInvested = 1_400
        }
        return copy
    }

    let after = metrics(input)
    #expect(after.holdings.count == 3)
    #expect(abs(after.totalValue - 3_000) < tol)      // 1 500 more of value
    #expect(abs(after.totalInvested - 2_750) < tol)   // 1 400 more invested
    #expect(abs(after.totalProfit - 250) < tol)
    // Every share is recalculated against the larger portfolio.
    #expect(abs(after.holdings.reduce(0) { $0 + $1.share } - 1) < 0.000001)
}

/// The same flag drives the savings rate, so including an account here changes
/// that figure too. Worth a test, because it is a real consequence rather than
/// an accident.
@Test func trackingAnAccountAlsoChangesTheSavingsRate() {
    var input = WorkbookFixture.portfolio
    let before = LedgerEngine.derive(input).last!.savingsRate!

    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.currentID { copy.countsAsSavings = true }
        return copy
    }
    let after = LedgerEngine.derive(input).last!.savingsRate!

    // The current account rose 400 over the last record, which now counts.
    #expect(abs(before - 0.08) < 0.000001)
    #expect(abs(after - 0.24) < 0.000001)
}

// MARK: - Per-year return

/// Balance records supply the time span, not the return: deposits sit inside
/// balances, so the span is all they can honestly contribute.
@Test func recordsSupplyTheTrackedSinceDate() {
    let m = metrics(WorkbookFixture.portfolio)
    // Savings first appears in the opening record, 1 March 2026.
    let savings = m.holdings.first { $0.name == "Savings" }!
    #expect(savings.trackedSince == WorkbookFixture.date(1, 3, 2026))
    #expect(m.trackedSince == WorkbookFixture.date(1, 3, 2026))
}

/// Under a year, annualising turns a few weeks into a fantasy — 6.7% over one
/// month is not 118% a year in any useful sense. It reports nothing instead.
@Test func refusesToAnnualiseLessThanAYear() {
    let m = metrics(WorkbookFixture.portfolio)
    #expect(m.years! < 1)
    #expect(m.annualisedReturn == nil)
    #expect(m.comparingAnnualised == false)
    #expect(Money.percent(m.annualisedReturn) == "—")
    // The cumulative figure is still there and still correct.
    #expect(abs(m.overallReturn! - 150.0 / 1_350.0) < 0.000001)
}

@Test func annualisesOnceThereIsAYearOfRecords() {
    var input = WorkbookFixture.portfolio
    // Same balances, but the latest record is two years after the first.
    input.records = input.records.enumerated().map { index, record in
        var copy = record
        if index == input.records.count - 1 { copy.date = WorkbookFixture.date(1, 3, 2028) }
        return copy
    }
    let m = metrics(input)
    #expect(m.years! > 1.9 && m.years! < 2.1)
    // 11.11% total over two years compounds to about 5.4% a year.
    #expect(abs(m.annualisedReturn! - 0.0541) < 0.001)
    #expect(m.annualisedReturn! < m.overallReturn!)
    #expect(m.comparingAnnualised)
}

/// The point of the whole exercise: an annual target must be judged against an
/// annual return, not a lifetime one.
@Test func theTargetIsJudgedAgainstThePerYearReturn() {
    var input = WorkbookFixture.portfolio
    input.investmentReturnTarget = 0.08
    input.records = input.records.enumerated().map { index, record in
        var copy = record
        if index == input.records.count - 1 { copy.date = WorkbookFixture.date(1, 3, 2028) }
        return copy
    }
    let m = metrics(input)
    // 11.11% total clears 8% outright, but 5.4% a year does not.
    #expect(m.overallReturn! > 0.08)
    #expect(m.annualisedReturn! < 0.08)
    #expect(!m.meetsTarget, "an annual target must be met annually")
}

@Test func annualisingRefusesImpossibleInput() {
    // A total loss has no meaningful per-year equivalent.
    #expect(InvestmentMetrics.annualise(-1, overYears: 3) == nil)
    #expect(InvestmentMetrics.annualise(-1.5, overYears: 3) == nil)
    #expect(InvestmentMetrics.annualise(0.2, overYears: nil) == nil)
    #expect(InvestmentMetrics.annualise(nil, overYears: 3) == nil)
    // Exactly a year leaves the figure untouched.
    #expect(abs(InvestmentMetrics.annualise(0.2, overYears: 1)! - 0.2) < 0.000001)
}

@Test func aSingleRecordGivesNoSpanToMeasureOver() {
    var input = WorkbookFixture.portfolio
    input.records = [input.records[0]]
    let m = metrics(input)
    #expect(m.years == nil)
    #expect(m.annualisedReturn == nil)
    #expect(m.overallReturn != nil, "a total return still works without a span")
}

// MARK: - Manual tracking overrides

/// Accounts still arrive on their own: the default follows the savings flag.
@Test func automaticTrackingFollowsTheSavingsFlag() {
    #expect(InvestmentTracking.auto.tracks(countsAsSavings: true))
    #expect(!InvestmentTracking.auto.tracks(countsAsSavings: false))
    #expect(InvestmentTracking.included.tracks(countsAsSavings: false))
    #expect(!InvestmentTracking.excluded.tracks(countsAsSavings: true))
}

@Test func includingAnAccountDoesNotTouchItsSavingsFlag() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.currentID {
            copy.investmentTracking = .included
            copy.amountInvested = 1_400
        }
        return copy
    }

    let m = metrics(input)
    #expect(m.holdings.count == 3)
    #expect(m.holdings.contains { $0.name == "Current Account" })

    // The savings rate reads the flag, which was never changed — so including
    // an account here leaves every other screen alone.
    let unchanged = LedgerEngine.derive(input).last!.savingsRate!
    #expect(abs(unchanged - 0.08) < 0.000001)
}

@Test func excludingAnAccountRemovesItFromTheTotals() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.savingsID { copy.investmentTracking = .excluded }
        return copy
    }
    let m = metrics(input)
    #expect(m.holdings.map(\.name) == ["Brokerage"])
    #expect(abs(m.totalInvested - 600) < tol)
    #expect(abs(m.totalValue - 700) < tol)
    // Shares are recalculated against what remains.
    #expect(abs(m.holdings[0].share - 1) < 0.000001)
}

/// An explicit choice beats the flag in both directions — that is the point of
/// having one.
@Test func anExplicitChoiceOverridesTheFlagEitherWay() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        // A savings account forced out, a non-savings account forced in.
        if copy.id == WorkbookFixture.savingsID { copy.investmentTracking = .excluded }
        if copy.id == WorkbookFixture.mealCardID { copy.investmentTracking = .included }
        return copy
    }
    let m = metrics(input)
    #expect(m.holdings.map(\.name) == ["Brokerage", "Meal Card"])
}

@MainActor
@Test func trackingChoiceSurvivesABackup() throws {
    let source = try inMemoryContext()
    SeedData.seedIfNeeded(source)
    let current = try #require(try source.fetch(FetchDescriptor<Account>())
        .first { $0.name == "Current Account" })
    current.investmentTracking = .included
    let savings = try #require(try source.fetch(FetchDescriptor<Account>())
        .first { $0.name == "Savings" })
    savings.investmentTracking = .excluded
    try source.save()

    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source),
        categories: try source.fetch(FetchDescriptor<AccountCategory>()),
        expenses: try source.fetch(FetchDescriptor<Expense>()),
        expenseCategories: try source.fetch(FetchDescriptor<ExpenseCategory>()))

    let target = try inMemoryContext()
    try BackupService.restore(from: data, into: target)
    let restored = try target.fetch(FetchDescriptor<Account>())
    #expect(restored.first { $0.name == "Current Account" }?.investmentTracking == .included)
    #expect(restored.first { $0.name == "Savings" }?.investmentTracking == .excluded)
    #expect(restored.first { $0.name == "Brokerage" }?.investmentTracking == .auto)
}

/// Existing stores have no stored choice, so everything must default to auto
/// and behave exactly as before.
@MainActor
@Test func accountsWithoutAChoiceDefaultToAutomatic() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let accounts = try context.fetch(FetchDescriptor<Account>())
    #expect(accounts.allSatisfy { $0.investmentTracking == .auto })
    #expect(accounts.filter(\.isTrackedInvestment).count == 2)
}
