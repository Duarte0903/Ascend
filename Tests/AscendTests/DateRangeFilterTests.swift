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
    let short = DateRangeFilter.standardCases.map(\.shortLabel)
    #expect(Set(short).count == short.count)
    #expect(DateRangeFilter.standardCases.allSatisfy { !$0.label.isEmpty })
}

@Test func allTimeHasNoLowerBound() {
    #expect(DateRangeFilter.all.startDate(now: now, calendar: calendar) == nil)
    #expect(DateRangeFilter.all.contains(WorkbookFixture.date(1, 1, 1990), now: now))
}

@Suite("Filtering by a named year")
struct YearRangeTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = WorkbookFixture.date(20, 8, 2026)

    private func day(_ d: Int, _ m: Int, _ y: Int) -> Date {
        WorkbookFixture.date(d, m, y)
    }

    @Test("A year takes everything inside it and nothing outside")
    func boundedAtBothEnds() {
        let range = DateRangeFilter.year(2025)
        #expect(range.contains(day(1, 1, 2025), now: now))
        #expect(range.contains(day(31, 12, 2025), now: now))
        #expect(!range.contains(day(31, 12, 2024), now: now))
        #expect(!range.contains(day(1, 1, 2026), now: now))
    }

    @Test("Unlike every other range, a year has a ceiling")
    func onlyYearsHaveAnEnd() {
        #expect(DateRangeFilter.year(2025).endDate(calendar: calendar) != nil)
        for range in DateRangeFilter.standardCases {
            #expect(range.endDate(calendar: calendar) == nil)
        }
    }

    @Test("A past year is not confused with the last twelve months")
    func notTheSameAsTwelveMonths() {
        // August 2025 is inside the last twelve months but 2025 also holds
        // January, which is not.
        #expect(DateRangeFilter.months12.contains(day(1, 1, 2025), now: now) == false)
        #expect(DateRangeFilter.year(2025).contains(day(1, 1, 2025), now: now))
    }

    @Test("A year survives being stored and read back")
    func roundTripsThroughStorage() {
        let stored = DateRangeFilter.year(2026).rawValue
        #expect(stored == "year2026")
        #expect(DateRangeFilter(rawValue: stored) == .year(2026))
    }

    @Test("The five original stored values still resolve")
    func oldPreferencesStillLoad() {
        for range in DateRangeFilter.standardCases {
            #expect(DateRangeFilter(rawValue: range.rawValue) == range)
        }
        #expect(DateRangeFilter(rawValue: "months3") == .months3)
        #expect(DateRangeFilter(rawValue: "nonsense") == nil)
        #expect(DateRangeFilter(rawValue: "yearXY") == nil)
    }

    @Test("A year is labelled as itself, not as a number")
    func labelledAsAYear() {
        #expect(DateRangeFilter.year(2026).label == "2026")
        #expect(DateRangeFilter.year(2026).shortLabel == "2026")
    }

    @Test("Only years with records in them are offered, newest first")
    func offersYearsThatExist() {
        let dates = [day(1, 3, 2024), day(5, 7, 2026), day(9, 9, 2024), day(2, 2, 2025)]
        #expect(DateRangeFilter.years(in: dates, calendar: calendar) == [2026, 2025, 2024])
        #expect(DateRangeFilter.years(in: [], calendar: calendar).isEmpty)
    }

    @Test("Applying a year keeps only that year's records")
    func appliesToRecords() {
        let input = PortfolioInput(
            accounts: [],
            records: [day(1, 6, 2025), day(1, 6, 2026)].map {
                RecordInput(id: UUID(), date: $0, createdAt: $0, balances: [:])
            },
            targetNetWorth: 0, monthlyNetIncome: 0, projectionHorizonMonths: 1)
        let derived = LedgerEngine.derive(input)

        let kept = DateRangeFilter.year(2025).apply(to: derived, now: now, calendar: calendar)
        #expect(kept.count == 1)
        #expect(calendar.component(.year, from: kept[0].date) == 2025)
    }
}
