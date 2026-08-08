import Foundation
import SwiftData

enum AccountError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case cannotArchiveLeftoverDestination
    case cannotArchiveLastAccount
    case needsLeftoverDestination

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Give the account a name."
        case .duplicateName:
            "An account with that name already exists."
        case .cannotArchiveLeftoverDestination:
            "This account receives the monthly leftover in projections. Choose a different leftover destination first."
        case .cannotArchiveLastAccount:
            "You need at least one active account."
        case .needsLeftoverDestination:
            "Pick an account to receive the monthly leftover."
        }
    }
}

enum AccountService {
    static func create(name: String, kind: AccountKind, colorHex: String,
                       in context: ModelContext) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyName }

        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard !existing.contains(where: {
            !$0.isArchived && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw AccountError.duplicateName }

        let account = Account(
            name: trimmed, kind: kind, colorHex: colorHex,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            includeInUsable: kind.defaultIncludeInUsable,
            countsAsSavings: kind.defaultCountsAsSavings)
        context.insert(account)
        try? context.save()
        return account
    }

    static func rename(_ account: Account, to name: String, in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyName }
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard !existing.contains(where: {
            $0.id != account.id && !$0.isArchived
                && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw AccountError.duplicateName }
        account.name = trimmed
        try? context.save()
    }

    static func archive(_ account: Account, in context: ModelContext) throws {
        guard !account.isLeftoverDestination else {
            throw AccountError.cannotArchiveLeftoverDestination
        }
        let active = ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { !$0.isArchived }
        guard active.count > 1 else { throw AccountError.cannotArchiveLastAccount }

        account.isArchived = true
        account.archivedAt = Date()
        try? context.save()
    }

    static func restore(_ account: Account, in context: ModelContext) {
        account.isArchived = false
        account.archivedAt = nil
        try? context.save()
    }

    /// Exactly one account can be the leftover destination. Pass nil to clear.
    static func setLeftoverDestination(_ account: Account?, accounts: [Account]) {
        for candidate in accounts {
            candidate.isLeftoverDestination = (candidate.id == account?.id)
        }
    }

    /// Moves an account one place earlier or later among the active ones.
    /// Column order on Balances and series order in charts follow from this.
    static func move(_ account: Account, by offset: Int,
                     accounts: [Account], in context: ModelContext) {
        var active = accounts.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        guard let index = active.firstIndex(where: { $0.id == account.id }) else { return }
        let destination = index + offset
        guard active.indices.contains(destination) else { return }

        active.swapAt(index, destination)
        for (position, item) in active.enumerated() { item.sortOrder = position }
        try? context.save()
    }

    static func canMove(_ account: Account, by offset: Int, accounts: [Account]) -> Bool {
        let active = accounts.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        guard let index = active.firstIndex(where: { $0.id == account.id }) else { return false }
        return active.indices.contains(index + offset)
    }

    static func affectedRecordCount(for account: Account, records: [BalanceRecord]) -> Int {
        records.filter { record in
            record.entries.contains { $0.accountID == account.id }
        }.count
    }

    /// Permanent: removes the account and strips its entries from history,
    /// which changes past totals. Always confirm before calling.
    static func delete(_ account: Account, records: [BalanceRecord], in context: ModelContext) {
        for record in records {
            record.entries.removeAll { $0.accountID == account.id }
        }
        context.delete(account)
        try? context.save()
    }
}
