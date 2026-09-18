import Foundation
import Observation
import Sparkle

/// A release the feed offers that is newer than the running app.
struct AvailableUpdate: Equatable {
    let version: String
}

/// Owns Sparkle's updater for the life of the app.
///
/// Sparkle does the checking, the "a new version is available" window, the
/// download, the signature check and the swap. This class starts it, asks it
/// quietly at launch (and once a day after that) whether anything newer
/// exists, and publishes the answer so the sidebar can show a card. Nothing is
/// downloaded until the user clicks through Sparkle's own Install window.
@MainActor
@Observable
final class UpdateService: NSObject {
    private(set) var canCheckForUpdates = false
    /// Set by the quiet check; cleared when the user dismisses the card,
    /// skips the version in Sparkle's window, or the update is installed.
    private(set) var availableUpdate: AvailableUpdate?

    /// How long the app waits after launch before asking, and how often it
    /// asks again while it stays open.
    nonisolated static let launchDelay: Duration = .seconds(3)
    nonisolated static let recheckInterval: Duration = .seconds(86400)

    // Sparkle's controller is not Sendable and must outlive the app; kept
    // private so nothing else reaches into the updater directly.
    // nil when updates are off (the dev preview): no feed is ever fetched
    // and the menu item stays disabled.
    @ObservationIgnored
    private var controller: SPUStandardUpdaterController?
    @ObservationIgnored
    private var observation: NSKeyValueObservation?
    @ObservationIgnored
    private var schedule: Task<Void, Never>?

    init(enabled: Bool = true) {
        super.init()
        guard enabled else { return }
        // Sparkle's own scheduled check is off (SUEnableAutomaticChecks); the
        // quiet probe below replaces it so the result lands in the toast
        // instead of an unprompted window.
        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: self,
                                                      userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates,
                                                 options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor [weak self] in self?.canCheckForUpdates = value }
        }
        schedule = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            while !Task.isCancelled {
                self?.probe()
                try? await Task.sleep(for: Self.recheckInterval)
            }
        }
    }

    /// A user-initiated check: always ends in a window, either the update
    /// offer or "You're up to date" / a connection error.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Hides the card until the next quiet check finds something.
    func dismissAvailableUpdate() {
        availableUpdate = nil
    }

    /// Fetches the feed without any UI; the answer arrives through the
    /// delegate. Sparkle ignores versions the user has skipped.
    private func probe() {
        guard let updater = controller?.updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdateInformation()
    }
}

extension UpdateService: @MainActor SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableUpdate = AvailableUpdate(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        availableUpdate = nil
    }

    func updater(_ updater: SPUUpdater, userDidSkipThisVersion item: SUAppcastItem) {
        availableUpdate = nil
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        availableUpdate = nil
    }
}
