import Foundation
import SwiftData

/// A recurring commitment. The sum of these, normalised to monthly, is what
/// Projections uses as monthly expenses.
@Model
final class Expense {
    var id: UUID = UUID()
    var name: String = ""
    var note: String = ""
    /// The amount as billed — see `frequency` for how often.
    var amount: Double = 0
    var frequencyRaw: String = ExpenseFrequency.monthly.rawValue
    var categoryID: UUID?
    /// Which account pays this. Defaults to the main account.
    var accountID: UUID?
    var isActive: Bool = true
    var sortOrder: Int = 0

    var frequency: ExpenseFrequency {
        get { ExpenseFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var monthlyAmount: Double { isActive ? amount * frequency.monthlyFactor : 0 }
    var yearlyAmount: Double { monthlyAmount * 12 }

    init(id: UUID = UUID(), name: String, note: String = "", amount: Double,
         frequency: ExpenseFrequency = .monthly, categoryID: UUID? = nil,
         accountID: UUID? = nil, isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.note = note
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.categoryID = categoryID
        self.accountID = accountID
        self.isActive = isActive
        self.sortOrder = sortOrder
    }

    func toInput() -> ExpenseInput {
        ExpenseInput(id: id, name: name, amount: amount, frequency: frequency,
                     categoryID: categoryID, accountID: accountID, isActive: isActive)
    }
}

/// A user-editable grouping for expenses, mirroring how account types work.
@Model
final class ExpenseCategory {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#1F6E8C"
    var sortOrder: Int = 0

    init(id: UUID = UUID(), name: String, colorHex: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }

    /// Sensible starting groups for a fixed-cost list.
    static let templates: [(name: String, colorHex: String)] = [
        ("Housing", "#1F6E8C"),
        ("Utilities", "#3E7C59"),
        ("Transport", "#C2703D"),
        ("Food", "#A34A5E"),
        ("Subscriptions", "#7A5EA6"),
        ("Other", "#5B6C9B"),
    ]

    static func seedDefaults(into context: ModelContext) -> [ExpenseCategory] {
        templates.enumerated().map { index, template in
            let category = ExpenseCategory(name: template.name,
                                           colorHex: template.colorHex,
                                           sortOrder: index)
            context.insert(category)
            return category
        }
    }
}
