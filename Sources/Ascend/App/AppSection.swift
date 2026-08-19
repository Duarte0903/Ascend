import Foundation

/// Sidebar destinations. Named `AppSection` rather than `Section` so it never
/// collides with SwiftUI's own `Section` inside view bodies.
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, balances, trends, allocation, investments, expenses, goals, projections, accounts,
         profile

    var id: String { rawValue }

    /// Sidebar groupings, in order.
    static let groups: [(label: String, items: [AppSection])] = [
        ("Overview", [.dashboard, .balances, .trends, .allocation, .investments]),
        ("Planning", [.expenses, .goals, .projections]),
        ("Setup", [.accounts, .profile]),
    ]

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .balances: "Balances"
        case .trends: "Trends"
        case .allocation: "Allocation"
        case .investments: "Investments"
        case .expenses: "Expenses"
        case .goals: "Goals"
        case .projections: "Projections"
        case .accounts: "Accounts"
        case .profile: "Profile"
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
        case .goals: "target"
        case .projections: "chart.line.uptrend.xyaxis"
        case .accounts: "building.columns"
        case .profile: "person.crop.circle"
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
        case .goals: "Set a target and track progress"
        case .projections: "Forecast from your assumptions"
        case .accounts: "Create, edit and archive your accounts"
        case .profile: "Whose books these are, and how they look"
        }
    }
}
