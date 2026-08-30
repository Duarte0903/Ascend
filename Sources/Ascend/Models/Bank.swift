import Foundation
import SwiftData

/// Where an account is held. One bank has many accounts; an account has at most
/// one bank, and may have none — plenty of accounts (a meal card, a broker, cash)
/// do not belong to a bank at all, so it is never required.
@Model
final class Bank {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#1F6E8C"
    var sortOrder: Int = 0

    init(id: UUID = UUID(), name: String, colorHex: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }

    /// What the engine needs: the name and colour to label a total with.
    func toInfo() -> BankInfo {
        BankInfo(id: id, name: name, colorHex: colorHex, sortOrder: sortOrder)
    }
}
