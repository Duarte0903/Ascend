import Foundation

struct DerivedRecord: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let balances: [UUID: Double]
    let total: Double
    let usable: Double
    /// nil for the first record — a change with nothing to compare to is
    /// undefined, not zero.
    let changeAmount: Double?
    /// nil when the previous total is zero.
    let changePercent: Double?
    let savingsRate: Double?

    func amount(for accountID: UUID) -> Double { balances[accountID] ?? 0 }
}

enum LedgerEngine {
    /// Derives every computed column for every record, oldest first.
    static func derive(_ input: PortfolioInput) -> [DerivedRecord] {
        let sorted = input.records.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let usableIDs = Set(input.accounts.filter(\.includeInUsable).map(\.id))
        let savingsIDs = Set(input.accounts.filter(\.countsAsSavings).map(\.id))
        let allIDs = input.accounts.map(\.id)

        var result: [DerivedRecord] = []
        var previous: RecordInput?

        for record in sorted {
            let total = allIDs.reduce(0) { $0 + record.amount(for: $1) }
            let usable = allIDs.filter(usableIDs.contains)
                .reduce(0) { $0 + record.amount(for: $1) }

            var changeAmount: Double?
            var changePercent: Double?
            var savingsRate: Double?

            if let previous {
                let previousTotal = allIDs.reduce(0) { $0 + previous.amount(for: $1) }
                changeAmount = total - previousTotal
                let savingsDelta = allIDs.filter(savingsIDs.contains)
                    .reduce(0) { $0 + record.amount(for: $1) - previous.amount(for: $1) }
                if previousTotal != 0 {
                    changePercent = (total - previousTotal) / previousTotal
                    savingsRate = savingsDelta / previousTotal
                }
            }

            result.append(DerivedRecord(
                id: record.id, date: record.date, balances: record.balances,
                total: total, usable: usable,
                changeAmount: changeAmount, changePercent: changePercent,
                savingsRate: savingsRate))
            previous = record
        }
        return result
    }
}
