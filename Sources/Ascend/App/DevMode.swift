import Foundation

/// The development preview: a Debug build launched by `scripts/dev.sh` with
/// `ASCEND_DEV=1`. It keeps its own data, never talks to Sparkle, and wears
/// a badge so it cannot be mistaken for the installed release.
///
/// The check is fenced at compile time: a Release binary ignores the variable
/// entirely, so no environment trick can put the badge on the real app.
enum DevMode {
    static let variable = "ASCEND_DEV"

    static let isActive = isActive(in: ProcessInfo.processInfo.environment)

    static func isActive(in environment: [String: String]) -> Bool {
        #if DEBUG
        return environment[variable] == "1"
        #else
        return false
        #endif
    }

    /// Where the preview keeps its profiles, beside — never inside — the
    /// release's `Ascend` folder.
    static var dataRoot: URL? {
        guard isActive else { return nil }
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil, create: true))
            ?? URL.homeDirectory.appending(path: "Library/Application Support")
        return support.appending(path: "Ascend Dev", directoryHint: .isDirectory)
    }
}
