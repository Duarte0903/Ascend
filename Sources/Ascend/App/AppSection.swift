import Foundation

/// Sidebar destinations. Named `AppSection` rather than `Section` so it never
/// collides with SwiftUI's own `Section` inside view bodies.
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, balances, trends, allocation, investments, expenses, tax, sideHustle,
         goals, projections, accounts, profile, settings

    var id: String { rawValue }

    /// Sidebar groupings, in order, before anything is filtered out.
    private static let allGroups: [(label: String, items: [AppSection])] = [
        ("Overview", [.dashboard, .balances, .trends, .allocation, .investments]),
        ("Planning", [.expenses, .tax, .sideHustle, .goals, .projections]),
        ("Setup", [.accounts, .profile, .settings]),
    ]

    /// Whether this screen makes sense for the profile that is open.
    ///
    /// Tax and Side hustles both estimate personal Portuguese tax, which an
    /// organisation does not pay — companies are assessed under an entirely
    /// different regime — and which means nothing outside Portugal. Both are
    /// offered to a person in Portugal and nobody else. Everything else is
    /// universal: balances and forecasts do not care where you live.
    func isAvailable(to kind: ProfileKind, in countryCode: String) -> Bool {
        switch self {
        case .tax, .sideHustle: kind == .person && countryCode == Countries.portugal
        default: true
        }
    }

    /// Whether this screen may be hidden from the sidebar.
    ///
    /// Settings cannot: hiding it would take away the only way of bringing
    /// anything back. Dashboard cannot either, because it is where every
    /// screen falls back to when its own becomes unavailable.
    var canBeHidden: Bool {
        switch self {
        case .settings, .dashboard: false
        default: true
        }
    }

    /// The sidebar for a given kind of profile. A group that loses all of its
    /// items disappears rather than leaving an empty heading.
    static func groups(for kind: ProfileKind, in countryCode: String,
                       hiding hidden: Set<AppSection> = [])
        -> [(label: String, items: [AppSection])] {
        allGroups.compactMap { group in
            let items = group.items.filter {
                $0.isAvailable(to: kind, in: countryCode)
                    && !($0.canBeHidden && hidden.contains($0))
            }
            return items.isEmpty ? nil : (label: group.label, items: items)
        }
    }

    /// Everything the profile could show, hidden or not — what the Settings
    /// screen lists, grouped as the sidebar groups it.
    static func hideableGroups(for kind: ProfileKind, in countryCode: String)
        -> [(label: String, items: [AppSection])] {
        allGroups.compactMap { group in
            let items = group.items.filter {
                $0.isAvailable(to: kind, in: countryCode) && $0.canBeHidden
            }
            return items.isEmpty ? nil : (label: group.label, items: items)
        }
    }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .balances: "Balances"
        case .trends: "Trends"
        case .allocation: "Allocation"
        case .investments: "Investments"
        case .expenses: "Expenses"
        case .tax: "Tax"
        case .sideHustle: "Side hustles"
        case .goals: "Goals"
        case .projections: "Projections"
        case .accounts: "Accounts"
        case .profile: "Profile"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .balances: "tablecells"
        case .trends: "chart.xyaxis.line"
        case .allocation: "chart.pie"
        case .investments: "chart.line.uptrend.xyaxis.circle"
        case .expenses: "creditcard"
        case .tax: "percent"
        case .sideHustle: "briefcase"
        case .goals: "target"
        case .projections: "chart.line.uptrend.xyaxis"
        case .accounts: "building.columns"
        case .profile: "person.crop.circle"
        case .settings: "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Live summary of everything you log"
        case .balances: "One row per recording date, oldest first"
        case .trends: "Deeper breakdowns across your accounts"
        case .allocation: "Split of your most recent record"
        case .investments: "What your savings and investments are worth"
        case .expenses: "What every month costs you"
        case .tax: "What the year costs, and what is left"
        case .sideHustle: "What work on the side earns, and owes"
        case .goals: "Set a target and track progress"
        case .projections: "Forecast from your assumptions"
        case .accounts: "Create, edit and archive your accounts"
        case .profile: "Whose books these are, and how they look"
        case .settings: "Which screens you see, and how the app behaves"
        }
    }
}
