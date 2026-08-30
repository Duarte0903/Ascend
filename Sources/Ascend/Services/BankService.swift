import Foundation
import SwiftData

enum BankError: LocalizedError, Equatable {
    case emptyName
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName: "Give the bank a name."
        case .duplicateName: "There's already a bank with that name."
        }
    }
}

/// Creating, renaming and removing banks, and keeping accounts pointing
/// somewhere real when one goes.
enum BankService {

    @discardableResult
    static func create(name: String, colorHex: String,
                       in context: ModelContext) throws -> Bank {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BankError.emptyName }

        let existing = all(in: context)
        guard !existing.contains(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw BankError.duplicateName }

        let bank = Bank(name: trimmed, colorHex: colorHex,
                        sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(bank)
        try? context.save()
        return bank
    }

    static func rename(_ bank: Bank, to name: String, in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BankError.emptyName }
        guard !all(in: context).contains(where: {
            $0.id != bank.id
                && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw BankError.duplicateName }
        bank.name = trimmed
        try? context.save()
    }

    /// Deleting a bank never deletes an account. The accounts held there simply
    /// stop being held anywhere, which is a state the app already handles —
    /// a bank was optional to begin with.
    static func delete(_ bank: Bank, accounts: [Account], in context: ModelContext) {
        for account in accounts where account.bankID == bank.id {
            account.bankID = nil
        }
        context.delete(bank)
        try? context.save()
    }

    static func accountsAt(_ bank: Bank, accounts: [Account]) -> Int {
        accounts.filter { $0.bankID == bank.id && !$0.isArchived }.count
    }

    static func all(in context: ModelContext) -> [Bank] {
        let banks = (try? context.fetch(FetchDescriptor<Bank>())) ?? []
        return banks.sorted { $0.sortOrder < $1.sortOrder }
    }
}
