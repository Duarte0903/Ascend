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
    #expect(abs(a.totalInvestedPerMonth - 300) < tol)
    #expect(abs(a.leftoverPerMonth - 1200) < tol)
    #expect(abs(a.savingsRateOfIncome - 0.75) < 0.0000001)
    #expect(a.horizonMonths == 60)
    #expect(a.hasLeftoverDestination)
}

@Test func monthZeroIsTheLatestRecord() {
    let m = project().months[0]
    #expect(m.month == 0)
    #expect(abs(m.netWorth - 3100) < tol)
    #expect(abs(m.balances[WorkbookFixture.currentID]! - 1500) < tol)
}

@Test func monthOneMatchesTheWorkbook() {
    let m = project().months[1]
    #expect(abs(m.balances[WorkbookFixture.currentID]! - 2700) < tol)
    #expect(abs(m.balances[WorkbookFixture.savingsID]! - 950.66) < tol)
    #expect(abs(m.balances[WorkbookFixture.brokerageID]! - 853.41) < tol)
    #expect(abs(m.balances[WorkbookFixture.mealCardID]! - 100) < tol)
    #expect(abs(m.netWorth - 4604.07) < tol)
    #expect(abs(m.usable - 4504.07) < tol)
}

@Test func restrictedAccountsStayFlat() {
    let p = project()
    for m in p.months {
        #expect(abs(m.balances[WorkbookFixture.mealCardID]! - 100) < tol)
    }
}

@Test func projectsOneThreeAndFiveYearHorizons() {
    let p = project()
    #expect(abs(p.netWorth(atMonth: 12)! - 21207.21) < 0.5)
    #expect(abs(p.netWorth(atMonth: 36)! - 57823.50) < 0.5)
    #expect(abs(p.netWorth(atMonth: 60)! - 95024.25) < 0.5)
}

@Test func horizonProducesMonthZeroThroughHorizonInclusive() {
    #expect(project().months.count == 61)
}

@Test func findsMonthsToGoal() {
    #expect(project().monthsToGoal == 5)
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
    #expect(abs(p.months[1].balances[WorkbookFixture.currentID]! - 1500) < tol)
}

// MARK: - What counts as investing your income

/// A contribution to an account that is neither usable cash nor savings — an
/// employer-loaded food card — is not investing, so it stays out of Total
/// Invested. It is still funded from income, because income counts the
/// allowance, so it does come off the leftover.
@Test func totalInvestedIgnoresAccountsThatAreNeitherUsableNorSavings() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.mealCardID { copy.monthlyContribution = 90 }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.totalInvestedPerMonth - 300) < tol)
    // 90 less than without the contribution: not invested, but still paid.
    #expect(abs(p.assumptions.leftoverPerMonth - 1110) < tol)
}

/// The balance still grows by that contribution — it is only the funding
/// source that differs.
@Test func excludedAccountsStillReceiveTheirContribution() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.mealCardID { copy.monthlyContribution = 90 }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.months[1].balances[WorkbookFixture.mealCardID]! - (100 + 90)) < tol)
}

/// An account that is savings but not usable still counts — either flag is enough.
@Test func savingsOnlyAccountsStillCountAsInvested() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.brokerageID { copy.includeInUsable = false }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.totalInvestedPerMonth - 300) < tol)
}

/// Flipping both flags off removes the contribution from Total Invested. The
/// leftover does not move: the money is still leaving the income, it is just
/// no longer being called investing.
@Test func clearingBothFlagsMovesContributionOutOfTheTotal() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.savingsID {
            copy.includeInUsable = false
            copy.countsAsSavings = false
        }
        return copy
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(abs(p.assumptions.totalInvestedPerMonth - 150) < tol)
    #expect(abs(p.assumptions.leftoverPerMonth - 1200) < tol)
}

@Test func projectingWithNoRecordsYieldsNoMonths() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(p.months.isEmpty)
    #expect(p.monthsToGoal == nil)
}

/// Income counts the meal allowance, so the account holding it is funded out
/// of income like any other. The pairing is what matters: counting the
/// allowance as income while funding the card from nowhere would grow net
/// worth by the allowance twice over, every month.
@Test func theMealCardIsFundedFromIncomeNotFromNowhere() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.mealCardID { copy.monthlyContribution = 90 }
        return copy
    }
    let records = LedgerEngine.derive(input)
    let withCard = ProjectionEngine.project(input, records: records,
                                            from: WorkbookFixture.date(8, 8, 2026))

    var without = input
    without.accounts = without.accounts.map { account in
        var copy = account
        if copy.id == WorkbookFixture.mealCardID { copy.monthlyContribution = 0 }
        return copy
    }
    let bare = ProjectionEngine.project(without, records: records,
                                        from: WorkbookFixture.date(8, 8, 2026))

    // The contribution leaves the income, so the leftover drops by it.
    #expect(abs((bare.assumptions.leftoverPerMonth
                 - withCard.assumptions.leftoverPerMonth) - 90) < tol)
    // And net worth is unchanged: the same money, in a different pocket.
    #expect(abs((withCard.months.last?.netWorth ?? 0)
                - (bare.months.last?.netWorth ?? 0)) < tol)
}
