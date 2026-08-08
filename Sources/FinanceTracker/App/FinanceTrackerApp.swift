import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

@main
struct FinanceTrackerApp: App {
    let container: ModelContainer
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue

    init() {
        let schema = Schema([Account.self, BalanceRecord.self, BalanceEntry.self, AppSettings.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
        let context = ModelContext(container)
        SeedData.seedIfNeeded(context)
        SeedData.migrateLegacyColors(context)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export Backup…") { exportBackup() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Import Backup…") { importBackup() }
            }
            // View ▸ Appearance. Each option carries a checkmark and a
            // shortcut, which reads better in a menu than a segmented picker.
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array(AppearanceSetting.allCases.enumerated()), id: \.element) { index, option in
                    Button {
                        appearanceRaw = option.rawValue
                        option.apply()
                    } label: {
                        HStack {
                            Text("Appearance: \(option.label)")
                            if appearanceRaw == option.rawValue { Image(systemName: "checkmark") }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                      modifiers: [.command, .control])
                }
                Divider()
            }
        }
    }

    @MainActor
    private func exportBackup() {
        let context = ModelContext(container)
        guard let accounts = try? context.fetch(FetchDescriptor<Account>()),
              let records = try? context.fetch(FetchDescriptor<BalanceRecord>()),
              let data = try? BackupService.export(accounts: accounts, records: records,
                                                   settings: SeedData.settings(in: context))
        else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "finance-tracker-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    @MainActor
    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        try? BackupService.restore(from: data, into: ModelContext(container))
    }
}
