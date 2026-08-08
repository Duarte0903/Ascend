import Foundation
import SwiftData

struct BackupFile: Codable {
    struct AccountDTO: Codable {
        var id: UUID, name: String, kind: String, colorHex: String, sortOrder: Int
        var includeInUsable: Bool, countsAsSavings: Bool
        var expectedAnnualReturn: Double, monthlyContribution: Double
        var isLeftoverDestination: Bool, isArchived: Bool
    }
    struct RecordDTO: Codable {
        var id: UUID, date: Date, createdAt: Date, note: String?, balances: [String: Double]
    }
    struct SettingsDTO: Codable {
        var targetNetWorth: Double, monthlyNetIncome: Double
        var maxMonthlyExpenses: Double, projectionHorizonMonths: Int
    }
    var version = 1
    var accounts: [AccountDTO]
    var records: [RecordDTO]
    var settings: SettingsDTO
}

enum BackupService {
    static func export(accounts: [Account], records: [BalanceRecord],
                       settings: AppSettings) throws -> Data {
        let file = BackupFile(
            accounts: accounts.map {
                .init(id: $0.id, name: $0.name, kind: $0.kind.rawValue, colorHex: $0.colorHex,
                      sortOrder: $0.sortOrder, includeInUsable: $0.includeInUsable,
                      countsAsSavings: $0.countsAsSavings,
                      expectedAnnualReturn: $0.expectedAnnualReturn,
                      monthlyContribution: $0.monthlyContribution,
                      isLeftoverDestination: $0.isLeftoverDestination,
                      isArchived: $0.isArchived)
            },
            records: records.map { record in
                var balances: [String: Double] = [:]
                for entry in record.entries { balances[entry.accountID.uuidString] = entry.amount }
                return .init(id: record.id, date: record.date, createdAt: record.createdAt,
                             note: record.note, balances: balances)
            },
            settings: .init(targetNetWorth: settings.targetNetWorth,
                            monthlyNetIncome: settings.monthlyNetIncome,
                            maxMonthlyExpenses: settings.maxMonthlyExpenses,
                            projectionHorizonMonths: settings.projectionHorizonMonths))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Replaces everything in the store with the backup's contents.
    static func restore(from data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)

        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] {
            context.delete(account)
        }
        for record in (try? context.fetch(FetchDescriptor<BalanceRecord>())) ?? [] {
            context.delete(record)
        }
        for settings in (try? context.fetch(FetchDescriptor<AppSettings>())) ?? [] {
            context.delete(settings)
        }

        for dto in file.accounts {
            let account = Account(
                id: dto.id, name: dto.name, kind: AccountKind(rawValue: dto.kind) ?? .main,
                colorHex: dto.colorHex, sortOrder: dto.sortOrder,
                includeInUsable: dto.includeInUsable, countsAsSavings: dto.countsAsSavings,
                expectedAnnualReturn: dto.expectedAnnualReturn,
                monthlyContribution: dto.monthlyContribution,
                isLeftoverDestination: dto.isLeftoverDestination)
            account.isArchived = dto.isArchived
            context.insert(account)
        }
        for dto in file.records {
            let record = BalanceRecord(id: dto.id, date: dto.date,
                                       createdAt: dto.createdAt, note: dto.note)
            context.insert(record)
            for (key, amount) in dto.balances {
                if let accountID = UUID(uuidString: key) {
                    record.setAmount(amount, for: accountID)
                }
            }
        }
        context.insert(AppSettings(
            targetNetWorth: file.settings.targetNetWorth,
            monthlyNetIncome: file.settings.monthlyNetIncome,
            maxMonthlyExpenses: file.settings.maxMonthlyExpenses,
            projectionHorizonMonths: file.settings.projectionHorizonMonths))
        try context.save()
    }
}
