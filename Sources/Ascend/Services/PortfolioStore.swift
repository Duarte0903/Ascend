import Foundation

/// Converts persisted models into the pure value types the engine consumes.
/// This is the only bridge between SwiftData and Engine.
enum PortfolioStore {
    static func input(accounts: [Account],
                      records: [BalanceRecord],
                      settings: AppSettings,
                      expenses: [Expense] = []) -> PortfolioInput {
        PortfolioInput(
            accounts: accounts.filter { !$0.isArchived }
                              .sorted { $0.sortOrder < $1.sortOrder }
                              .map { $0.toInfo() },
            records: records.map { $0.toInput() },
            expenses: expenses.sorted { $0.sortOrder < $1.sortOrder }.map { $0.toInput() },
            targetNetWorth: settings.targetNetWorth,
            monthlyNetIncome: settings.monthlyNetIncome,
            projectionHorizonMonths: settings.projectionHorizonMonths)
    }

    /// Includes archived accounts, so historical totals stay intact after an
    /// account is archived.
    static func historicalInput(accounts: [Account],
                                records: [BalanceRecord],
                                settings: AppSettings,
                                expenses: [Expense] = []) -> PortfolioInput {
        var input = self.input(accounts: accounts, records: records,
                               settings: settings, expenses: expenses)
        input.accounts = accounts.sorted { $0.sortOrder < $1.sortOrder }.map { $0.toInfo() }
        return input
    }
}
