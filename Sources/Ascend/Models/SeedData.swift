import Foundation
import SwiftData

/// Populates the store with the source workbook on first launch.
enum SeedData {
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard existing.isEmpty else { return }

        let categories = AccountCategory.seedDefaults(into: context)
        func category(_ name: String) -> AccountCategory? {
            categories.first { $0.name == name }
        }

        let current = Account(name: "Current Account",
                          note: "Everyday account — income lands here",
                          categoryID: category("Main")?.id, legacyKind: "main",
                          colorHex: "#1F6E8C", sortOrder: 0,
                          includeInUsable: true, countsAsSavings: false,
                          isLeftoverDestination: true)
        let savings = Account(name: "Savings", note: "Short-term savings",
                              categoryID: category("Savings")?.id, legacyKind: "savings",
                              colorHex: "#7A5EA6", sortOrder: 1,
                              includeInUsable: true, countsAsSavings: true,
                              expectedAnnualReturn: 0.01, monthlyContribution: 150,
                              amountInvested: 750)
        let brokerage = Account(name: "Brokerage", note: "Long-term investing",
                          categoryID: category("Investment")?.id, legacyKind: "investment",
                          colorHex: "#C2703D", sortOrder: 2,
                          includeInUsable: true, countsAsSavings: true,
                          expectedAnnualReturn: 0.06, monthlyContribution: 150,
                          amountInvested: 600)
        let mealCard = Account(name: "Meal Card",
                              note: "Food only — not spendable cash",
                              categoryID: category("Restricted")?.id, legacyKind: "restricted",
                              colorHex: "#A34A5E", sortOrder: 3,
                              includeInUsable: false, countsAsSavings: false)
        for account in [current, savings, brokerage, mealCard] { context.insert(account) }

        // Deliberately round, obviously invented figures. Two records share a
        // date so the same-date ordering behaviour is exercised out of the box.
        let rows: [(Int, Int, Int, Double, Double, Double, Double)] = [
            (1, 3, 2026, 1000, 500, 500, 100),
            (1, 3, 2026, 1100, 500, 500, 100),
            (15, 3, 2026, 1100, 700, 600, 100),
            (1, 4, 2026, 1500, 800, 700, 100),
        ]
        let calendar = Calendar(identifier: .gregorian)
        let seedEpoch = Date(timeIntervalSince1970: 1_750_000_000)
        for (offset, row) in rows.enumerated() {
            let (day, month, year, a, b, c, d) = row
            var comps = DateComponents()
            comps.day = day; comps.month = month; comps.year = year; comps.hour = 12
            // createdAt increases with row order so the two records sharing
            // 01/07/2026 keep the workbook's sequence.
            let record = BalanceRecord(date: calendar.date(from: comps)!,
                                       createdAt: seedEpoch.addingTimeInterval(Double(offset)))
            context.insert(record)
            record.setAmount(a, for: current.id)
            record.setAmount(b, for: savings.id)
            record.setAmount(c, for: brokerage.id)
            record.setAmount(d, for: mealCard.id)
        }

        context.insert(AppSettings(targetNetWorth: 10_000, monthlyNetIncome: 2_000,
                                   maxMonthlyExpenses: 500, projectionHorizonMonths: 60,
                                   investmentReturnTarget: 0.03))

        // Commitments totalling 500 €/month, including a yearly bill so the
        // frequency normalisation is visible without editing anything.
        let expenseCategories = ExpenseCategory.seedDefaults(into: context)
        func expenseCategory(_ name: String) -> UUID? {
            expenseCategories.first { $0.name == name }?.id
        }
        let seededExpenses: [(String, Double, ExpenseFrequency, String)] = [
            ("Rent", 350, .monthly, "Housing"),
            ("Phone", 20, .monthly, "Utilities"),
            ("Transport pass", 30, .monthly, "Transport"),
            ("Home insurance", 1_200, .yearly, "Housing"),
        ]
        for (index, item) in seededExpenses.enumerated() {
            context.insert(Expense(name: item.0, amount: item.1, frequency: item.2,
                                   categoryID: expenseCategory(item.3),
                                   accountID: current.id, sortOrder: index))
        }

        try? context.save()
    }

    /// Moves accounts still carrying the original seed colours onto the current
    /// palette. Only exact old defaults are touched, so a colour you chose
    /// yourself is never overwritten, and re-running this changes nothing.
    static func migrateLegacyColors(_ context: ModelContext) {
        let replacements = ["#2E7D32": "#1F6E8C",
                            "#1565C0": "#7A5EA6",
                            "#EF6C00": "#C2703D",
                            "#6A1B9A": "#A34A5E"]
        guard let accounts = try? context.fetch(FetchDescriptor<Account>()) else { return }
        var changed = false
        for account in accounts {
            if let replacement = replacements[account.colorHex.uppercased()] {
                account.colorHex = replacement
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Moves a store created before the Expenses screen onto the new model.
    /// The old typed `maxMonthlyExpenses` becomes a single expense of the same
    /// amount, so the projection figures do not shift under the user.
    static func migrateExpenses(_ context: ModelContext) {
        var categories = (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? []
        if categories.isEmpty {
            categories = ExpenseCategory.seedDefaults(into: context)
        }

        let existing = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        guard existing.isEmpty else { return }

        let settings = self.settings(in: context)
        guard settings.maxMonthlyExpenses > 0 else { try? context.save(); return }

        let other = categories.first { $0.name == "Other" } ?? categories.last
        context.insert(Expense(name: "Monthly expenses",
                               note: "Carried over from the single expenses figure. Split it into real commitments whenever you like.",
                               amount: settings.maxMonthlyExpenses,
                               frequency: .monthly,
                               categoryID: other?.id,
                               sortOrder: 0))
        try? context.save()
    }

    /// Points expenses written before the paying-account field at the main
    /// account, so none is left without one.
    static func migrateExpenseAccounts(_ context: ModelContext) {
        guard let expenses = try? context.fetch(FetchDescriptor<Expense>()) else { return }
        guard let fallback = ExpenseService.defaultAccountID(in: context) else { return }
        var changed = false
        for expense in expenses where expense.accountID == nil {
            expense.accountID = fallback
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Brings a store created before categories existed up to date: seeds the
    /// four defaults if absent, then attaches every unassigned account to the
    /// category matching the type it used to have.
    static func migrateCategories(_ context: ModelContext) {
        var categories = (try? context.fetch(FetchDescriptor<AccountCategory>())) ?? []
        if categories.isEmpty {
            categories = AccountCategory.seedDefaults(into: context)
        }

        guard let accounts = try? context.fetch(FetchDescriptor<Account>()) else { return }
        let byLegacyKey = Dictionary(uniqueKeysWithValues:
            AccountCategory.templates.map { ($0.legacyKey, $0.name) })

        var changed = false
        for account in accounts where account.categoryID == nil {
            let name = byLegacyKey[account.kindRaw] ?? "Main"
            if let match = categories.first(where: { $0.name == name }) {
                account.categoryID = match.id
                changed = true
            }
        }
        if changed || !categories.isEmpty { try? context.save() }
    }

    /// Moves a store that recorded which year of the young-taxpayer scheme you
    /// were in onto the year it started, which never needs touching again.
    ///
    /// The old field is cleared as it is read, so this cannot run twice and
    /// switch the scheme back on after it has been turned off.
    static func migrateYoungTaxpayerStart(_ context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<AppSettings>()) else { return }
        var changed = false
        for settings in all where settings.taxYoungTaxpayerYear > 0 {
            if settings.taxYoungTaxpayerFirstYear == 0 {
                settings.taxYoungTaxpayerFirstYear =
                    settings.taxTable.year - settings.taxYoungTaxpayerYear + 1
            }
            settings.taxYoungTaxpayerYear = 0
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Moves a saved rate table still carrying the meal allowance limits the
    /// app used to ship onto the current ones.
    ///
    /// Only those exact figures are touched, so a limit set by hand is never
    /// overwritten, and re-running this changes nothing.
    static func migrateMealAllowanceLimits(_ context: ModelContext) {
        let shipped = (cash: 6.00, card: 10.20)
        let current = TaxYear.portugalDefaults
        guard let all = try? context.fetch(FetchDescriptor<AppSettings>()) else { return }
        var changed = false
        for settings in all {
            var table = settings.taxTable
            var edited = false
            // Checked one at a time rather than as a pair: someone who changed
            // the cash limit — irrelevant when you are paid on a card — should
            // still have the card limit brought up to date.
            if abs(table.mealAllowanceCashLimit - shipped.cash) < 0.005 {
                table.mealAllowanceCashLimit = current.mealAllowanceCashLimit
                edited = true
            }
            if abs(table.mealAllowanceCardLimit - shipped.card) < 0.005 {
                table.mealAllowanceCardLimit = current.mealAllowanceCardLimit
                edited = true
            }
            if edited { settings.taxTable = table; changed = true }
        }
        if changed { try? context.save() }
    }

    /// The escalões the app shipped with before the 2026 ones.
    private static let bands2025: [TaxBracket] = [
        TaxBracket(upperLimit: 8_059, rate: 0.130),
        TaxBracket(upperLimit: 12_160, rate: 0.165),
        TaxBracket(upperLimit: 17_233, rate: 0.220),
        TaxBracket(upperLimit: 22_306, rate: 0.250),
        TaxBracket(upperLimit: 28_400, rate: 0.320),
        TaxBracket(upperLimit: 41_629, rate: 0.355),
        TaxBracket(upperLimit: 44_987, rate: 0.435),
        TaxBracket(upperLimit: 83_696, rate: 0.450),
        TaxBracket(upperLimit: nil, rate: 0.480),
    ]

    /// Moves a saved table still on the previous year's escalões onto the
    /// current ones. Only that exact scale is replaced, so a band edited by
    /// hand keeps the whole table as it was.
    static func migrateTaxBands(_ context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<AppSettings>()) else { return }
        var changed = false
        for settings in all where settings.taxTable.brackets == bands2025 {
            var table = settings.taxTable
            table.brackets = TaxYear.portugalDefaults.brackets
            settings.taxTable = table
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Clears young-taxpayer skips left beyond the end of the scheme by an
    /// earlier version, which counted them but never showed them.
    static func migrateYoungTaxpayerSkips(_ context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<AppSettings>()) else { return }
        var changed = false
        for settings in all where !settings.taxYoungTaxpayerSkipped.isEmpty {
            let before = settings.taxYoungTaxpayerSkipped
            // The setter prunes, so writing it back is the whole repair.
            settings.taxYoungTaxpayerSkipped = before
            if settings.taxYoungTaxpayerSkipped != before { changed = true }
        }
        if changed { try? context.save() }
    }

    static func settings(in context: ModelContext) -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        return created
    }
}
