import Foundation
@testable import Ascend

/// The sample portfolio the whole suite asserts against.
///
/// Deliberately round, invented figures — no real balances live in this repo.
/// It mirrors `SeedData`, so a value proven here is the value a fresh install
/// shows. Two records share a date on purpose: their order decides the change
/// and savings-rate columns, so the ordering rule stays covered.
///
///  | Date       | Current | Savings | Brokerage | Meal | Total | Usable |
///  |------------|---------|---------|-----------|------|-------|--------|
///  | 01/03/2026 |   1 000 |     500 |       500 |  100 | 2 100 |  2 000 |
///  | 01/03/2026 |   1 100 |     500 |       500 |  100 | 2 200 |  2 100 |
///  | 15/03/2026 |   1 100 |     700 |       600 |  100 | 2 500 |  2 400 |
///  | 01/04/2026 |   1 500 |     800 |       700 |  100 | 3 100 |  3 000 |
enum WorkbookFixture {
    static let currentID = UUID()
    static let savingsID = UUID()
    static let brokerageID = UUID()
    static let mealCardID = UUID()

    static let accounts: [AccountInfo] = [
        AccountInfo(id: currentID, name: "Current Account", colorHex: "#1F6E8C",
                    sortOrder: 0, includeInUsable: true, countsAsSavings: false,
                    expectedAnnualReturn: 0, monthlyContribution: 0,
                    isLeftoverDestination: true),
        AccountInfo(id: savingsID, name: "Savings", colorHex: "#7A5EA6",
                    sortOrder: 1, includeInUsable: true, countsAsSavings: true,
                    expectedAnnualReturn: 0.01, monthlyContribution: 150,
                    isLeftoverDestination: false, amountInvested: 750),
        AccountInfo(id: brokerageID, name: "Brokerage", colorHex: "#C2703D",
                    sortOrder: 2, includeInUsable: true, countsAsSavings: true,
                    expectedAnnualReturn: 0.06, monthlyContribution: 150,
                    isLeftoverDestination: false, amountInvested: 600),
        AccountInfo(id: mealCardID, name: "Meal Card", colorHex: "#A34A5E",
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

    /// createdAt increases with row order, so the two records sharing
    /// 01/03/2026 keep their sequence rather than sorting arbitrarily.
    private static let epoch = Date(timeIntervalSince1970: 1_750_000_000)

    static let records: [RecordInput] = [
        RecordInput(id: UUID(), date: date(1, 3, 2026), createdAt: epoch,
                    balances: [currentID: 1000, savingsID: 500, brokerageID: 500, mealCardID: 100]),
        RecordInput(id: UUID(), date: date(1, 3, 2026), createdAt: epoch.addingTimeInterval(1),
                    balances: [currentID: 1100, savingsID: 500, brokerageID: 500, mealCardID: 100]),
        RecordInput(id: UUID(), date: date(15, 3, 2026), createdAt: epoch.addingTimeInterval(2),
                    balances: [currentID: 1100, savingsID: 700, brokerageID: 600, mealCardID: 100]),
        RecordInput(id: UUID(), date: date(1, 4, 2026), createdAt: epoch.addingTimeInterval(3),
                    balances: [currentID: 1500, savingsID: 800, brokerageID: 700, mealCardID: 100]),
    ]

    static let rentID = UUID()
    static let insuranceID = UUID()

    /// 400 monthly plus a 1 200 yearly premium (100 a month) — 500 a month.
    static let expenses: [ExpenseInput] = [
        ExpenseInput(id: rentID, name: "Rent", amount: 400, frequency: .monthly),
        ExpenseInput(id: insuranceID, name: "Insurance", amount: 1_200, frequency: .yearly),
    ]

    static let portfolio = PortfolioInput(
        accounts: accounts,
        records: records,
        expenses: expenses,
        targetNetWorth: 10_000,
        monthlyNetIncome: 2_000,
        projectionHorizonMonths: 60
    )
}
