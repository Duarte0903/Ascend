import Foundation
import SwiftData

enum ExpenseError: LocalizedError, Equatable {
    case emptyName
    case emptyCategoryName
    case duplicateCategoryName
    case categoryInUse(expenses: Int)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Give the expense a name."
        case .emptyCategoryName:
            "Give the category a name."
        case .duplicateCategoryName:
            "A category with that name already exists."
        case .categoryInUse(let expenses):
            "\(expenses) expense\(expenses == 1 ? " uses" : "s use") this category. Move them elsewhere first."
        }
    }
}

enum ExpenseService {
    // MARK: - Expenses

    /// The account a new expense is paid from unless told otherwise: the one
    /// that receives the monthly leftover — the main account — falling back to
    /// the first active account.
    static func defaultAccountID(in context: ModelContext) -> UUID? {
        let accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
        return accounts.first(where: \.isLeftoverDestination)?.id ?? accounts.first?.id
    }

    @discardableResult
    static func create(name: String, amount: Double,
                       frequency: ExpenseFrequency = .monthly,
                       categoryID: UUID? = nil,
                       accountID: UUID? = nil,
                       in context: ModelContext) throws -> Expense {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseError.emptyName }

        let existing = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let expense = Expense(name: trimmed, amount: max(0, amount), frequency: frequency,
                              categoryID: categoryID,
                              accountID: accountID ?? defaultAccountID(in: context),
                              sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(expense)
        try? context.save()
        return expense
    }

    static func rename(_ expense: Expense, to name: String,
                       in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseError.emptyName }
        expense.name = trimmed
        try? context.save()
    }

    static func delete(_ expense: Expense, in context: ModelContext) {
        context.delete(expense)
        try? context.save()
    }

    static func move(_ expense: Expense, by offset: Int,
                     expenses: [Expense], in context: ModelContext) {
        var ordered = expenses.sorted { $0.sortOrder < $1.sortOrder }
        guard let index = ordered.firstIndex(where: { $0.id == expense.id }) else { return }
        let destination = index + offset
        guard ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
        for (position, item) in ordered.enumerated() { item.sortOrder = position }
        try? context.save()
    }

    // MARK: - Categories

    @discardableResult
    static func createCategory(name: String, colorHex: String,
                               in context: ModelContext) throws -> ExpenseCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseError.emptyCategoryName }

        let existing = (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? []
        guard !existing.contains(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw ExpenseError.duplicateCategoryName }

        let category = ExpenseCategory(name: trimmed, colorHex: colorHex,
                                       sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(category)
        try? context.save()
        return category
    }

    static func renameCategory(_ category: ExpenseCategory, to name: String,
                               in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseError.emptyCategoryName }
        let existing = (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? []
        guard !existing.contains(where: {
            $0.id != category.id
                && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw ExpenseError.duplicateCategoryName }
        category.name = trimmed
        try? context.save()
    }

    static func expensesUsing(_ category: ExpenseCategory, expenses: [Expense]) -> Int {
        expenses.filter { $0.categoryID == category.id }.count
    }

    /// Refused while in use, so an expense can never point at a category that
    /// no longer exists.
    static func deleteCategory(_ category: ExpenseCategory, expenses: [Expense],
                               in context: ModelContext) throws {
        let inUse = expensesUsing(category, expenses: expenses)
        guard inUse == 0 else { throw ExpenseError.categoryInUse(expenses: inUse) }

        let all = (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? []
        context.delete(category)
        for (position, item) in all.filter({ $0.id != category.id })
            .sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            item.sortOrder = position
        }
        try? context.save()
    }

    static func assign(_ expense: Expense, to category: ExpenseCategory?,
                       in context: ModelContext) {
        expense.categoryID = category?.id
        try? context.save()
    }

    static func assign(_ expense: Expense, toAccount account: Account?,
                       in context: ModelContext) {
        expense.accountID = account?.id
        try? context.save()
    }
}
