import Testing
import Foundation
@testable import Ascend

private let calendar = Calendar(identifier: .gregorian)
private let now = WorkbookFixture.date(15, 8, 2026)

private func derived() -> [DerivedRecord] {
    LedgerEngine.derive(WorkbookFixture.portfolio)
}

@Test func allTimeKeepsEverything() {
    #expect(DateRangeFilter.all.apply(to: derived(), now: now).count == 5)
}

@Test func windowsToTheLastThreeMonths() {
    // The fixture spans 1 July to 4 August 2026 — all within three months of
    // 15 August, so nothing is dropped.
    #expect(DateRangeFilter.months3.apply(to: derived(), now: now).count == 5)
}

@Test func dropsRecordsOlderThanTheWindow() {
    let later = WorkbookFixture.date(15, 10, 2026)
    // Three months back from mid-October is mid-July, so only the 4 August
    // record survives.
    let kept = DateRangeFilter.months3.apply(to: derived(), now: later)
    #expect(kept.count == 1)
    #expect(abs(kept[0].total - 8409.74) < 0.005)
}

@Test func yearToDateStartsOnTheFirstOfJanuary() {
    let start = DateRangeFilter.yearToDate.startDate(now: now, calendar: calendar)!
    #expect(calendar.component(.year, from: start) == 2026)
    #expect(calendar.component(.month, from: start) == 1)
    #expect(calendar.component(.day, from: start) == 1)
    #expect(DateRangeFilter.yearToDate.apply(to: derived(), now: now).count == 5)
}

@Test func yearToDateExcludesTheYearBefore() {
    let nextYear = WorkbookFixture.date(3, 2, 2027)
    #expect(DateRangeFilter.yearToDate.apply(to: derived(), now: nextYear).isEmpty)
}

/// The point of filtering after derivation: a visible record's change must
/// still be measured against the record that really preceded it, even when
/// that one is outside the window.
@Test func filteringPreservesChangeAgainstTheTruePredecessor() {
    let later = WorkbookFixture.date(15, 10, 2026)
    let kept = DateRangeFilter.months3.apply(to: derived(), now: later)
    #expect(kept.count == 1)
    // 914.71 is measured against 3 July, which the window excludes.
    #expect(abs(kept[0].changeAmount! - 914.71) < 0.005)
    #expect(abs(kept[0].savingsRate! - 0.0278704688) < 0.0000001)
}

/// Aggregates recompute over the visible window, which is what a period filter
/// is for.
@Test func dashboardAggregatesFollowTheWindow() {
    let all = DashboardMetrics.compute(records: DateRangeFilter.all.apply(to: derived(), now: now))
    #expect(all.recordCount == 5)
    #expect(abs(all.averageChange! - 236.1825) < 0.005)

    let later = WorkbookFixture.date(15, 10, 2026)
    let windowed = DashboardMetrics.compute(
        records: DateRangeFilter.months3.apply(to: derived(), now: later))
    #expect(windowed.recordCount == 1)
    #expect(abs(windowed.averageChange! - 914.71) < 0.005)
    #expect(abs(windowed.currentNetWorth! - 8409.74) < 0.005)
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
