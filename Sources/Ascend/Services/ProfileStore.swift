import Foundation
import SwiftData
import Observation

/// What a freshly created profile is filled with.
enum NewProfileContent: String, CaseIterable, Identifiable {
    case empty, sample, copyOfCurrent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .empty: "Empty"
        case .sample: "Sample data"
        case .copyOfCurrent: "Copy of current"
        }
    }

    var explanation: String {
        switch self {
        case .empty: "Start with nothing but the default account types."
        case .sample: "Start with invented accounts and records to explore with."
        case .copyOfCurrent: "Duplicate the open profile, then diverge from it."
        }
    }
}

/// Owns the profile list and the store of whichever profile is open.
///
/// Each profile is a separate SwiftData file. That is what lets every screen
/// keep its plain unfiltered `@Query`: isolation is enforced by the filesystem,
/// so no screen can show another profile's data even by mistake.
@MainActor
@Observable
final class ProfileStore {
    private(set) var registry: ProfileRegistry
    private(set) var container: ModelContainer
    /// Surfaced by the UI rather than thrown, so a failed create or delete
    /// leaves the app usable on the profile it already had open.
    var lastError: String?

    private let registryURL: URL
    private let profilesDirectory: URL

    static let schema = Schema([Account.self, AccountCategory.self, BalanceRecord.self,
                                BalanceEntry.self, AppSettings.self, Expense.self,
                                ExpenseCategory.self])

    /// `root` exists for tests: pass a temporary directory and the store keeps
    /// entirely to itself, adopting no legacy store and seeding no sample data.
    init(root: URL? = nil) {
        let isolated = root != nil
        let fileManager = FileManager.default
        let support = (try? fileManager.url(for: .applicationSupportDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil, create: true))
            ?? URL.homeDirectory.appending(path: "Library/Application Support")
        let root = root ?? support.appending(path: "Ascend", directoryHint: .isDirectory)
        let directory = root.appending(path: "Profiles", directoryHint: .isDirectory)
        let registryFile = root.appending(path: "profiles.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        profilesDirectory = directory
        registryURL = registryFile

        // Resolved into locals first: nothing may be read back off `self`
        // until every stored property has a value.
        let loaded: ProfileRegistry
        var seedFirstProfile = false
        if let data = try? Data(contentsOf: registryFile),
           let decoded = try? JSONDecoder().decode(ProfileRegistry.self, from: data) {
            loaded = decoded
        } else {
            // First launch under profiles. Anyone upgrading already has a store
            // at SwiftData's default location; adopt it as their first profile
            // so no existing data is stranded.
            let first = Profile(name: "Personal")
            loaded = ProfileRegistry(first: first)
            let adopted = isolated ? false
                : Self.adoptLegacyStore(in: support,
                                        as: directory.appending(path: first.fileName))
            // Sample data belongs only to a first profile created out of
            // nothing. An empty profile the user asked for must stay empty,
            // which is why seeding does not live in `prepare`.
            seedFirstProfile = !adopted && !isolated
            Self.write(loaded, to: registryFile)
        }

        let opened = Self.open(directory.appending(path: loaded.active.fileName))
        if seedFirstProfile { SeedData.seedIfNeeded(ModelContext(opened)) }
        Self.prepare(opened)

        registry = loaded
        container = opened
        applyCurrency()
    }

    // MARK: - Switching

    func activate(_ id: UUID) {
        guard id != registry.activeID else { return }
        registry.activate(id)
        container = Self.open(url(for: registry.active))
        Self.prepare(container)
        applyCurrency()
        persist()
    }

    // MARK: - Editing

    func create(kind: ProfileKind = .person, name: String, colorHex: String,
                symbol: String, content: NewProfileContent) {
        let profile = Profile(kind: kind, name: registry.uniqueName(basedOn: name),
                              colorHex: colorHex, symbol: symbol)
        // Snapshot before anything switches, while the source store is still
        // the open one.
        let snapshot = content == .copyOfCurrent ? backupOfActive() : nil
        if content == .copyOfCurrent && snapshot == nil {
            lastError = "Couldn't copy the current profile, so nothing was created."
            return
        }

        do {
            let created = try Self.openThrowing(url(for: profile))
            let context = ModelContext(created)
            switch content {
            case .empty: break
            case .sample: SeedData.seedIfNeeded(context)
            case .copyOfCurrent: try BackupService.restore(from: snapshot!, into: context)
            }
            Self.prepare(created)

            registry.add(profile)
            registry.activate(profile.id)
            container = created
            applyCurrency()
            persist()
        } catch {
            try? FileManager.default.removeItem(at: url(for: profile))
            lastError = "Couldn't create that profile: \(error.localizedDescription)"
        }
    }

    func rename(_ id: UUID, to name: String) {
        registry.rename(id, to: name)
        persist()
    }

    func setAppearance(_ id: UUID, colorHex: String, symbol: String) {
        registry.setAppearance(id, colorHex: colorHex, symbol: symbol)
        persist()
    }

    /// The general editor for everything else a profile carries.
    func update(_ id: UUID, _ transform: (inout Profile) -> Void) {
        registry.update(id, transform)
        applyCurrency()
        persist()
    }

    /// Downscales before storing, so a dropped-in photo doesn't bloat the
    /// registry file the app reads on every launch.
    func setImage(fromFileAt url: URL, for id: UUID) -> Bool {
        guard let data = AccountIconStyle.thumbnailData(fromFileAt: url) else { return false }
        update(id) { $0.imageData = data }
        return true
    }

    func clearImage(for id: UUID) {
        update(id) { $0.imageData = nil }
    }

    private func applyCurrency() {
        Money.symbol = registry.active.currencySymbol
    }

    var canDelete: Bool { registry.profiles.count > 1 }

    /// Deletes a profile and everything in it. Switches first when the deleted
    /// profile is the open one, so the store file is no longer in use by the
    /// time it is removed.
    func delete(_ id: UUID) {
        let wasActive = id == registry.activeID
        guard let removed = registry.remove(id) else {
            lastError = "There has to be at least one profile."
            return
        }
        if wasActive {
            container = Self.open(url(for: registry.active))
            Self.prepare(container)
            applyCurrency()
        }
        Self.deleteStoreFiles(at: url(for: removed))
        persist()
    }

    // MARK: - Files

    private func url(for profile: Profile) -> URL {
        profilesDirectory.appending(path: profile.fileName)
    }

    private func persist() {
        Self.write(registry, to: registryURL)
    }

    private static func write(_ registry: ProfileRegistry, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(registry).write(to: url, options: .atomic)
    }

    private static func openThrowing(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
    }

    private static func open(_ url: URL) -> ModelContainer {
        do {
            return try openThrowing(url)
        } catch {
            fatalError("Could not open the data store at \(url.path): \(error)")
        }
    }

    /// Brings a store up to date on open. Safe to re-run: each step is a no-op
    /// once it has been applied, and on a brand-new empty store they simply
    /// seed the default account and expense categories.
    private static func prepare(_ container: ModelContainer) {
        let context = ModelContext(container)
        SeedData.migrateLegacyColors(context)
        SeedData.migrateCategories(context)
        SeedData.migrateExpenses(context)
        SeedData.migrateExpenseAccounts(context)
        SeedData.migrateYoungTaxpayerStart(context)
        SeedData.migrateMealAllowanceLimits(context)
        SeedData.migrateTaxBands(context)
        SeedData.migrateYoungTaxpayerSkips(context)
        SeedData.migrateLeftoverContribution(context)
    }

    /// SwiftData keeps a write-ahead log and a shared-memory file beside the
    /// store; all three move or delete together or the store is corrupted.
    private static let storeSiblings = ["", "-wal", "-shm"]

    /// Attributes marked `.externalStorage` — account images — are written to a
    /// hidden directory beside the store rather than into it. Move or delete a
    /// store without this and the images are stranded.
    private static func supportDirectory(for store: URL) -> URL {
        let base = store.deletingPathExtension().lastPathComponent
        return store.deletingLastPathComponent()
            .appending(path: ".\(base)_SUPPORT", directoryHint: .isDirectory)
    }

    /// Returns whether an existing store was taken over.
    @discardableResult
    private static func adoptLegacyStore(in support: URL, as destination: URL) -> Bool {
        let fileManager = FileManager.default
        let legacy = support.appending(path: "default.store")
        guard fileManager.fileExists(atPath: legacy.path) else { return false }
        for suffix in storeSiblings {
            let from = URL(filePath: legacy.path + suffix)
            let to = URL(filePath: destination.path + suffix)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try? fileManager.moveItem(at: from, to: to)
        }
        move(supportDirectory(for: legacy), to: supportDirectory(for: destination))
        return fileManager.fileExists(atPath: destination.path)
    }

    /// Moves a support directory, merging when the destination already exists —
    /// which it does whenever a container has been opened there first.
    private static func move(_ source: URL, to destination: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        if !fileManager.fileExists(atPath: destination.path) {
            try? fileManager.moveItem(at: source, to: destination)
            return
        }
        let contents = (try? fileManager.contentsOfDirectory(at: source,
                                                             includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            let target = destination.appending(path: item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                // One level deeper: the _EXTERNAL_DATA folder holding the files.
                let inner = (try? fileManager.contentsOfDirectory(at: item,
                                                                  includingPropertiesForKeys: nil)) ?? []
                for file in inner {
                    try? fileManager.moveItem(at: file,
                                              to: target.appending(path: file.lastPathComponent))
                }
            } else {
                try? fileManager.moveItem(at: item, to: target)
            }
        }
        try? fileManager.removeItem(at: source)
    }

    private static func deleteStoreFiles(at url: URL) {
        for suffix in storeSiblings {
            try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
        }
        try? FileManager.default.removeItem(at: supportDirectory(for: url))
    }

    // MARK: - Backup

    /// A full JSON snapshot of the open profile. Used both by File ▸ Export and
    /// by "copy of current", which is why duplicating a profile goes through
    /// the backup format rather than copying the file: the source store is open
    /// and its write-ahead log may not be checkpointed.
    func backupOfActive() -> Data? {
        let context = ModelContext(container)
        guard let accounts = try? context.fetch(FetchDescriptor<Account>()),
              let records = try? context.fetch(FetchDescriptor<BalanceRecord>()) else { return nil }
        return try? BackupService.export(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context),
            categories: (try? context.fetch(FetchDescriptor<AccountCategory>())) ?? [],
            expenses: (try? context.fetch(FetchDescriptor<Expense>())) ?? [],
            expenseCategories: (try? context.fetch(FetchDescriptor<ExpenseCategory>())) ?? [])
    }

    func restoreIntoActive(_ data: Data) {
        do {
            try BackupService.restore(from: data, into: ModelContext(container))
        } catch {
            lastError = "That backup couldn't be read: \(error.localizedDescription)"
        }
    }
}
