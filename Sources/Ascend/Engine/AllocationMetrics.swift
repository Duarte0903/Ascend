import Foundation

struct AllocationSlice: Identifiable, Sendable {
    var id: UUID { accountID }
    let accountID: UUID
    let name: String
    let colorHex: String
    let amount: Double
    let share: Double
}

/// A bank, as far as the engine is concerned: something to label a total with.
struct BankInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
}

/// What is held at one bank, or — when `bankID` is nil — everything held at no
/// bank at all.
struct BankSlice: Identifiable, Sendable {
    let bankID: UUID?
    let name: String
    let colorHex: String
    let amount: Double
    let share: Double
    /// How many accounts make up the total, so a single-account bank does not
    /// look like a category.
    let accountCount: Int

    /// Stable across renames, and distinct for the unbanked bucket.
    var id: String { bankID?.uuidString ?? "unbanked" }
}

struct AllocationMetrics: Sendable {
    var slices: [AllocationSlice]
    var byBank: [BankSlice]
    var total: Double
    var usable: Double

    /// Splits the most recent record across accounts, and again across the
    /// banks holding them.
    static func compute(accounts: [AccountInfo],
                        records: [DerivedRecord],
                        banks: [BankInfo] = []) -> AllocationMetrics {
        guard let latest = records.last else {
            return AllocationMetrics(slices: [], byBank: [], total: 0, usable: 0)
        }
        let sorted = accounts.sorted { $0.sortOrder < $1.sortOrder }
        // Largest first: this screen answers "where is most of my money", and
        // the answer should be the first row, not somewhere down a list in
        // the order the accounts happened to be created. Ties keep the
        // accounts' own order, so equal balances do not reshuffle on refresh.
        let slices = sorted.map { account in
            let amount = latest.amount(for: account.id)
            return AllocationSlice(
                accountID: account.id, name: account.name, colorHex: account.colorHex,
                amount: amount,
                share: latest.total == 0 ? 0 : amount / latest.total)
        }
        .sorted { $0.amount > $1.amount }
        return AllocationMetrics(slices: slices,
                                 byBank: bankSlices(accounts: sorted, latest: latest,
                                                    banks: banks),
                                 total: latest.total, usable: latest.usable)
    }

    /// Totals by bank, in the banks' own order, with anything unbanked last.
    ///
    /// A bank with no accounts is left out rather than shown as zero: it is a
    /// bank you have not used, not a holding worth a row. The unbanked bucket
    /// appears only when something is actually in it.
    private static func bankSlices(accounts: [AccountInfo],
                                   latest: DerivedRecord,
                                   banks: [BankInfo]) -> [BankSlice] {
        var totals: [UUID?: (amount: Double, count: Int)] = [:]
        for account in accounts {
            // An account pointing at a bank that no longer exists counts as
            // unbanked rather than vanishing from the total.
            let known = account.bankID.flatMap { id in
                banks.contains { $0.id == id } ? id : nil
            }
            let amount = latest.amount(for: account.id)
            let existing = totals[known] ?? (0, 0)
            totals[known] = (existing.amount + amount, existing.count + 1)
        }

        func share(_ amount: Double) -> Double {
            latest.total == 0 ? 0 : amount / latest.total
        }

        var result = banks.sorted { $0.sortOrder < $1.sortOrder }.compactMap { bank -> BankSlice? in
            guard let entry = totals[bank.id] else { return nil }
            return BankSlice(bankID: bank.id, name: bank.name, colorHex: bank.colorHex,
                             amount: entry.amount, share: share(entry.amount),
                             accountCount: entry.count)
        }
        if let unbanked = totals[UUID?.none] {
            result.append(BankSlice(bankID: nil, name: "No bank",
                                    colorHex: "#8A8A8E",
                                    amount: unbanked.amount, share: share(unbanked.amount),
                                    accountCount: unbanked.count))
        }
        return result
    }
}
