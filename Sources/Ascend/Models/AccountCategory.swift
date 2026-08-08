import Foundation
import SwiftData

/// A user-editable account type. Replaces the fixed Main/Savings/Investment/
/// Restricted enum: the four originals are seeded as ordinary rows, so they can
/// be renamed, re-defaulted or removed like any category you add yourself.
@Model
final class AccountCategory {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    /// Applied to new accounts of this category. Existing accounts are never
    /// retroactively changed — their own flags stay authoritative.
    var defaultIncludeInUsable: Bool = true
    var defaultCountsAsSavings: Bool = false
    var defaultAnnualReturn: Double = 0

    init(id: UUID = UUID(), name: String, sortOrder: Int,
         defaultIncludeInUsable: Bool, defaultCountsAsSavings: Bool,
         defaultAnnualReturn: Double = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.defaultIncludeInUsable = defaultIncludeInUsable
        self.defaultCountsAsSavings = defaultCountsAsSavings
        self.defaultAnnualReturn = defaultAnnualReturn
    }

    /// The starting set, matching the original workbook's four roles.
    /// `legacyKey` maps a pre-categories account onto its replacement.
    static let templates: [(legacyKey: String, name: String,
                            usable: Bool, savings: Bool, annualReturn: Double)] = [
        ("main", "Main", true, false, 0),
        ("savings", "Savings", true, true, 0),
        ("investment", "Investment", true, true, 0.05),
        ("restricted", "Restricted", false, false, 0),
    ]

    static func seedDefaults(into context: ModelContext) -> [AccountCategory] {
        templates.enumerated().map { index, template in
            let category = AccountCategory(
                name: template.name, sortOrder: index,
                defaultIncludeInUsable: template.usable,
                defaultCountsAsSavings: template.savings,
                defaultAnnualReturn: template.annualReturn)
            context.insert(category)
            return category
        }
    }
}
