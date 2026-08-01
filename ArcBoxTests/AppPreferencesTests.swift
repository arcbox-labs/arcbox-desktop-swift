import Foundation
import XCTest

@testable import ArcBox

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testRegistersEveryDefaultWithoutOverwritingAStoredPreference() throws {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(false, forKey: "switchDockerContextAutomatically")
        AppPreferences.registerDefaults(in: userDefaults)

        XCTAssertFalse(userDefaults.bool(forKey: "showInMenuBar"))
        XCTAssertEqual(userDefaults.string(forKey: "updateChannel"), "stable")
        XCTAssertEqual(userDefaults.data(forKey: "activity.containerColumns"), Data())
        XCTAssertEqual(userDefaults.string(forKey: "terminalTheme"), "system")
        XCTAssertEqual(
            userDefaults.string(forKey: "externalTerminal"),
            ExternalTerminalApp.terminalBundleIdentifier
        )
        XCTAssertFalse(userDefaults.bool(forKey: "startAtLogin"))
        XCTAssertTrue(userDefaults.bool(forKey: "telemetryEnabled"))
        XCTAssertFalse(userDefaults.bool(forKey: "includeTimeMachine"))
        XCTAssertFalse(
            userDefaults.bool(forKey: "switchDockerContextAutomatically"),
            "registered defaults must not overwrite a stored preference"
        )
        XCTAssertTrue(userDefaults.bool(forKey: "pauseContainersWhileSleeping"))

        userDefaults.removeObject(forKey: "switchDockerContextAutomatically")
        XCTAssertTrue(userDefaults.bool(forKey: "switchDockerContextAutomatically"))
    }
}
