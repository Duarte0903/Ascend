import Foundation

struct GoalMetrics: Sendable {
    var target: Double
    var current: Double
    var remaining: Double
    var progress: Double?
    /// nil when average change per record is not positive — the goal would
    /// never be reached at the current rate.
    var estimatedRecordsToGoal: Int?

    static func compute(target: Double, dashboard: DashboardMetrics) -> GoalMetrics {
        let current = dashboard.currentNetWorth ?? 0
        let remaining = max(0, target - current)
        var estimate: Int?
        if remaining == 0 {
            estimate = 0
        } else if let average = dashboard.averageChange, average > 0 {
            estimate = Int((remaining / average).rounded(.up))
        }
        return GoalMetrics(
            target: target, current: current, remaining: remaining,
            progress: target == 0 ? nil : current / target,
            estimatedRecordsToGoal: estimate)
    }
}
