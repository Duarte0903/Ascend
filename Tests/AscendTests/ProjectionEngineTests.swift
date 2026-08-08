import Testing
import Foundation
@testable import Ascend

private let tol = 0.01

private func project() -> Projection {
    let input = WorkbookFixture.portfolio
    return ProjectionEngine.project(input,
                                    records: LedgerEngine.derive(input),
                                    from: WorkbookFixture.date(8, 8, 2026))
}

@Test func derivesAssumptionsFromInputsAndAccounts() {
    let a = project().assumptions
    #expect(abs(a.totalInvestedPerMonth - 200) < tol)
    #expect(abs(a.leftoverPerMonth - 717) < tol)
    #expect(abs(a.savingsRateOfIncome - 0.8209489) < 0.0000001)
    #expect(a.horizonMonths == 60)
    #expect(a.hasLeftoverDestination)
}

@Test func monthZeroIsTheLatestRecord() {
    let m = project().months[0]
    #expect(m.month == 0)
    #expect(abs(m.netWorth - 8409.74) < tol)
    #expect(abs(m.balances[WorkbookFixture.cttID]! - 6962.35) < tol)
}

@Test func monthOneMatchesTheWorkbook() {
    let m = project().months[1]
    #expect(abs(m.balances[WorkbookFixture.cttID]! - 7679.35) < tol)
    #expect(abs(m.balances[WorkbookFixture.revolutID]! - 450.59) < tol)
    #expect(abs(m.balances[WorkbookFixture.xtbID]! - 924.12) < tol)
    #expect(abs(m.balances[WorkbookFixture.edenredID]! - 277.63) < tol)
    #expect(abs(m.netWorth - 9331.69) < tol)
    #expect(abs(m.usable - 9054.06) < tol)
}

@Test func restrictedAccountsStayFlat() {
    let p = project()
    for m in p.months {
        #expect(abs(m.balances[WorkbookFixture.edenredID]! - 277.63) < tol)
    }
}

@Test func projectsOneThreeAndFiveYearHorizons() {
    let p = project()
    #expect(abs(p.netWorth(atMonth: 12)! - 19519.03) < 0.5)
    #expect(abs(p.netWorth(atMonth: 36)! - 42056.05) < 0.5)
    #expect(abs(p.netWorth(atMonth: 60)! - 65063.23) < 0.5)
}

@Test func horizonProducesMonthZeroThroughHorizonInclusive() {
    #expect(project().months.count == 61)
}

@Test func findsMonthsToGoal() {
    #expect(project().monthsToGoal == 18)
}

@Test func monthsToGoalIsNilWhenGoalIsNotReachedWithinHorizon() {
    var input = WorkbookFixture.portfolio
    input.targetNetWorth = 10_000_000
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(p.monthsToGoal == nil)
}

@Test func monthDatesAdvanceByOneMonth() {
    let p = project()
    let cal = Calendar(identifier: .gregorian)
    #expect(cal.component(.month, from: p.months[1].date) == 9)
    #expect(cal.component(.year, from: p.months[12].date) == 2027)
}

/// Without a leftover destination the surplus has nowhere to go. The engine
/// must report that rather than silently discarding the money.
@Test func flagsMissingLeftoverDestination() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map {
        var a = $0; a.isLeftoverDestination = false; return a
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(p.assumptions.hasLeftoverDestination == false)
    #expect(abs(p.months[1].balances[WorkbookFixture.cttID]! - 6962.35) < tol)
}

// MARK: - What counts as investing your income

/// A contribution to an account that is neither usable cash nor savings — an
/// employer-loaded food card, for instance — is not funded from your salary,
/// so it must stay out of Total Invested and out of the leftover deduction.
@Test func totalInvestedIgnoresAccountsThatAreNeitherUsableNorSavings() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.edenredID { copy.monthlyContribution = 90 }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.totalInvestedPerMonth - 200) < tol)
    #expect(abs(p.assumptions.leftoverPerMonth - 717) < tol)
}

/// The balance still grows by that contribution — it is only the funding
/// source that differs.
@Test func excludedAccountsStillReceiveTheirContribution() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.edenredID { copy.monthlyContribution = 90 }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.months[1].balances[WorkbookFixture.edenredID]! - (277.63 + 90)) < tol)
}

/// An account that is savings but not usable still counts — either flag is enough.
@Test func savingsOnlyAccountsStillCountAsInvested() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.xtbID { copy.includeInUsable = false }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.totalInvestedPerMonth - 200) < tol)
}

/// Flipping both flags off removes the contribution from the total, which
/// raises the leftover by the same amount.
@Test func clearingBothFlagsMovesContributionOutOfTheTotal() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.revolutID {
            copy.includeInUsable = false
            copy.countsAsSavings = false
        }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.totalInvestedPerMonth - 100) < tol)
    #expect(abs(p.assumptions.leftoverPerMonth - 817) < tol)
}

@Test func projectingWithNoRecordsYieldsNoMonths() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(p.months.isEmpty)
    #expect(p.monthsToGoal == nil)
}
