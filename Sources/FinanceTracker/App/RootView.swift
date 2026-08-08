import SwiftUI
import SwiftData

struct RootView: View {
    @State private var selection: AppSection = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case .dashboard: DashboardView()
                case .balances: BalancesView()
                case .trends: TrendsView()
                case .allocation: AllocationView()
                case .goals: GoalsView()
                case .projections: ProjectionsView()
                case .accounts: AccountsView()
                }
            }
            .navigationTitle(selection.title)
            .navigationSubtitle(selection.subtitle)
            .frame(minWidth: 720, minHeight: 560)
        }
    }
}
