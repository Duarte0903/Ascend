import Foundation

struct DashboardMetrics: Sendable {
    var currentNetWorth: Double?
    var usableCash: Double?
    var latestChangeAmount: Double?
    var latestChangePercent: Double?
    var totalGrowth: Double?
    var bestChange: Double?
    var averageChange: Double?
    var recordCount: Int
    var averageSavingsRate: Double?

    static func compute(records: [DerivedRecord]) -> DashboardMetrics {
        guard let latest = records.last, let first = records.first else {
            return DashboardMetrics(recordCount: 0)
        }
        let changes = records.compactMap(\.changeAmount)
        let savingsRates = records.compactMap(\.savingsRate)

        return DashboardMetrics(
            currentNetWorth: latest.total,
            usableCash: latest.usable,
            latestChangeAmount: latest.changeAmount,
            latestChangePercent: latest.changePercent,
            totalGrowth: latest.total - first.total,
            bestChange: changes.max(),
            averageChange: changes.isEmpty ? nil : changes.reduce(0, +) / Double(changes.count),
            recordCount: records.count,
            averageSavingsRate: savingsRates.isEmpty
                ? nil
                : savingsRates.reduce(0, +) / Double(savingsRates.count))
    }
}
