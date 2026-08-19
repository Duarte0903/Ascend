import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]

    @Environment(ProfileStore.self) private var profiles
    @State private var selection: AppSection = .dashboard
    @State private var showingNewProfile = false
    @State private var showingProfileManager = false
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue

    private var appearance: Binding<AppearanceSetting> {
        Binding(get: { AppearanceSetting(rawValue: appearanceRaw) ?? .system },
                set: { appearanceRaw = $0.rawValue })
    }

    private var netWorth: Double? {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context),
            expenses: expenseItems)).last?.total
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showingNewProfile) {
            NewProfileSheet(isPresented: $showingNewProfile)
        }
        .alert("Couldn't do that",
               isPresented: Binding(get: { profiles.lastError != nil },
                                    set: { if !$0 { profiles.lastError = nil } })) {
            Button("OK") { profiles.lastError = nil }
        } message: {
            Text(profiles.lastError ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(AppSection.groups, id: \.label) { group in
                SwiftUI.Section {
                    ForEach(group.items) { section in
                        Label {
                            Text(section.title).font(.system(size: 13.5, weight: .medium))
                        } icon: {
                            Image(systemName: section.icon)
                                .foregroundStyle(selection == section ? Color.white : Color.ftAccent)
                        }
                        .tag(section)
                    }
                } header: {
                    Text(group.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 196, ideal: 214, max: 260)
        .safeAreaInset(edge: .top) {
            ProfileSwitcher(showingNew: $showingNewProfile,
                            showingManager: $showingProfileManager)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                .overlay(Divider(), alignment: .bottom)
                .popover(isPresented: $showingProfileManager, arrowEdge: .bottom) {
                    ProfileManager(isPresented: $showingProfileManager,
                                   showingNew: $showingNewProfile)
                }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Eyebrow("Net worth")
                Text(Money.currency(netWorth))
                    .font(.figure(18))
                    .monospacedDigit()
                    .foregroundStyle(Color.ftInk)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
            .overlay(Divider(), alignment: .top)
        }
        .onAppear { appearance.wrappedValue.apply() }
    }

    private var detail: some View {
        Group {
            switch selection {
            case .dashboard: DashboardView()
            case .balances: BalancesView()
            case .trends: TrendsView()
            case .allocation: AllocationView()
            case .investments: InvestmentsView()
            case .expenses: ExpensesView()
            case .goals: GoalsView()
            case .projections: ProjectionsView()
            case .accounts: AccountsView()
            case .profile: ProfileView()
            }
        }
        .background(Color.ftCanvas)
        // Clicking any inert area drops first responder, which commits whatever
        // field was being edited. Fields, buttons and toggles handle their own
        // taps, so they take precedence over this.
        .contentShape(Rectangle())
        .onTapGesture { NSApp?.keyWindow?.makeFirstResponder(nil) }
        .navigationTitle(selection.title)
        .navigationSubtitle(selection.subtitle)
        .frame(minWidth: 760, minHeight: 580)
    }
}
