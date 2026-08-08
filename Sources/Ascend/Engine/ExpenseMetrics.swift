import Foundation

struct ExpenseCategoryTotal: Identifiable, Sendable {
    /// nil is the bucket for expenses with no category assigned.
    let categoryID: UUID?
    var id: String { categoryID?.uuidString ?? "uncategorised" }
    let name: String
    let monthlyAmount: Double
    let share: Double
    let count: Int
}

struct ExpenseMetrics: Sendable {
    var monthlyTotal: Double
    var yearlyTotal: Double
    var activeCount: Int
    var pausedCount: Int
    var largest: ExpenseInput?
    var byCategory: [ExpenseCategoryTotal]

    /// `categoryNames` keeps the engine free of any model type while still
    /// letting it group — names are looked up, never stored here.
    static func compute(expenses: [ExpenseInput],
                        categoryNames: [UUID: String],
                        categoryOrder: [UUID] = []) -> ExpenseMetrics {
        let active = expenses.filter(\.isActive)
        let monthlyTotal = active.reduce(0) { $0 + $1.monthlyAmount }

        var totals: [UUID?: (amount: Double, count: Int)] = [:]
        for expense in active {
            let existing = totals[expense.categoryID] ?? (0, 0)
            totals[expense.categoryID] = (existing.amount + expense.monthlyAmount,
                                          existing.count + 1)
        }

        let ordered = totals.map { key, value in
            ExpenseCategoryTotal(
                categoryID: key,
                name: key.flatMap { categoryNames[$0] } ?? "Uncategorised",
                monthlyAmount: value.amount,
                share: monthlyTotal == 0 ? 0 : value.amount / monthlyTotal,
                count: value.count)
        }
        .sorted { lhs, rhs in
            // Follow the user's category order, with the uncategorised bucket last.
            let lhsRank = lhs.categoryID.flatMap { categoryOrder.firstIndex(of: $0) } ?? Int.max
            let rhsRank = rhs.categoryID.flatMap { categoryOrder.firstIndex(of: $0) } ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name < rhs.name
        }

        return ExpenseMetrics(
            monthlyTotal: monthlyTotal,
            yearlyTotal: monthlyTotal * 12,
            activeCount: active.count,
            pausedCount: expenses.count - active.count,
            largest: active.max { $0.monthlyAmount < $1.monthlyAmount },
            byCategory: ordered)
    }
}
