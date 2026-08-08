import Foundation

/// How often a commitment is actually billed. Everything is normalised to a
/// monthly figure so a yearly premium and a monthly subscription can sit in the
/// same list without you doing the division.
enum ExpenseFrequency: String, Codable, CaseIterable, Sendable, Identifiable {
    case monthly, quarterly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        }
    }

    /// Multiplier turning one billed amount into its monthly equivalent.
    var monthlyFactor: Double {
        switch self {
        case .monthly: 1
        case .quarterly: 1.0 / 3.0
        case .yearly: 1.0 / 12.0
        }
    }

    var occurrencesPerYear: Int {
        switch self {
        case .monthly: 12
        case .quarterly: 4
        case .yearly: 1
        }
    }
}

struct ExpenseInput: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// The amount as billed, not per month.
    var amount: Double
    var frequency: ExpenseFrequency
    var categoryID: UUID?
    /// Paused commitments stay in the list but stop counting.
    var isActive: Bool

    init(id: UUID, name: String, amount: Double,
         frequency: ExpenseFrequency = .monthly,
         categoryID: UUID? = nil, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.amount = amount
        self.frequency = frequency
        self.categoryID = categoryID
        self.isActive = isActive
    }

    /// What this commitment costs per month, or zero while paused.
    var monthlyAmount: Double {
        isActive ? amount * frequency.monthlyFactor : 0
    }
}
