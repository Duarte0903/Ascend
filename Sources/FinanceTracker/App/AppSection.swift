import Foundation

/// Sidebar destinations. Named `AppSection` rather than `Section` so it never
/// collides with SwiftUI's own `Section` inside view bodies.
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, balances, trends, allocation, goals, projections, accounts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .balances: "Balances"
        case .trends: "Trends"
        case .allocation: "Allocation"
        case .goals: "Goals"
        case .projections: "Projections"
        case .accounts: "Accounts"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .balances: "tablecells"
        case .trends: "chart.xyaxis.line"
        case .allocation: "chart.pie"
        case .goals: "target"
        case .projections: "chart.line.uptrend.xyaxis"
        case .accounts: "building.columns"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Live summary of everything you log on the Balances screen."
        case .balances: "Fill one row per recording date, oldest first."
        case .trends: "Deeper visual breakdowns across your accounts."
        case .allocation: "Split of your most recently filled record."
        case .goals: "Set a target and track progress towards it."
        case .projections: "Set your assumptions. The forecast updates automatically."
        case .accounts: "Create accounts, change how they are treated, or archive old ones."
        }
    }
}
