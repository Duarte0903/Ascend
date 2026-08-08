import Foundation
@testable import Ascend

/// The source workbook, expressed as engine input. Every expected value in the
/// test suite is traceable to net_worth_tracker_pro.pdf.
enum WorkbookFixture {
    static let cttID = UUID()
    static let revolutID = UUID()
    static let xtbID = UUID()
    static let edenredID = UUID()

    static let accounts: [AccountInfo] = [
        AccountInfo(id: cttID, name: "Banco CTT", colorHex: "#2E7D32",
                    sortOrder: 0, includeInUsable: true, countsAsSavings: false,
                    expectedAnnualReturn: 0, monthlyContribution: 0,
                    isLeftoverDestination: true),
        AccountInfo(id: revolutID, name: "Revolut", colorHex: "#1565C0",
                    sortOrder: 1, includeInUsable: true, countsAsSavings: true,
                    expectedAnnualReturn: 0.011, monthlyContribution: 100,
                    isLeftoverDestination: false),
        AccountInfo(id: xtbID, name: "XTB", colorHex: "#EF6C00",
                    sortOrder: 2, includeInUsable: true, countsAsSavings: true,
                    expectedAnnualReturn: 0.07, monthlyContribution: 100,
                    isLeftoverDestination: false),
        AccountInfo(id: edenredID, name: "Edenred", colorHex: "#6A1B9A",
                    sortOrder: 3, includeInUsable: false, countsAsSavings: false,
                    expectedAnnualReturn: 0, monthlyContribution: 0,
                    isLeftoverDestination: false),
    ]

    static func date(_ day: Int, _ month: Int, _ year: Int) -> Date {
        var c = DateComponents()
        c.day = day; c.month = month; c.year = year
        c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// `createdAt` increases with row order so the two records sharing
    /// 01/07/2026 keep the workbook's sequence.
    private static func created(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_750_000_000 + Double(offset))
    }

    static let records: [RecordInput] = [
        RecordInput(id: UUID(), date: date(1, 7, 2026), createdAt: created(0),
                    balances: [cttID: 6285.73, revolutID: 200.00, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(1, 7, 2026), createdAt: created(1),
                    balances: [cttID: 6235.73, revolutID: 250.00, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(2, 7, 2026), createdAt: created(2),
                    balances: [cttID: 6265.73, revolutID: 250.00, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(3, 7, 2026), createdAt: created(3),
                    balances: [cttID: 6265.73, revolutID: 250.02, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(4, 8, 2026), createdAt: created(4),
                    balances: [cttID: 6962.35, revolutID: 350.27, xtbID: 819.49, edenredID: 277.63]),
    ]

    static let rentID = UUID()
    static let insuranceID = UUID()

    /// Monthly expenses are now derived from commitments rather than typed.
    /// These add up to the workbook's original 200 €: 180 monthly plus a 240 €
    /// yearly premium, which normalises to 20 €/month.
    static let expenses: [ExpenseInput] = [
        ExpenseInput(id: rentID, name: "Rent", amount: 180, frequency: .monthly),
        ExpenseInput(id: insuranceID, name: "Insurance", amount: 240, frequency: .yearly),
    ]

    static let portfolio = PortfolioInput(
        accounts: accounts,
        records: records,
        expenses: expenses,
        targetNetWorth: 25_000,
        monthlyNetIncome: 1_117,
        projectionHorizonMonths: 60
    )
}
