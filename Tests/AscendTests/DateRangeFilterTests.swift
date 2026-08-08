import Testing
import Foundation
@testable import Ascend

private let calendar = Calendar(identifier: .gregorian)
private let now = WorkbookFixture.date(15, 4, 2026)

private func derived() -> [DerivedRecord] {
    LedgerEngine.derive(WorkbookFixture.portfolio)
}

@Test func allTimeKeepsEverything() {
    #expect(DateRangeFilter.all.apply(to: derived(), now: now).count == 4)
}

@Test func windowsToTheLastThreeMonths() {
    // The fixture spans 1 March to 1 April 2026 — all within three months of
    // 15 April, so nothing is dropped.
    #expect(DateRangeFilter.months3.apply(to: derived(), now: now).count == 4)
}

@Test func dropsRecordsOlderThanTheWindow() {
    let later = WorkbookFixture.date(1, 7, 2026)
    // Three months back from 1 July is 1 April, so only the final record
    // survives.
    let kept = DateRangeFilter.months3.apply(to: derived(), now: later)
    #expect(kept.count == 1)
    #expect(abs(kept[0].total - 3100) < 0.005)
}

@Test func yearToDateStartsOnTheFirstOfJanuary() {
    let start = DateRangeFilter.yearToDate.startDate(now: now, calendar: calendar)!
    #expect(calendar.component(.year, from: start) == 2026)
    #expect(calendar.component(.month, from: start) == 1)
    #expect(calendar.component(.day, from: start) == 1)
    #expect(DateRangeFilter.yearToDate.apply(to: derived(), now: now).count == 4)
}

@Test func yearToDateExcludesTheYearBefore() {
    let nextYear = WorkbookFixture.date(3, 2, 2027)
    #expect(DateRangeFilter.yearToDate.apply(to: derived(), now: nextYear).isEmpty)
}

/// The point of filtering after derivation: a visible record's change must
/// still be measured against the record that really preceded it, even when
/// that one is outside the window.
@Test func filteringPreservesChangeAgainstTheTruePredecessor() {
    let later = WorkbookFixture.date(1, 7, 2026)
    let kept = DateRangeFilter.months3.apply(to: derived(), now: later)
    #expect(kept.count == 1)
    // 600 is measured against 15 March, which the window excludes.
    #expect(abs(kept[0].changeAmount! - 600) < 0.005)
    #expect(abs(kept[0].savingsRate! - 0.08) < 0.0000001)
}

/// Aggregates recompute over the visible window, which is what a period filter
/// is for.
@Test func dashboardAggregatesFollowTheWindow() {
    let all = DashboardMetrics.compute(records: DateRangeFilter.all.apply(to: derived(), now: now))
    #expect(all.recordCount == 4)
    #expect(abs(all.averageChange! - 333.3333333) < 0.005)

    let later = WorkbookFixture.date(1, 7, 2026)
    let windowed = DashboardMetrics.compute(
        records: DateRangeFilter.months3.apply(to: derived(), now: later))
    #expect(windowed.recordCount == 1)
    #expect(abs(windowed.averageChange! - 600) < 0.005)
    #expect(abs(windowed.currentNetWorth! - 3100) < 0.005)
}

@Test func everyRangeHasDistinctLabels() {
    let short = DateRangeFilter.allCases.map(\.shortLabel)
    #expect(Set(short).count == short.count)
    #expect(DateRangeFilter.allCases.allSatisfy { !$0.label.isEmpty })
}

@Test func allTimeHasNoLowerBound() {
    #expect(DateRangeFilter.all.startDate(now: now, calendar: calendar) == nil)
    #expect(DateRangeFilter.all.contains(WorkbookFixture.date(1, 1, 1990), now: now))
}
