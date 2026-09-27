import Foundation

/// The country a profile belongs to, as an ISO 3166-1 alpha-2 code.
///
/// Only a code is stored. Names come from the system, so they follow whatever
/// language the Mac is set to and never go stale when a country is renamed.
enum Countries {
    /// Portugal, the one tax system the app actually models.
    static let portugal = "PT"

    /// Every code the system knows, sorted by the name it will be shown under.
    static var all: [String] {
        Locale.Region.isoRegions
            .map(\.identifier)
            // Two-letter codes only: the list also carries continents and
            // groupings like "019" (Americas), which are not countries.
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .sorted { name(for: $0).localizedCompare(name(for: $1)) == .orderedAscending }
    }

    static func name(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
