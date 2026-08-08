import Foundation
import SwiftData

/// Populates the store with the source workbook on first launch.
enum SeedData {
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard existing.isEmpty else { return }

        let ctt = Account(name: "Banco CTT", kind: .main, colorHex: "#2E7D32", sortOrder: 0,
                          includeInUsable: true, countsAsSavings: false,
                          isLeftoverDestination: true)
        let revolut = Account(name: "Revolut", kind: .savings, colorHex: "#1565C0", sortOrder: 1,
                              includeInUsable: true, countsAsSavings: true,
                              expectedAnnualReturn: 0.011, monthlyContribution: 100)
        let xtb = Account(name: "XTB", kind: .investment, colorHex: "#EF6C00", sortOrder: 2,
                          includeInUsable: true, countsAsSavings: true,
                          expectedAnnualReturn: 0.07, monthlyContribution: 100)
        let edenred = Account(name: "Edenred", kind: .restricted, colorHex: "#6A1B9A", sortOrder: 3,
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
        try? context.save()
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
