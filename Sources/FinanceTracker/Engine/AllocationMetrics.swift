import Foundation

struct AllocationSlice: Identifiable, Sendable {
    var id: UUID { accountID }
    let accountID: UUID
    let name: String
    let colorHex: String
    let amount: Double
    let share: Double
}

struct AllocationMetrics: Sendable {
    var slices: [AllocationSlice]
    var total: Double
    var usable: Double

    /// Splits the most recent record across accounts.
    static func compute(accounts: [AccountInfo], records: [DerivedRecord]) -> AllocationMetrics {
        guard let latest = records.last else {
            return AllocationMetrics(slices: [], total: 0, usable: 0)
        }
        let sorted = accounts.sorted { $0.sortOrder < $1.sortOrder }
        let slices = sorted.map { account in
            let amount = latest.amount(for: account.id)
            return AllocationSlice(
                accountID: account.id, name: account.name, colorHex: account.colorHex,
                amount: amount,
                share: latest.total == 0 ? 0 : amount / latest.total)
        }
        return AllocationMetrics(slices: slices, total: latest.total, usable: latest.usable)
    }
}
