import Foundation
import SwiftData

@Model
final class BalanceRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Orders records that share a date. Without it, two records on the same
    /// day would sort arbitrarily and flip their change and savings-rate values.
    var createdAt: Date = Date()
    var note: String?
    @Relationship(deleteRule: .cascade) var entries: [BalanceEntry] = []

    init(id: UUID = UUID(), date: Date, createdAt: Date = Date(),
         note: String? = nil, entries: [BalanceEntry] = []) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.note = note
        self.entries = entries
    }

    func amount(for accountID: UUID) -> Double {
        entries.first { $0.accountID == accountID }?.amount ?? 0
    }

    /// Rounds to cents — money is never stored with sub-cent noise.
    func setAmount(_ amount: Double, for accountID: UUID) {
        let rounded = (amount * 100).rounded() / 100
        if let existing = entries.first(where: { $0.accountID == accountID }) {
            existing.amount = rounded
        } else {
            entries.append(BalanceEntry(accountID: accountID, amount: rounded))
        }
    }

    func toInput() -> RecordInput {
        var balances: [UUID: Double] = [:]
        for entry in entries { balances[entry.accountID] = entry.amount }
        return RecordInput(id: id, date: date, createdAt: createdAt, balances: balances)
    }
}

@Model
final class BalanceEntry {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var amount: Double = 0

    init(id: UUID = UUID(), accountID: UUID, amount: Double) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
    }
}
