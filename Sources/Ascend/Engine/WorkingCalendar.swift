import Foundation

/// How many days in a year are actually worked, which is what meal allowance
/// is paid for.
///
/// Pure arithmetic on the calendar, so it can be checked without launching
/// anything. Portugal's national holidays include three that move with Easter,
/// so the count genuinely differs year to year — 2025 loses ten weekdays to
/// holidays, 2027 only eight.
enum WorkingCalendar {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Fixed offset: this is date arithmetic, and a daylight-saving shift
        // must not be able to move a holiday onto a different day.
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// Easter Sunday, by the anonymous Gregorian computus. Good Friday and
    /// Corpus Christi are both fixed offsets from it.
    static func easter(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The thirteen national public holidays. Municipal holidays vary by
    /// council and are not in here; they are counted separately.
    static func nationalHolidays(year: Int) -> [Date] {
        let fixed: [(month: Int, day: Int)] = [
            (1, 1),    // Ano Novo
            (4, 25),   // Dia da Liberdade
            (5, 1),    // Dia do Trabalhador
            (6, 10),   // Dia de Portugal
            (8, 15),   // Assunção de Nossa Senhora
            (10, 5),   // Implantação da República
            (11, 1),   // Todos os Santos
            (12, 1),   // Restauração da Independência
            (12, 8),   // Imaculada Conceição
            (12, 25),  // Natal
        ]
        let sunday = easter(year: year)
        let moveable = [
            calendar.date(byAdding: .day, value: -2, to: sunday)!,  // Sexta-feira Santa
            sunday,                                                 // Páscoa
            calendar.date(byAdding: .day, value: 60, to: sunday)!,  // Corpo de Deus
        ]
        return fixed.map {
            calendar.date(from: DateComponents(year: year, month: $0.month, day: $0.day))!
        } + moveable
    }

    static func isWeekday(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    /// Monday to Friday, across the whole year.
    static func weekdays(inYear year: Int) -> Int {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return 0 }

        var count = 0
        var day = start
        while day < end {
            if isWeekday(day) { count += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    /// Holidays that actually cost a working day. One falling on a Saturday
    /// takes nothing away.
    static func holidaysOnWeekdays(inYear year: Int) -> Int {
        nationalHolidays(year: year).count(where: isWeekday)
    }

    /// Days actually worked, and so days the allowance is paid for.
    static func workingDays(inYear year: Int,
                            vacationDays: Int = 22,
                            extraHolidays: Int = 1) -> Int {
        let base = weekdays(inYear: year)
            - holidaysOnWeekdays(inYear: year)
            - max(0, vacationDays)
            - max(0, extraHolidays)
        return max(0, base)
    }
}
