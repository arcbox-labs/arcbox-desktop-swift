import AppKit
import ArcBoxAuth
import ArcBoxClient
import DockerClient
import Foundation
import OSLog
import Observation
import Sparkle
import SwiftUI

@MainActor
final class ApplicationCoordinator: NSObject {
    let appVM = AppViewModel()
    let daemonManager = DaemonManager()
    let authSession = AuthSession()
    let containersVM = ContainersViewModel()
    let imagesVM = ImagesViewModel()
    let networksVM = NetworksViewModel()
    let volumesVM = VolumesViewModel()
    let systemVmBackendVM = SystemVmBackendModel()

    private let eventMonitor = DockerEventMonitor()
    private let sandboxEventMonitor = SandboxEventMonitor()
    private let machineEventMonitor = MachineEventMonitor()
    private let sleepWakeManager = SleepWakeManager()
    private let deepLinkRouter = DeepLinkRouter()
    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController
    private let updaterSettings: UpdaterSettingsModel

    private(set) var arcboxClient: ArcBoxClient?
    private(set) var dockerClient: DockerClient?
    private(set) var startupOrchestrator: StartupOrchestrator?

    private var mainWindowController: MainWindowController?
    private var sidebarViewController: SidebarViewController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?
    private var mainHost: NSHostingController<AnyView>?
    private var settingsHost: NSHostingController<AnyView>?
    private var menuBarHost: NSHostingController<AnyView>?
    private var startupTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var lastDaemonState: DaemonState?
    private var lastValidNavigation: NavItem = .containers
    private var lastShowInMenuBar: Bool
    private var lastUpdateChannel: String
    private var started = false

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        updaterSettings = UpdaterSettingsModel(updater: updaterController.updater)
        lastShowInMenuBar = UserDefaults.standard.bool(forKey: "showInMenuBar")
        lastUpdateChannel = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        super.init()
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    func start() {
        guard !started else { return }
        started = true

        let orchestrator = StartupOrchestrator(
            daemonManager: daemonManager,
            onClientsNeeded: { [unowned self] in try initClientsAndReturn() }
        )
        startupOrchestrator = orchestrator

        installWindows()
        observeNavigation()
        configureDeepLinks()
        observeDaemonState()
        observeAuthState()
        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.defaultsDidChange()
            }
        }

        Task { [weak self] in
            await self?.authSession.loadUserInfo()
        }

        startupTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = CFAbsoluteTimeGetCurrent()
            await orchestrator.start()
            captureStartupResult(orchestrator, startedAt: startedAt)
        }
    }

    func handleDeepLink(_ url: URL) {
        deepLinkRouter.handle(url)
    }

    func showMainWindow() {
        activate()
        mainWindowController?.window?.deminiaturize(nil)
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func showSettings(tab: SettingsTab? = nil) {
        if let tab {
            appVM.settingsTab = tab
        }
        activate()
        settingsWindowController?.window?.deminiaturize(nil)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        activate()
        showAboutWindow()
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    func closeVisibleWindows() {
        statusItemController?.closePopover()
        for window in NSApp.windows where window.isVisible {
            window.close()
        }
    }

    func requestQuit() {
        (NSApp.delegate as? AppDelegate)?.forceQuit = true
        NSApp.terminate(nil)
    }

    func shutdown() async {
        startupTask?.cancel()
        startupTask = nil
        eventMonitor.stop()
        sandboxEventMonitor.stop()
        machineEventMonitor.stop()
        sleepWakeManager.stop()
        DockerContextManager.restorePreviousContext()
        arcboxClient?.close()
        connectionTask?.cancel()
        connectionTask = nil
        daemonManager.stopWatching()
        await daemonManager.disableDaemon()
    }

    private func installWindows() {
        let sidebarViewController = SidebarViewController(
            selection: appVM.currentNav,
            onSelect: { [weak self] item in
                self?.appVM.navigate(to: item)
            },
            onAccount: { [weak self] in
                self?.accountButtonPressed()
            }
        )
        self.sidebarViewController = sidebarViewController

        let mainHost = NSHostingController(rootView: makeMainRoot())
        mainHost.sceneBridgingOptions = .all
        let settingsHost = NSHostingController(rootView: makeSettingsRoot())
        let menuBarHost = NSHostingController(rootView: makeMenuBarRoot())

        self.mainHost = mainHost
        self.settingsHost = settingsHost
        self.menuBarHost = menuBarHost
        mainWindowController = MainWindowController(contentViewController: mainHost)
        settingsWindowController = SettingsWindowController(contentViewController: settingsHost)
        statusItemController = StatusItemController(contentViewController: menuBarHost)
        statusItemController?.setVisible(lastShowInMenuBar)
    }

    private func configureDeepLinks() {
        deepLinkRouter.configure(
            .init(
                appVM: appVM,
                containersVM: containersVM,
                volumesVM: volumesVM,
                imagesVM: imagesVM,
                networksVM: networksVM,
                openMainWindow: { [weak self] in self?.showMainWindow() },
                openSettingsWindow: { [weak self] in self?.showSettings() },
                oauthCallbackScheme: OIDCClientConfiguration.redirectURI.scheme,
                onOAuthCallback: { [weak self] url in
                    Task { await self?.authSession.handleAuthorizationCallback(url) }
                }
            ))
    }

    private func observeDaemonState() {
        lastDaemonState = daemonManager.state
        trackDaemonState()
    }

    private func observeNavigation() {
        if let navigation = appVM.currentNav, !navigation.isComingSoon {
            lastValidNavigation = navigation
        }
        trackNavigation()
    }

    private func trackNavigation() {
        withObservationTracking {
            _ = appVM.currentNav
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.navigationDidChange()
            }
        }
    }

    private func navigationDidChange() {
        trackNavigation()
        guard let navigation = appVM.currentNav else { return }
        guard !navigation.isComingSoon else {
            showComingSoonPanel()
            appVM.currentNav = lastValidNavigation
            return
        }
        lastValidNavigation = navigation
        sidebarViewController?.select(navigation)
    }

    private func observeAuthState() {
        updateAccountButton()
        trackAuthState()
    }

    private func trackAuthState() {
        withObservationTracking {
            _ = authSession.status
            _ = authSession.identity
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.authStateDidChange()
            }
        }
    }

    private func authStateDidChange() {
        trackAuthState()
        updateAccountButton()
    }

    private func trackDaemonState() {
        withObservationTracking {
            _ = daemonManager.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.daemonStateDidChange()
            }
        }
    }

    private func daemonStateDidChange() {
        trackDaemonState()
        let state = daemonManager.state
        guard state != lastDaemonState else { return }
        lastDaemonState = state

        if state.isRunning {
            if dockerClient == nil {
                dockerClient = DockerClient()
                refreshHostedRoots()
            }
            if let dockerClient {
                eventMonitor.start(docker: dockerClient)
                sleepWakeManager.dockerClientRef = dockerClient
                sleepWakeManager.start()
            }
            if let arcboxClient {
                sandboxEventMonitor.start(client: arcboxClient, machineID: "default")
                machineEventMonitor.start(client: arcboxClient)
            }
            DockerContextManager.switchToArcBox()
        } else {
            eventMonitor.stop()
            sandboxEventMonitor.stop()
            machineEventMonitor.stop()
            sleepWakeManager.stop()
            DockerContextManager.restorePreviousContext()
        }
    }

    private func initClientsAndReturn() throws -> ArcBoxClient {
        if let arcboxClient {
            Log.startup.info("Reusing existing ArcBoxClient")
            return arcboxClient
        }

        connectionTask?.cancel()
        let client = try ArcBoxClient()
        connectionTask = Task {
            do {
                Log.startup.info("runConnections starting")
                try await client.runConnections()
                Log.startup.info("runConnections ended")
            } catch {
                Log.startup.error(
                    "runConnections failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        arcboxClient = client
        refreshHostedRoots()
        return client
    }

    private func refreshHostedRoots() {
        mainHost?.rootView = makeMainRoot()
        settingsHost?.rootView = makeSettingsRoot()
        menuBarHost?.rootView = makeMenuBarRoot()
    }

    private func makeMainRoot() -> AnyView {
        guard let sidebarViewController else {
            preconditionFailure("The main sidebar must exist before its SwiftUI host")
        }
        return AnyView(
            ContentView(sidebarViewController: sidebarViewController)
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(networksVM)
                .environment(volumesVM)
                .environment(sandboxEventMonitor)
                .environment(authSession)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.startupOrchestrator, startupOrchestrator)
                .environment(\.accessTokenProvider, authSession)
        )
    }

    private func makeSettingsRoot() -> AnyView {
        AnyView(
            SettingsView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(authSession)
                .environment(systemVmBackendVM)
                .environment(updaterSettings)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.accessTokenProvider, authSession)
        )
    }

    private func makeMenuBarRoot() -> AnyView {
        AnyView(
            MenuBarView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(networksVM)
                .environment(volumesVM)
                .environment(authSession)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.startupOrchestrator, startupOrchestrator)
                .environment(\.accessTokenProvider, authSession)
        )
    }

    private func updateAccountButton() {
        let title: String
        let isBusy: Bool
        let isEnabled: Bool
        let help: String

        switch authSession.status {
        case .signedOut:
            title = "Sign In"
            isBusy = false
            isEnabled = !authSession.configuration.isPlaceholder
            help =
                isEnabled
                ? "Sign in to ArcBox"
                : "No OIDC provider is configured"
        case .signingIn:
            title = "Signing In…"
            isBusy = true
            isEnabled = false
            help = "Signing in to ArcBox"
        case .signedIn:
            title = authSession.identity?.displayName ?? "Account"
            isBusy = false
            isEnabled = true
            help = "Open account settings"
        case .error(let message):
            title = "Sign In"
            isBusy = false
            isEnabled = !authSession.configuration.isPlaceholder
            help = "Sign-in failed: \(message)"
        }

        sidebarViewController?.updateAccount(
            title: title,
            avatarURL: authSession.identity?.avatarURL,
            isBusy: isBusy,
            isEnabled: isEnabled,
            help: help
        )
    }

    private func accountButtonPressed() {
        if authSession.status == .signedIn {
            showSettings(tab: .account)
            return
        }
        guard authSession.status != .signingIn, !authSession.configuration.isPlaceholder else {
            return
        }
        Task {
            await authSession.signIn(using: WebAuthenticationController.shared.authenticate)
        }
    }

    private func activate() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureStartupResult(
        _ orchestrator: StartupOrchestrator,
        startedAt: CFAbsoluteTime
    ) {
        let duration = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        if orchestrator.isReady {
            Analytics.capture(
                .startupCompleted,
                properties: ["duration_ms": duration]
            )
        } else if case .failed(let step, _) = orchestrator.phase {
            Analytics.capture(
                .startupFailed,
                properties: [
                    "duration_ms": duration,
                    "step": step.label,
                ]
            )
        }
    }

    private func defaultsDidChange() {
        let defaults = UserDefaults.standard
        let showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        if showInMenuBar != lastShowInMenuBar {
            lastShowInMenuBar = showInMenuBar
            statusItemController?.setVisible(showInMenuBar)
        }

        let updateChannel = defaults.string(forKey: "updateChannel") ?? "stable"
        if updateChannel != lastUpdateChannel {
            lastUpdateChannel = updateChannel
            updaterController.updater.resetUpdateCycle()
        }
    }
}
