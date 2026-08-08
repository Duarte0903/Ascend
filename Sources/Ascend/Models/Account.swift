import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.main.rawValue
    var colorHex: String = "#1565C0"
    var sortOrder: Int = 0
    var includeInUsable: Bool = true
    var countsAsSavings: Bool = false
    var expectedAnnualReturn: Double = 0
    var monthlyContribution: Double = 0
    var isLeftoverDestination: Bool = false
    var isArchived: Bool = false
    var archivedAt: Date?

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .main }
        set { kindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, kind: AccountKind, colorHex: String,
         sortOrder: Int, includeInUsable: Bool, countsAsSavings: Bool,
         expectedAnnualReturn: Double = 0, monthlyContribution: Double = 0,
         isLeftoverDestination: Bool = false) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.includeInUsable = includeInUsable
        self.countsAsSavings = countsAsSavings
        self.expectedAnnualReturn = expectedAnnualReturn
        self.monthlyContribution = monthlyContribution
        self.isLeftoverDestination = isLeftoverDestination
    }

    func toInfo() -> AccountInfo {
        AccountInfo(id: id, name: name, kind: kind, colorHex: colorHex,
                    sortOrder: sortOrder, includeInUsable: includeInUsable,
                    countsAsSavings: countsAsSavings,
                    expectedAnnualReturn: expectedAnnualReturn,
                    monthlyContribution: monthlyContribution,
                    isLeftoverDestination: isLeftoverDestination)
    }
}
