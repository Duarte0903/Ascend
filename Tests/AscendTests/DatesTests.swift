import Foundation
import Testing
@testable import Ascend

@Suite("Date formatting")
struct DatesTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ d: Int, _ m: Int, _ y: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("Dates read day/month/year, zero-padded, with a four-digit year")
    func dayMonthYear() {
        #expect(Dates.short(day(1, 7, 2026)) == "01/07/2026")
        #expect(Dates.short(day(25, 12, 2026)) == "25/12/2026")
    }

    @Test("Day and month alone keep the same order and padding")
    func dayMonth() {
        #expect(Dates.dayMonth(day(1, 7, 2026)) == "01/07")
        #expect(Dates.dayMonth(day(15, 11, 2026)) == "15/11")
    }

    @Test("The order cannot be mistaken: 7 January and 1 July differ")
    func unambiguous() {
        #expect(Dates.short(day(7, 1, 2026)) == "07/01/2026")
        #expect(Dates.short(day(1, 7, 2026)) == "01/07/2026")
        #expect(Dates.short(day(7, 1, 2026)) != Dates.short(day(1, 7, 2026)))
    }

    @Test("The picker locale's own short date is the same shape")
    func pickerLocaleAgrees() {
        // Pickers format with the locale, not the formatter, so the two must
        // agree or a date would read differently while being edited.
        let formatter = DateFormatter()
        formatter.locale = Dates.pickerLocale
        formatter.dateStyle = .short
        #expect(formatter.string(from: day(1, 7, 2026)) == Dates.short(day(1, 7, 2026)))
    }
}
