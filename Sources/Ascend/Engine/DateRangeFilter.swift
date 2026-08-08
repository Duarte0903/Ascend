import Foundation

/// A time window for the screens that show history.
///
/// Filtering happens *after* derivation, never before: each record's change and
/// savings rate must stay relative to its true predecessor, even when that
/// predecessor falls outside the window. Only the aggregate figures are
/// recomputed over what's visible.
enum DateRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case all, months3, months6, months12, yearToDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All time"
        case .months3: "Last 3 months"
        case .months6: "Last 6 months"
        case .months12: "Last 12 months"
        case .yearToDate: "This year"
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
        }
    }

    func contains(_ date: Date, now: Date,
                  calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
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
