import Foundation
import SwiftData

enum SideHustleError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case notPositive

    var errorDescription: String? {
        switch self {
        case .emptyName: "Give the side hustle a name."
        case .duplicateName: "A side hustle with that name already exists."
        case .notPositive: "Enter what you invoiced."
        }
    }
}

enum SideHustleService {

    static func all(in context: ModelContext) -> [SideHustle] {
        ((try? context.fetch(FetchDescriptor<SideHustle>())) ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @discardableResult
    static func create(name: String,
                       activity: SideHustleActivity = .professionalServices,
                       in context: ModelContext) throws -> SideHustle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SideHustleError.emptyName }
        let existing = all(in: context)
        guard !existing.contains(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw SideHustleError.duplicateName }

        // The palette in order, so two hustles created in a row look apart.
        let palette = Theme.accountPalette
        let hustle = SideHustle(name: trimmed,
                                colorHex: palette[existing.count % palette.count],
                                activity: activity,
                                sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(hustle)
        try? context.save()
        return hustle
    }

    static func rename(_ hustle: SideHustle, to name: String,
                       in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SideHustleError.emptyName }
        guard !all(in: context).contains(where: {
            $0.id != hustle.id
                && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw SideHustleError.duplicateName }
        hustle.name = trimmed
        try? context.save()
    }

    /// Deleting takes the earnings with it — they describe this work and
    /// nothing else, so leaving them behind would strand money with no source.
    static func delete(_ hustle: SideHustle, in context: ModelContext) {
        context.delete(hustle)
        try? context.save()
    }

    static func setArchived(_ archived: Bool, on hustle: SideHustle,
                            in context: ModelContext) {
        hustle.isArchived = archived
        try? context.save()
    }

    @discardableResult
    static func record(amount: Double, on date: Date, note: String = "",
                       isPaid: Bool = true, for hustle: SideHustle,
                       in context: ModelContext) throws -> SideHustleEarning {
        guard amount > 0 else { throw SideHustleError.notPositive }
        let earning = SideHustleEarning(date: date, amount: Money.cents(amount),
                                        note: note, isPaid: isPaid, hustle: hustle)
        context.insert(earning)
        hustle.earnings = (hustle.earnings ?? []) + [earning]
        try? context.save()
        return earning
    }

    static func remove(_ earning: SideHustleEarning, in context: ModelContext) {
        earning.hustle?.earnings?.removeAll { $0.id == earning.id }
        context.delete(earning)
        try? context.save()
    }

    static func update(_ earning: SideHustleEarning,
                       amount: Double? = nil, date: Date? = nil,
                       note: String? = nil, isPaid: Bool? = nil,
                       in context: ModelContext) {
        if let amount { earning.amount = Money.cents(max(0, amount)) }
        if let date { earning.date = date }
        if let note { earning.note = note }
        if let isPaid { earning.isPaid = isPaid }
        try? context.save()
    }

    /// The rules the year is judged against, taken from the Tax screen where
    /// it is set up so the same marginal rate drives both screens.
    static func rules(settings: AppSettings, hustle: SideHustle?) -> SideHustleRules {
        let table = settings.taxTable
        var marginal = settings.sideHustleIRSRate
        var derived = false
        var share: Double = 0
        var remaining: Double = 0
        if let input = settings.taxAssessmentInput {
            let assessment = TaxEngine.assess(input)
            marginal = assessment.marginalIRSRate
            derived = true
            // The same scheme year the salary is claiming, and whatever is
            // left of the one allowance the two categories share.
            if let schemeYear = settings.taxYoungTaxpayerSchemeYear,
               schemeYear >= 1, schemeYear <= table.youngExemptionShares.count {
                share = table.youngExemptionShares[schemeYear - 1]
                let cap = Money.cents(table.youngExemptionCapMultiple
                                      * table.socialSupportIndex)
                remaining = Money.cents(max(0, cap - assessment.exemptIncome))
            }
        }
        let months = hustle.map { $0.monthsActive > 0 ? $0.monthsActive : 12 } ?? 12
        return SideHustleRules(marginalIRSRate: marginal,
                               derivesIRSRate: derived,
                               contributionRate: settings.sideHustleContributionRate,
                               socialSupportIndex: table.socialSupportIndex,
                               hasEmployment: settings.taxAssessmentInput != nil,
                               monthsActive: months,
                               youngExemptionShare: share,
                               youngExemptionRemaining: remaining)
    }
}
