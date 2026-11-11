import Foundation

/// Which screens the user has taken out of the sidebar.
///
/// Stored as one string of raw values rather than a flag per screen, so
/// adding a screen later needs no migration: anything unrecognised is simply
/// dropped when it is read back.
enum HiddenSections {
    static let key = "hiddenSections"

    static func decode(_ raw: String) -> Set<AppSection> {
        Set(raw.split(separator: ",")
            .compactMap { AppSection(rawValue: String($0)) }
            // A screen that cannot be hidden is not hidden, whatever the
            // stored string says.
            .filter(\.canBeHidden))
    }

    /// Sorted, so the stored string does not churn between launches.
    static func encode(_ sections: Set<AppSection>) -> String {
        sections.filter(\.canBeHidden).map(\.rawValue).sorted().joined(separator: ",")
    }
}
