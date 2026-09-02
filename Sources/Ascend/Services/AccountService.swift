import Foundation
import SwiftData

enum AccountError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case cannotArchiveLeftoverDestination
    case cannotArchiveLastAccount
    case needsLeftoverDestination
    case emptyCategoryName
    case duplicateCategoryName
    case categoryInUse(accounts: Int)
    case cannotDeleteLastCategory

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
        case .emptyCategoryName:
            "Give the type a name."
        case .duplicateCategoryName:
            "A type with that name already exists."
        case .categoryInUse(let accounts):
            "\(accounts) account\(accounts == 1 ? " uses" : "s use") this type. Move them to another type first."
        case .cannotDeleteLastCategory:
            "You need at least one account type."
        }
    }
}

enum AccountService {
    /// New accounts inherit their category's defaults, then own them outright —
    /// later changes to the category never rewrite an existing account.
    static func create(name: String, category: AccountCategory?, colorHex: String,
                       note: String = "", in context: ModelContext) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyName }

        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard !existing.contains(where: {
            !$0.isArchived && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw AccountError.duplicateName }

        let account = Account(
            name: trimmed,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: category?.id,
            colorHex: colorHex,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            includeInUsable: category?.defaultIncludeInUsable ?? true,
            countsAsSavings: category?.defaultCountsAsSavings ?? false,
            expectedAnnualReturn: category?.defaultAnnualReturn ?? 0)
        context.insert(account)
        try? context.save()
        return account
    }

    // MARK: - Categories

    static func createCategory(name: String, includeInUsable: Bool, countsAsSavings: Bool,
                               annualReturn: Double = 0,
                               in context: ModelContext) throws -> AccountCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyCategoryName }

        let existing = (try? context.fetch(FetchDescriptor<AccountCategory>())) ?? []
        guard !existing.contains(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw AccountError.duplicateCategoryName }

        let category = AccountCategory(
            name: trimmed,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            defaultIncludeInUsable: includeInUsable,
            defaultCountsAsSavings: countsAsSavings,
            defaultAnnualReturn: annualReturn)
        context.insert(category)
        try? context.save()
        return category
    }

    static func renameCategory(_ category: AccountCategory, to name: String,
                               in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyCategoryName }
        let existing = (try? context.fetch(FetchDescriptor<AccountCategory>())) ?? []
        guard !existing.contains(where: {
            $0.id != category.id
                && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw AccountError.duplicateCategoryName }
        category.name = trimmed
        try? context.save()
    }

    static func accountsUsing(_ category: AccountCategory, accounts: [Account]) -> Int {
        accounts.filter { $0.categoryID == category.id }.count
    }

    /// Refused while any account still uses it, so a category can never vanish
    /// out from under an account.
    static func deleteCategory(_ category: AccountCategory, accounts: [Account],
                               in context: ModelContext) throws {
        let inUse = accountsUsing(category, accounts: accounts)
        guard inUse == 0 else { throw AccountError.categoryInUse(accounts: inUse) }

        let all = (try? context.fetch(FetchDescriptor<AccountCategory>())) ?? []
        guard all.count > 1 else { throw AccountError.cannotDeleteLastCategory }

        context.delete(category)
        let remaining = all.filter { $0.id != category.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        for (position, item) in remaining.enumerated() { item.sortOrder = position }
        try? context.save()
    }

    static func assign(_ account: Account, to category: AccountCategory?,
                       in context: ModelContext) {
        account.categoryID = category?.id
        try? context.save()
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

    /// Sets how often interest is credited, keeping the anchor date in step.
    ///
    /// The anchor is never shown or typed: choosing a frequency starts the
    /// schedule from that moment, and every later payment is counted forward
    /// from it. A frequency with no anchor cannot produce a schedule, and an
    /// anchor with no frequency is never read, so neither exists alone.
    static func setInterestSchedule(_ frequency: InterestFrequency,
                                    on account: Account,
                                    in context: ModelContext,
                                    now: Date = Date(),
                                    calendar: Calendar = Calendar(identifier: .gregorian)) {
        // Stored in its simplest form, so one schedule has one spelling.
        account.interestFrequency = InterestFrequency.normalised(frequency)
        if account.interestFrequency.isScheduled {
            if account.interestDate == nil {
                // The next 1st. Never today: a schedule created today reading
                // as "interest due today" is interest you have already had.
                account.interestDate = nextOccurrence(ofDay: 1, after: now,
                                                      calendar: calendar)
            }
        } else {
            account.interestDate = nil
        }
        try? context.save()
    }

    /// Moves the schedule onto a different day of the month.
    ///
    /// The next payment is the next time that day comes round — not the same
    /// day in whichever month the schedule happened to be created in. Ask for
    /// the 15th on the 2nd and you get this month's 15th, not next month's.
    static func setInterestDay(_ day: Int, on account: Account,
                               in context: ModelContext,
                               now: Date = Date(),
                               calendar: Calendar = Calendar(identifier: .gregorian)) {
        guard account.interestFrequency.isScheduled else { return }
        account.interestDate = nextOccurrence(ofDay: day, after: now, calendar: calendar)
        try? context.save()
    }

    /// The day of the month the schedule falls on.
    static func interestDay(of account: Account,
                            calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        guard let anchor = account.interestDate else { return 1 }
        return calendar.component(.day, from: anchor)
    }

    /// The first date strictly after today that falls on `day`.
    ///
    /// Strictly after, so a payment is never dated the day it was set up; and
    /// it looks at this month first, so the answer depends on the day chosen
    /// rather than on when the schedule was created.
    private static func nextOccurrence(ofDay day: Int, after now: Date,
                                       calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard var month = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)) else { return nil }
        // At most two hops: this month, then the next, whose length differs.
        for _ in 0..<2 {
            let candidate = clamping(day: day, inMonthOf: month, calendar: calendar)
            if candidate > today { return candidate }
            guard let following = calendar.date(byAdding: .month, value: 1, to: month)
            else { return nil }
            month = following
        }
        return nil
    }

    /// The given day in the same month as `date`, clamped to that month's
    /// length so the 31st still resolves in February.
    private static func clamping(day: Int, inMonthOf date: Date,
                                 calendar: Calendar) -> Date {
        let length = calendar.range(of: .day, in: .month, for: date)?.count ?? 28
        var parts = calendar.dateComponents([.year, .month], from: date)
        parts.day = min(max(1, day), length)
        return calendar.date(from: parts) ?? date
    }

    /// Exactly one account can be the leftover destination. Pass nil to clear.
    static func setLeftoverDestination(_ account: Account?, accounts: [Account]) {
        for candidate in accounts {
            candidate.isLeftoverDestination = (candidate.id == account?.id)
            // The destination receives income less contributions and expenses,
            // so a contribution of its own would be subtracted from the very
            // income it is then handed. Clearing it is the only coherent state.
            if candidate.isLeftoverDestination { candidate.monthlyContribution = 0 }
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

    // MARK: - Icons

    /// Stores a downscaled copy of the chosen image. Returns false when the
    /// file is not an image the system can read, so the caller can say so
    /// rather than silently doing nothing.
    @discardableResult
    static func setIcon(fromFileAt url: URL, for account: Account,
                        in context: ModelContext) -> Bool {
        guard let data = AccountIconStyle.thumbnailData(fromFileAt: url) else { return false }
        account.iconData = data
        try? context.save()
        return true
    }

    /// Clearing an icon falls back to the symbol derived from the account's
    /// flags — an account is never left without one.
    static func clearIcon(for account: Account, in context: ModelContext) {
        account.iconData = nil
        try? context.save()
    }

    /// One image already in the store, and which accounts are using it.
    struct StoredIcon: Identifiable, Hashable {
        let data: Data
        let usedBy: [String]
        var id: Data { data }
    }

    /// Every distinct image already loaded, so the same bank logo can be picked
    /// again instead of hunting for the file a second time. Identical images
    /// collapse into one entry: importing re-encodes to PNG at a fixed size, so
    /// the same source file always yields the same bytes.
    static func iconLibrary(accounts: [Account]) -> [StoredIcon] {
        var order: [Data] = []
        var users: [Data: [String]] = [:]
        for account in accounts.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let data = account.iconData else { continue }
            if users[data] == nil { order.append(data) }
            users[data, default: []].append(account.name)
        }
        return order.map { StoredIcon(data: $0, usedBy: users[$0] ?? []) }
    }

    /// Each account keeps its own copy rather than sharing a reference, so
    /// deleting one account can never blank another's icon.
    static func reuseIcon(_ data: Data, for account: Account, in context: ModelContext) {
        account.iconData = data
        try? context.save()
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
