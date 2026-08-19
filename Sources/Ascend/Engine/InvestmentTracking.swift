import Foundation

/// Whether an account appears on the Investments screen.
///
/// Defaults to `auto`, which follows the savings-rate flag — so accounts still
/// arrive on their own — while leaving an explicit override for the cases the
/// rule gets wrong.
enum InvestmentTracking: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto, included, excluded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Automatic"
        case .included: "Always track"
        case .excluded: "Never track"
        }
    }

    /// `auto` defers to the same flag that marks an account as savings or
    /// investment elsewhere; the other two ignore it entirely.
    func tracks(countsAsSavings: Bool) -> Bool {
        switch self {
        case .auto: countsAsSavings
        case .included: true
        case .excluded: false
        }
    }

    func explanation(countsAsSavings: Bool) -> String {
        switch self {
        case .auto:
            countsAsSavings
                ? "Tracked, because it counts toward your savings rate"
                : "Not tracked, because it doesn't count toward your savings rate"
        case .included: "Tracked, whatever its flags say"
        case .excluded: "Kept out, whatever its flags say"
        }
    }
}
