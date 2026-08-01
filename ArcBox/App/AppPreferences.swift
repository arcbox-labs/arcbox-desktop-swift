import Foundation

enum AppPreferences {
    static func registerDefaults(in userDefaults: UserDefaults = .standard) {
        userDefaults.register(defaults: [
            "showInMenuBar": false,
            "updateChannel": "stable",
            "activity.containerColumns": Data(),
            "terminalTheme": "system",
            "externalTerminal": ExternalTerminalApp.terminalBundleIdentifier,
            "startAtLogin": false,
            "telemetryEnabled": true,
            "includeTimeMachine": false,
            "switchDockerContextAutomatically": true,
            "pauseContainersWhileSleeping": true,
        ])
    }
}
