import SwiftUI
import AppKit

/// Light/dark preference. Defaults to following macOS, which is what most
/// people want; the override is there for when it isn't.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Applies to the whole app. `nil` hands control back to macOS.
    @MainActor
    func apply() {
        NSApp?.appearance = nsAppearance
    }
}

/// A compact three-way control for the sidebar footer.
struct AppearancePicker: View {
    @Binding var selection: AppearanceSetting

    var body: some View {
        Picker("Appearance", selection: $selection) {
            ForEach(AppearanceSetting.allCases) { option in
                Image(systemName: option.icon)
                    .help(option.label)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .onChange(of: selection) { _, new in new.apply() }
    }
}
