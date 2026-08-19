import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

@main
struct AscendApp: App {
    /// Owns both the profile list and the open profile's store. Seeding and
    /// migration moved in here, because they now happen per profile.
    @State private var profiles = ProfileStore()
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                // Switching profiles rebuilds the window from scratch, so no
                // screen keeps a selection or a half-typed field from the
                // profile you just left.
                .id(profiles.registry.activeID)
                // Installed here rather than on the WindowGroup: as a Scene
                // modifier it is not re-applied when the container changes, so
                // switching profiles left every screen querying the old store.
                .modelContainer(profiles.container)
                .environment(profiles)
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Menu("Switch Profile") {
                    ForEach(profiles.registry.profiles) { profile in
                        Button {
                            profiles.activate(profile.id)
                        } label: {
                            HStack {
                                Text(profile.name)
                                if profile.id == profiles.registry.activeID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                .disabled(profiles.registry.profiles.count < 2)
            }
            CommandGroup(after: .saveItem) {
                Button("Export Backup…") { exportBackup() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Import Backup…") { importBackup() }
            }
            // View ▸ Appearance. Each option carries a checkmark and a
            // shortcut, which reads better in a menu than a segmented picker.
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array(AppearanceSetting.allCases.enumerated()), id: \.element) { index, option in
                    Button {
                        appearanceRaw = option.rawValue
                        option.apply()
                    } label: {
                        HStack {
                            Text("Appearance: \(option.label)")
                            if appearanceRaw == option.rawValue { Image(systemName: "checkmark") }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                      modifiers: [.command, .control])
                }
                Divider()
            }
        }
    }

    @MainActor
    private func exportBackup() {
        guard let data = profiles.backupOfActive() else { return }

        let panel = NSSavePanel()
        // Named after the profile, so backups of two profiles don't overwrite
        // each other in the same folder.
        let slug = profiles.registry.active.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        panel.nameFieldStringValue = "ascend-\(slug)-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    @MainActor
    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        // Restores into the open profile only; the others are untouched.
        profiles.restoreIntoActive(data)
    }
}
