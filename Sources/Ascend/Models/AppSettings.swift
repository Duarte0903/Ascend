import Foundation
import SwiftData

@Model
final class AppSettings {
    var targetNetWorth: Double = 25_000
    var monthlyNetIncome: Double = 0
    var maxMonthlyExpenses: Double = 0
    var projectionHorizonMonths: Int = 60
    /// The combined return the investments are aiming to beat, as a fraction.
    var investmentReturnTarget: Double = 0.03

    // MARK: - Tax

    /// When on, monthly net income is worked out from the salary below rather
    /// than typed into Projections.
    var taxEnabled: Bool = false
    /// Everything the employer pays over the year, food allowance included —
    /// the figure a contract states. The salary the tax is worked out on is
    /// this less the allowance, which the app knows from the daily rate.
    var grossAnnualIncome: Double = 0

    /// The year's meal allowance, at the rate and number of days set below.
    var mealAllowanceAnnual: Double {
        max(0, mealAllowancePerDay) * Double(max(0, mealAllowanceDaysPerYear))
    }

    /// What is left once the allowance is taken out: the pay the bands and the
    /// contribution actually apply to.
    var salaryExcludingMealAllowance: Double {
        max(0, grossAnnualIncome - mealAllowanceAnnual)
    }
    /// Written by the version that let part of the salary sit outside the
    /// contribution base. No longer read: contributions are charged on the
    /// whole salary.
    var taxIncomeWithoutSocialSecurity: Double = 0
    var taxRegionRaw: String = TaxRegion.mainland.rawValue
    var taxDependents: Int = 0
    var taxJointAssessment: Bool = false
    /// The calendar year the young-taxpayer scheme started for you; 0 when it
    /// doesn't apply. Stored rather than the year-of-scheme so it never needs
    /// touching again — which year you are in follows from the tax year.
    var taxYoungTaxpayerFirstYear: Int = 0
    /// Remembers the starting year while the scheme is switched off.
    var taxYoungTaxpayerRememberedFirstYear: Int = 0
    /// Fiscal years in which the exemption was not claimed, comma separated.
    /// Stored as text so the model keeps to scalars.
    var taxYoungTaxpayerSkippedRaw: String = ""

    /// Written by versions that asked which year of the scheme you were in.
    /// Read once by `SeedData.migrateYoungTaxpayerStart` and then cleared.
    var taxYoungTaxpayerYear: Int = 0
    var taxYoungTaxpayerLastYear: Int = 1
    var taxOtherCredits: Double = 0
    /// Meal allowance, stored as it is paid: a rate per working day.
    var mealAllowancePerDay: Double = 0
    /// Days off that carry no allowance, and any municipal holiday.
    var mealAllowanceVacationDays: Int = 22
    var mealAllowanceExtraHolidays: Int = 1
    /// 0 uses the calendar. Anything else pins the count, for a contract that
    /// pays a flat number of days regardless.
    var mealAllowanceDaysOverride: Int = 0
    var mealAllowanceOnCard: Bool = true
    /// Off by default: a meal card buys food and nothing else.
    var mealAllowanceSpendable: Bool = false
    /// Whether IRS is withheld monthly before the money arrives.
    var taxWithholdingAtSource: Bool = true
    /// The rate from the payslip, when known. 0 means it is not.
    var taxWithholdingRate: Double = 0
    /// Written by the version that chose between withholding and assessment as
    /// the basis for monthly income. No longer read.
    var taxUseWithholdingForIncome: Bool = true
    /// The rate table, stored encoded so it can be edited without a rebuild.
    /// Empty means "use the built-in table".
    var taxTableData: Data = Data()

    /// Days the allowance is paid for: worked out from the tax year's calendar
    /// unless a figure has been pinned.
    var mealAllowanceDaysPerYear: Int {
        guard mealAllowanceDaysOverride <= 0 else { return mealAllowanceDaysOverride }
        return WorkingCalendar.workingDays(inYear: taxTable.year,
                                           vacationDays: mealAllowanceVacationDays,
                                           extraHolidays: mealAllowanceExtraHolidays)
    }

    /// Whether the young-taxpayer scheme applies.
    ///
    /// Derived from the starting year rather than stored beside it: a separate
    /// flag could disagree with the year it guards.
    var taxYoungTaxpayerEnabled: Bool {
        get { taxYoungTaxpayerFirstYear > 0 }
        set {
            // A no-op when the state already matches. Without this, writing
            // `true` over an already-on switch — which a SwiftUI toggle does —
            // would overwrite the starting year with the remembered one.
            guard newValue != taxYoungTaxpayerEnabled else { return }
            if newValue {
                taxYoungTaxpayerFirstYear = taxYoungTaxpayerRememberedFirstYear > 0
                    ? taxYoungTaxpayerRememberedFirstYear
                    : taxTable.year
            } else {
                taxYoungTaxpayerRememberedFirstYear = taxYoungTaxpayerFirstYear
                taxYoungTaxpayerFirstYear = 0
            }
        }
    }

    /// Fiscal years the exemption was not claimed in. They consume none of the
    /// scheme, so each one pushes its final year out by one.
    var taxYoungTaxpayerSkipped: Set<Int> {
        get {
            Set(taxYoungTaxpayerSkippedRaw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        set {
            // Pruned on the way in, so a year the scheme never reaches cannot
            // be stored and then counted in a total nothing on screen explains.
            let pruned = taxTable.prunedSkips(startingIn: taxYoungTaxpayerFirstYear,
                                              skipping: newValue)
            taxYoungTaxpayerSkippedRaw = pruned.sorted().map(String.init).joined(separator: ",")
        }
    }

    func toggleYoungTaxpayerYearClaimed(_ year: Int) {
        var skipped = taxYoungTaxpayerSkipped
        if skipped.contains(year) { skipped.remove(year) } else { skipped.insert(year) }
        taxYoungTaxpayerSkipped = skipped
    }

    /// Which year of the scheme the tax year is, or nil once it has run out —
    /// so the exemption expires by itself rather than being switched off by
    /// hand ten years from now.
    var taxYoungTaxpayerSchemeYear: Int? {
        taxTable.youngTaxpayerYear(startingIn: taxYoungTaxpayerFirstYear,
                                   skipping: taxYoungTaxpayerSkipped)
    }

    var taxRegion: TaxRegion {
        get { TaxRegion(rawValue: taxRegionRaw) ?? .mainland }
        set { taxRegionRaw = newValue.rawValue }
    }

    /// The stored table, falling back to the built-in one whenever nothing has
    /// been saved or what was saved can no longer be read.
    var taxTable: TaxYear {
        get {
            guard !taxTableData.isEmpty,
                  let decoded = try? JSONDecoder().decode(TaxYear.self, from: taxTableData)
            else { return .portugalDefaults }
            return decoded
        }
        set { taxTableData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// What the engine needs, or nil when the tax screen is switched off.
    /// What the engine needs, or nil when the tax screen is not feeding
    /// Projections — either because it is switched off or because there is no
    /// salary to work from.
    var taxInput: TaxInput? {
        guard taxEnabled, grossAnnualIncome > 0 else { return nil }
        return TaxInput(grossAnnual: salaryExcludingMealAllowance,
                        region: taxRegion,
                        dependents: taxDependents,
                        jointTaxation: taxJointAssessment,
                        youngTaxpayerYear: taxYoungTaxpayerSchemeYear,
                        otherCredits: taxOtherCredits,
                        mealAllowancePerDay: mealAllowancePerDay,
                        mealAllowanceDaysPerYear: Double(mealAllowanceDaysPerYear),
                        mealAllowanceOnCard: mealAllowanceOnCard,
                        mealAllowanceSpendable: mealAllowanceSpendable,
                        withholdingAtSource: taxWithholdingAtSource,
                        withholdingRate: taxWithholdingRate,
                        table: taxTable)
    }

    init(targetNetWorth: Double = 25_000, monthlyNetIncome: Double = 0,
         maxMonthlyExpenses: Double = 0, projectionHorizonMonths: Int = 60,
         investmentReturnTarget: Double = 0.03) {
        self.targetNetWorth = targetNetWorth
        self.monthlyNetIncome = monthlyNetIncome
        self.maxMonthlyExpenses = maxMonthlyExpenses
        self.projectionHorizonMonths = projectionHorizonMonths
        self.investmentReturnTarget = investmentReturnTarget
    }
}
