import Foundation

/// A time window for the screens that show history.
///
/// Filtering happens *after* derivation, never before: each record's change and
/// savings rate must stay relative to its true predecessor, even when that
/// predecessor falls outside the window. Only the aggregate figures are
/// recomputed over what's visible.
enum DateRangeFilter: Hashable, Identifiable, Sendable {
    case all, months3, months6, months12, yearToDate
    /// One whole calendar year, bounded at both ends — unlike every other case,
    /// which only has a floor.
    case year(Int)

    /// The fixed windows, for a menu that then lists whichever years exist.
    static let standardCases: [DateRangeFilter] = [.all, .months3, .months6,
                                                   .months12, .yearToDate]

    var id: String { rawValue }

    /// Written by hand rather than synthesised, because a case with an
    /// associated value cannot have a raw type. The five original strings are
    /// kept exactly so a stored preference still resolves.
    var rawValue: String {
        switch self {
        case .all: "all"
        case .months3: "months3"
        case .months6: "months6"
        case .months12: "months12"
        case .yearToDate: "yearToDate"
        case .year(let year): "year\(year)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "months3": self = .months3
        case "months6": self = .months6
        case "months12": self = .months12
        case "yearToDate": self = .yearToDate
        default:
            guard rawValue.hasPrefix("year"),
                  let year = Int(rawValue.dropFirst(4)) else { return nil }
            self = .year(year)
        }
    }

    /// The years that appear in a set of records, most recent first.
    static func years(in dates: [Date],
                      calendar: Calendar = Calendar(identifier: .gregorian)) -> [Int] {
        Set(dates.map { calendar.component(.year, from: $0) }).sorted(by: >)
    }

    var label: String {
        switch self {
        case .all: "All time"
        case .months3: "Last 3 months"
        case .months6: "Last 6 months"
        case .months12: "Last 12 months"
        case .yearToDate: "This year"
        case .year(let year): String(year)
        }
    }

    /// Short form for a toolbar, where space is tight.
    var shortLabel: String {
        switch self {
        case .all: "All"
        case .months3: "3M"
        case .months6: "6M"
        case .months12: "12M"
        case .yearToDate: "YTD"
        case .year(let year): String(year)
        }
    }

    /// The earliest date included, or nil for no lower bound.
    func startDate(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        switch self {
        case .all:
            nil
        case .months3:
            calendar.date(byAdding: .month, value: -3, to: now)
        case .months6:
            calendar.date(byAdding: .month, value: -6, to: now)
        case .months12:
            calendar.date(byAdding: .month, value: -12, to: now)
        case .yearToDate:
            calendar.date(from: DateComponents(year: calendar.component(.year, from: now),
                                               month: 1, day: 1))
        case .year(let year):
            calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        }
    }

    /// The first moment *after* the window. Only a named year has one; every
    /// other case runs up to now and beyond, so it has no ceiling.
    func endDate(calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        guard case .year(let year) = self else { return nil }
        return calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
    }

    func contains(_ date: Date, now: Date,
                  calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        if let end = endDate(calendar: calendar), date >= end { return false }
        guard let start = startDate(now: now, calendar: calendar) else { return true }
        return date >= start
    }

    /// Applies the window to already-derived records.
    func apply(to records: [DerivedRecord], now: Date,
               calendar: Calendar = Calendar(identifier: .gregorian)) -> [DerivedRecord] {
        guard self != .all else { return records }
        return records.filter { contains($0.date, now: now, calendar: calendar) }
    }
}
