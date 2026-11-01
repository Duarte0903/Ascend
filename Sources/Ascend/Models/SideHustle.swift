import Foundation
import SwiftData

/// Work done on the side, invoiced rather than salaried.
///
/// Kept apart from accounts and expenses because it is neither: it is income
/// that arrives with tax still owed on it, and what that tax comes to depends
/// on what the work is.
@Model
final class SideHustle {
    var id: UUID = UUID()
    var name: String = ""
    var note: String = ""
    var colorHex: String = "#7A5EA6"
    var activityRaw: String = SideHustleActivity.professionalServices.rawValue
    var contributionsRaw: String = SideHustleContributions.automatic.rawValue
    /// Months of the year this was running, which is what the contribution
    /// exemption ceiling is measured against. 0 means the whole year.
    var monthsActive: Int = 0
    var isArchived: Bool = false
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \SideHustleEarning.hustle)
    var earnings: [SideHustleEarning]? = []

    var activity: SideHustleActivity {
        get { SideHustleActivity(rawValue: activityRaw) ?? .professionalServices }
        set { activityRaw = newValue.rawValue }
    }

    var contributions: SideHustleContributions {
        get { SideHustleContributions(rawValue: contributionsRaw) ?? .automatic }
        set { contributionsRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, note: String = "",
         colorHex: String = "#7A5EA6",
         activity: SideHustleActivity = .professionalServices,
         contributions: SideHustleContributions = .automatic,
         monthsActive: Int = 0, isArchived: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.note = note
        self.colorHex = colorHex
        self.activityRaw = activity.rawValue
        self.contributionsRaw = contributions.rawValue
        self.monthsActive = monthsActive
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    func toInput() -> SideHustleInput {
        SideHustleInput(id: id, name: name, colorHex: colorHex,
                        activity: activity, contributions: contributions,
                        isArchived: isArchived, sortOrder: sortOrder,
                        earnings: (earnings ?? []).map { $0.toInput() })
    }
}

/// One payment, as invoiced.
@Model
final class SideHustleEarning {
    var id: UUID = UUID()
    var date: Date = Date()
    /// What was invoiced, before IRS or contributions.
    var amount: Double = 0
    var note: String = ""
    /// Whether the money has arrived. Defaults to true so earnings recorded
    /// before this existed stay what they were: money already received.
    var isPaid: Bool = true
    var hustle: SideHustle?

    init(id: UUID = UUID(), date: Date, amount: Double, note: String = "",
         isPaid: Bool = true, hustle: SideHustle? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.note = note
        self.isPaid = isPaid
        self.hustle = hustle
    }

    func toInput() -> SideHustleEarningInput {
        SideHustleEarningInput(id: id, date: date, amount: amount, note: note,
                               isPaid: isPaid)
    }
}
