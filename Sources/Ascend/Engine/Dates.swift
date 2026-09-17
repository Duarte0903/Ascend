import Foundation

/// Date formatting for the whole app, fixed to day/month/year regardless of
/// the Mac's locale — a date read as 7 January in one place and 1 July in
/// another is worse than either.
enum Dates {
    /// DateFormatter is documented thread-safe for formatting, so one shared
    /// instance is fine; the annotation says so to the compiler.
    nonisolated(unsafe) private static let full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    nonisolated(unsafe) private static let dayMonthOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    /// 01/07/2026
    static func short(_ date: Date) -> String { full.string(from: date) }

    /// 01/07 — for a caption where the year is already obvious.
    static func dayMonth(_ date: Date) -> String { dayMonthOnly.string(from: date) }

    /// The locale whose short date is exactly dd/MM/yyyy, for date pickers,
    /// whose format is the locale's and cannot be set directly.
    static let pickerLocale = Locale(identifier: "en_GB")
}
