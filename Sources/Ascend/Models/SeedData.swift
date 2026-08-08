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

        let ctt = Account(name: "Banco CTT", note: "Main current account — salary lands here",
                          categoryID: category("Main")?.id, legacyKind: "main",
                          colorHex: "#1F6E8C", sortOrder: 0,
                          includeInUsable: true, countsAsSavings: false,
                          isLeftoverDestination: true)
        let revolut = Account(name: "Revolut", note: "Short-term savings",
                              categoryID: category("Savings")?.id, legacyKind: "savings",
                              colorHex: "#7A5EA6", sortOrder: 1,
                              includeInUsable: true, countsAsSavings: true,
                              expectedAnnualReturn: 0.011, monthlyContribution: 100)
        let xtb = Account(name: "XTB", note: "Brokerage — long-term investing",
                          categoryID: category("Investment")?.id, legacyKind: "investment",
                          colorHex: "#C2703D", sortOrder: 2,
                          includeInUsable: true, countsAsSavings: true,
                          expectedAnnualReturn: 0.07, monthlyContribution: 100)
        let edenred = Account(name: "Edenred", note: "Meal card — food only, not spendable cash",
                              categoryID: category("Restricted")?.id, legacyKind: "restricted",
                              colorHex: "#A34A5E", sortOrder: 3,
                              includeInUsable: false, countsAsSavings: false)
        for account in [ctt, revolut, xtb, edenred] { context.insert(account) }

        let rows: [(Int, Int, Int, Double, Double, Double, Double)] = [
            (1, 7, 2026, 6285.73, 200.00, 710.85, 268.43),
            (1, 7, 2026, 6235.73, 250.00, 710.85, 268.43),
            (2, 7, 2026, 6265.73, 250.00, 710.85, 268.43),
            (3, 7, 2026, 6265.73, 250.02, 710.85, 268.43),
            (4, 8, 2026, 6962.35, 350.27, 819.49, 277.63),
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
            record.setAmount(a, for: ctt.id)
            record.setAmount(b, for: revolut.id)
            record.setAmount(c, for: xtb.id)
            record.setAmount(d, for: edenred.id)
        }

        context.insert(AppSettings(targetNetWorth: 25_000, monthlyNetIncome: 1_117,
                                   maxMonthlyExpenses: 200, projectionHorizonMonths: 60))

        // Expenses: the old single 200 € figure, broken into example commitments
        // that add up to the same monthly total.
        let expenseCategories = ExpenseCategory.seedDefaults(into: context)
        func expenseCategory(_ name: String) -> UUID? {
            expenseCategories.first { $0.name == name }?.id
        }
        let seededExpenses: [(String, Double, ExpenseFrequency, String)] = [
            ("Rent", 90, .monthly, "Housing"),
            ("Electricity and water", 35, .monthly, "Utilities"),
            ("Phone", 15, .monthly, "Utilities"),
            ("Transport pass", 30, .monthly, "Transport"),
            ("Streaming", 10, .monthly, "Subscriptions"),
            ("Home insurance", 240, .yearly, "Housing"),
        ]
        for (index, item) in seededExpenses.enumerated() {
            context.insert(Expense(name: item.0, amount: item.1, frequency: item.2,
                                   categoryID: expenseCategory(item.3), sortOrder: index))
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

    static func settings(in context: ModelContext) -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        return created
    }
}
