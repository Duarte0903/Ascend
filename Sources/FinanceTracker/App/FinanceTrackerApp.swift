import SwiftUI
import SwiftData

@main
struct FinanceTrackerApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Account.self, BalanceRecord.self, BalanceEntry.self, AppSettings.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
        SeedData.seedIfNeeded(ModelContext(container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 800)
    }
}
