import Foundation

/// How often interest is credited to an account.
///
/// Separate from `ExpenseFrequency` even though they overlap: interest is paid
/// on schedules that bills are not — six-monthly is common for savings and
/// meaningless for a subscription — and coupling them would mean one list
/// growing options the other has no use for.
///
/// Every schedule is ultimately a number of months, so the named cases are
/// shorthand and `everyMonths` covers whatever the shorthand misses.
enum InterestFrequency: Hashable, Codable, Sendable, Identifiable {
    case none, monthly, quarterly, semiannual, annual
    /// Any other interval, in whole months.
    case everyMonths(Int)

    /// What the picker offers before you reach for a custom interval.
    static let presets: [InterestFrequency] = [.none, .monthly, .quarterly,
                                               .semiannual, .annual]

    /// The shortest and longest custom interval worth allowing. A schedule of
    /// zero months would never arrive; a decade is past the point of use.
    static let customRange = 1...120

    var id: String { rawValue }

    /// Labelled by interval rather than by name.
    ///
    /// "Quarterly", "trimestral" and "every 3 months" are one schedule, and the
    /// name is the only part that needs translating — so the name goes. It also
    /// puts the presets and a custom interval in the same series, instead of
    /// making them read as different kinds of thing.
    var label: String {
        guard let months = monthsBetween else { return "No set schedule" }
        return months == 1 ? "Every month" : "Every \(months) months"
    }

    /// Months between payments, or nil when there is no schedule to walk.
    var monthsBetween: Int? {
        switch self {
        case .none: nil
        case .monthly: 1
        case .quarterly: 3
        case .semiannual: 6
        case .annual: 12
        case .everyMonths(let months): max(1, months)
        }
    }

    var timesPerYear: Double {
        guard let months = monthsBetween else { return 0 }
        return 12.0 / Double(months)
    }

    var isScheduled: Bool { self != .none }

    /// True for an interval no preset already covers, which is what the UI
    /// needs to know to show the months field.
    var isCustom: Bool {
        if case .everyMonths = self { return true }
        return false
    }

    /// Collapses a custom interval onto the preset that means the same thing.
    ///
    /// Without this, "every 3 months" and "quarterly" would be two spellings of
    /// one schedule — identical in behaviour, different in the store, and
    /// capable of disagreeing in a picker about which one is selected.
    static func normalised(_ frequency: InterestFrequency) -> InterestFrequency {
        guard case .everyMonths(let months) = frequency else { return frequency }
        let clamped = min(max(months, customRange.lowerBound), customRange.upperBound)
        return presets.first { $0.monthsBetween == clamped } ?? .everyMonths(clamped)
    }

    // MARK: - Stored form

    /// Written by hand: a case with an associated value cannot have a raw type.
    /// The original five strings are kept exactly so stored accounts still read.
    var rawValue: String {
        switch self {
        case .none: "none"
        case .monthly: "monthly"
        case .quarterly: "quarterly"
        case .semiannual: "semiannual"
        case .annual: "annual"
        case .everyMonths(let months): "every\(months)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "none": self = .none
        case "monthly": self = .monthly
        case "quarterly": self = .quarterly
        case "semiannual": self = .semiannual
        case "annual": self = .annual
        default:
            guard rawValue.hasPrefix("every"),
                  let months = Int(rawValue.dropFirst(5)) else { return nil }
            self = Self.normalised(.everyMonths(months))
        }
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InterestFrequency(rawValue: raw) ?? .none
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
