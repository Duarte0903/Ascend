import Foundation
import Testing
@testable import Ascend

/// The counts here were worked out independently of the implementation, so
/// they check the arithmetic rather than restate it.
@Suite("Working calendar")
struct WorkingCalendarTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func parts(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year!, components.month!, components.day!)
    }

    @Test("Easter lands where the computus says it does")
    func easterDates() {
        #expect(parts(WorkingCalendar.easter(year: 2024)) == (2024, 3, 31))
        #expect(parts(WorkingCalendar.easter(year: 2025)) == (2025, 4, 20))
        #expect(parts(WorkingCalendar.easter(year: 2026)) == (2026, 4, 5))
        #expect(parts(WorkingCalendar.easter(year: 2027)) == (2027, 3, 28))
    }

    @Test("Easter is always a Sunday")
    func easterIsSunday() {
        for year in 2020...2040 {
            #expect(calendar.component(.weekday, from: WorkingCalendar.easter(year: year)) == 1)
        }
    }

    @Test("There are thirteen national holidays, three of them moveable")
    func holidayCount() {
        for year in 2024...2030 {
            #expect(WorkingCalendar.nationalHolidays(year: year).count == 13)
        }
        // Good Friday is two days before Easter, Corpus Christi sixty after.
        let easter = WorkingCalendar.easter(year: 2026)
        let holidays = WorkingCalendar.nationalHolidays(year: 2026)
        #expect(holidays.contains(calendar.date(byAdding: .day, value: -2, to: easter)!))
        #expect(holidays.contains(calendar.date(byAdding: .day, value: 60, to: easter)!))
    }

    @Test("Weekday counts match the calendar")
    func weekdayCounts() {
        #expect(WorkingCalendar.weekdays(inYear: 2024) == 262)  // leap year
        #expect(WorkingCalendar.weekdays(inYear: 2025) == 261)
        #expect(WorkingCalendar.weekdays(inYear: 2026) == 261)
    }

    @Test("Holidays falling at the weekend take no working day away")
    func weekendHolidaysCostNothing() {
        // 2025 loses ten weekdays to holidays, 2027 only eight — the same
        // thirteen holidays, landing differently.
        #expect(WorkingCalendar.holidaysOnWeekdays(inYear: 2025) == 10)
        #expect(WorkingCalendar.holidaysOnWeekdays(inYear: 2026) == 9)
        #expect(WorkingCalendar.holidaysOnWeekdays(inYear: 2027) == 8)
    }

    @Test("Working days come out around the high two hundreds")
    func workingDayTotals() {
        #expect(WorkingCalendar.workingDays(inYear: 2025) == 261 - 10 - 22 - 1)
        #expect(WorkingCalendar.workingDays(inYear: 2026) == 261 - 9 - 22 - 1)
        // Well below the 242 that "22 days × 11 months" would have assumed.
        for year in 2024...2030 {
            let days = WorkingCalendar.workingDays(inYear: year)
            #expect(days > 220 && days < 240)
        }
    }

    @Test("More vacation means fewer days paid")
    func vacationReducesDays() {
        let standard = WorkingCalendar.workingDays(inYear: 2026, vacationDays: 22)
        let generous = WorkingCalendar.workingDays(inYear: 2026, vacationDays: 30)
        #expect(generous == standard - 8)
    }

    @Test("Absurd inputs give no working days rather than a negative count")
    func neverNegative() {
        #expect(WorkingCalendar.workingDays(inYear: 2026, vacationDays: 500) == 0)
        #expect(WorkingCalendar.workingDays(inYear: 2026, vacationDays: -10)
                == WorkingCalendar.workingDays(inYear: 2026, vacationDays: 0))
    }
}
