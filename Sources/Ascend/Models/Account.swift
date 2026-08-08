import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    /// Free-text note — what this account is for, in your own words.
    var note: String = ""
    var categoryID: UUID?
    /// Retained only so accounts created before categories existed can be
    /// migrated onto one. Not used for anything else.
    var kindRaw: String = "main"
    var colorHex: String = "#1565C0"
    var sortOrder: Int = 0
    var includeInUsable: Bool = true
    var countsAsSavings: Bool = false
    var expectedAnnualReturn: Double = 0
    var monthlyContribution: Double = 0
    var isLeftoverDestination: Bool = false
    var isArchived: Bool = false
    var archivedAt: Date?

    init(id: UUID = UUID(), name: String, note: String = "",
         categoryID: UUID? = nil, legacyKind: String = "main", colorHex: String,
         sortOrder: Int, includeInUsable: Bool, countsAsSavings: Bool,
         expectedAnnualReturn: Double = 0, monthlyContribution: Double = 0,
         isLeftoverDestination: Bool = false) {
        self.id = id
        self.name = name
        self.note = note
        self.categoryID = categoryID
        self.kindRaw = legacyKind
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.includeInUsable = includeInUsable
        self.countsAsSavings = countsAsSavings
        self.expectedAnnualReturn = expectedAnnualReturn
        self.monthlyContribution = monthlyContribution
        self.isLeftoverDestination = isLeftoverDestination
    }

    func toInfo() -> AccountInfo {
        AccountInfo(id: id, name: name, colorHex: colorHex,
                    sortOrder: sortOrder, includeInUsable: includeInUsable,
                    countsAsSavings: countsAsSavings,
                    expectedAnnualReturn: expectedAnnualReturn,
                    monthlyContribution: monthlyContribution,
                    isLeftoverDestination: isLeftoverDestination)
    }
}
