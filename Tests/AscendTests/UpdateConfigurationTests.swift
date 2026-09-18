import Foundation
import Testing
@testable import Ascend

/// The keys that decide whether Ascend may install anything without asking.
/// Pinned so a future edit to project.yml cannot quietly turn on unattended
/// updates or point the app at a different feed.
@Suite("Update configuration")
struct UpdateConfigurationTests {
    private var info: [String: Any] {
        (Bundle(identifier: "com.duarte.ascend") ?? Bundle.main).infoDictionary ?? [:]
    }

    @Test("The feed is the appcast on the repo's main branch")
    func feedURL() {
        #expect(info["SUFeedURL"] as? String
                == "https://raw.githubusercontent.com/Duarte0903/Ascend/main/appcast.xml")
    }

    @Test("Updates are verified against a public EdDSA key")
    func publicKey() {
        let key = info["SUPublicEDKey"] as? String ?? ""
        #expect(!key.isEmpty)
        // A 32-byte Ed25519 key, base64: 44 characters ending in '='.
        #expect(key.count == 44)
        #expect(Data(base64Encoded: key)?.count == 32)
    }

    @Test("Sparkle neither schedules its own checks nor installs unasked")
    func consent() {
        // The key must be present (either value) or Sparkle asks the user on
        // second launch; false because UpdateService runs the quiet checks.
        #expect(info["SUEnableAutomaticChecks"] as? Bool == false)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
    }

    @Test("The app asks at launch and once a day after")
    func cadence() {
        #expect(UpdateService.launchDelay == .seconds(3))
        #expect(UpdateService.recheckInterval == .seconds(86400))
    }

    @Test("Version numbers come from build settings, not literals")
    func versions() {
        let build = info["CFBundleVersion"] as? String ?? ""
        let marketing = info["CFBundleShortVersionString"] as? String ?? ""
        #expect(Int(build) != nil)
        #expect(!marketing.isEmpty)
    }
}

@Suite("Dev mode")
struct DevModeTests {
    @Test("A Debug build honours ASCEND_DEV=1 and nothing else")
    func flag() {
        #expect(DevMode.isActive(in: ["ASCEND_DEV": "1"]))
        #expect(!DevMode.isActive(in: ["ASCEND_DEV": "0"]))
        #expect(!DevMode.isActive(in: ["ASCEND_DEV": "yes"]))
        #expect(!DevMode.isActive(in: [:]))
    }

    @Test("The test process itself is not in dev mode")
    func testsAreNotDev() {
        #expect(!DevMode.isActive)
        #expect(DevMode.dataRoot == nil)
    }
}
