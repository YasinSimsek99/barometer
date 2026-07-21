import AppKit
import ClaudeCodeBridge
import Combine
import Foundation
import LocalAuthentication
import OSLog
import BarometerCore
import UserNotifications

/// A System Settings pane Barometer can hand off to when it cannot grant
/// itself a permission (notifications) or cannot detect whether macOS is
/// blocking it in the background (login items).
enum SystemSettingsDestination: Equatable {
    case notifications
    case loginItems

    var url: URL {
        switch self {
        case .notifications: URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        case .loginItems: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        }
    }

    var buttonTitle: String {
        switch self {
        case .notifications: "Open Notification Settings"
        case .loginItems: "Open Login Items Settings"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var integrationStatus: IntegrationStatus = .disconnected
    @Published var integrationPreview: IntegrationPreview?
    @Published private(set) var lastError: String?
    @Published var showingSettings = false
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var notificationRequestInFlight = false
    @Published private(set) var eraseRequestInFlight = false
    @Published private(set) var showsNotificationsSettingsPopover = false
    @Published private(set) var showsLoginItemsSettingsPopover = false

    let preferences: AppPreferences
    private let cache: UsageCache
    private let settingsManager: ClaudeSettingsManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "app")
    private var timer: Timer?
    private var preferencesCancellable: AnyCancellable?
    private var sentNotificationTokens: Set<String>

    init(
        preferences: AppPreferences = AppPreferences(),
        cache: UsageCache = UsageCache(),
        settingsManager: ClaudeSettingsManager = ClaudeSettingsManager(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        self.preferences = preferences
        self.cache = cache
        self.settingsManager = settingsManager
        self.launchAtLoginManager = launchAtLoginManager
        self.launchAtLoginEnabled = launchAtLoginManager.isEnabled
        self.sentNotificationTokens = preferences.notificationTokens
        preferencesCancellable = preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        repairLaunchAtLoginPath()
        synchronizeNotificationAuthorization()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var helperExecutableURL: URL {
        if let configuredPath = ProcessInfo.processInfo.environment["BAROMETER_BRIDGE_PATH"],
           FileManager.default.isExecutableFile(atPath: configuredPath) {
            return URL(fileURLWithPath: configuredPath)
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(AppIdentity.current.bridgeExecutableName)
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }

        return Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent(AppIdentity.current.bridgeExecutableName) ?? bundled
    }

    func refresh() {
        snapshot = (try? cache.readSanitized())?.normalized()
        integrationStatus = settingsManager.status()
        if preferences.notificationsEnabled, let snapshot {
            deliverThresholdNotifications(for: snapshot)
        }
        objectWillChange.send()
    }

    func prepareIntegrationPreview() {
        do {
            integrationPreview = try settingsManager.preview(helperExecutableURL: helperExecutableURL)
            setError(nil)
        } catch {
            setError(error.localizedDescription)
        }
    }

    func connect() {
        do {
            try settingsManager.install(helperExecutableURL: helperExecutableURL)
            preferences.onboardingCompleted = true
            integrationPreview = nil
            setError(nil)
            logger.notice("Claude Code integration connected")
            refresh()
        } catch {
            setError(error.localizedDescription)
            logger.error("Claude Code connection failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disconnect() {
        do {
            try settingsManager.disconnect()
            setError(nil)
            logger.notice("Claude Code integration disconnected")
            refresh()
        } catch {
            setError(error.localizedDescription)
            logger.error("Claude Code disconnect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens the System Settings pane Barometer could not take the user to
    /// itself, e.g. after a denied notification permission.
    func openSettingsDestination(_ destination: SystemSettingsDestination) {
        NSWorkspace.shared.open(destination.url)
    }

    func dismissNotificationsSettingsPopover() { showsNotificationsSettingsPopover = false }
    func dismissLoginItemsSettingsPopover() { showsLoginItemsSettingsPopover = false }

    private func setError(_ message: String?) {
        lastError = message
    }

    /// Requires Touch ID or the account password before erasing the usage
    /// cache, settings backups, and disconnecting Claude Code.
    func eraseAllData() {
        guard !eraseRequestInFlight else { return }
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            setError("Erasing data requires Touch ID or a Mac password, and neither is available on this Mac.")
            logger.error("Data erase blocked: no local authentication method available")
            return
        }

        eraseRequestInFlight = true
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "erase all local Barometer data"
        ) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.eraseRequestInFlight = false
                guard success else {
                    if let laError = error as? LAError, laError.code == .userCancel {
                        return
                    }
                    self.setError("Authentication failed: \(error?.localizedDescription ?? "unknown error").")
                    self.logger.error("Data erase authentication failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                    return
                }
                self.performErase()
            }
        }
    }

    private func performErase() {
        do {
            try settingsManager.eraseAllLocalData()
            try cache.erase()
            setError(nil)
            logger.notice("All local Barometer data erased")
            refresh()
        } catch {
            setError("Could not erase all data: \(error.localizedDescription)")
            logger.error("Data erase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            preferences.notificationsEnabled = false
            setError(nil)
            return
        }
        guard supportsUserNotifications else {
            preferences.notificationsEnabled = false
            setError("Notifications require the packaged app. Use make install, then open Barometer from ~/Applications.")
            logger.notice("Notification authorization skipped outside an app bundle")
            return
        }
        guard !notificationRequestInFlight else { return }
        notificationRequestInFlight = true

        // Uses the async UserNotifications API rather than a completion-handler
        // closure. UNUserNotificationCenter invokes completion handlers from an
        // arbitrary background queue, and Swift can misinfer such a closure as
        // inheriting this @MainActor method's isolation, which then traps at
        // runtime when the framework actually calls it off the main thread.
        // await correctly resumes back on this method's actor instead.
        Task { [weak self] in
            guard let self else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.notificationRequestInFlight = false
                self.preferences.notificationsEnabled = true
                self.setError(nil)
                self.logger.notice("Usage notifications enabled")
                self.refresh()
            case .denied:
                self.notificationRequestInFlight = false
                self.preferences.notificationsEnabled = false
                self.showsNotificationsSettingsPopover = true
                self.logger.error("Notification authorization is denied")
            case .notDetermined:
                await self.requestNotificationAuthorization()
            @unknown default:
                self.notificationRequestInFlight = false
                self.preferences.notificationsEnabled = false
                self.setError("The current notification authorization state is unsupported.")
                self.logger.error("Unknown notification authorization state")
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            guard let executableURL = Bundle.main.executableURL else {
                throw LaunchAtLoginError.missingExecutable
            }
            try launchAtLoginManager.setEnabled(enabled, executableURL: executableURL)
            launchAtLoginEnabled = enabled
            setError(nil)
            if enabled {
                showsLoginItemsSettingsPopover = true
            }
            logger.notice("Launch at login changed: \(enabled, privacy: .public)")
        } catch {
            setError("Launch at login could not be changed: \(error.localizedDescription)")
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            logger.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestNotificationAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationRequestInFlight = false
            preferences.notificationsEnabled = granted
            if granted {
                setError(nil)
                logger.notice("Notification authorization granted")
                refresh()
            } else {
                showsNotificationsSettingsPopover = true
                logger.notice("Notification authorization was not granted")
            }
        } catch {
            notificationRequestInFlight = false
            preferences.notificationsEnabled = false
            setError("Notifications could not be enabled: \(error.localizedDescription)")
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func synchronizeNotificationAuthorization() {
        guard supportsUserNotifications else { return }
        Task { [weak self] in
            guard let self else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied {
                self.preferences.notificationsEnabled = false
            }
        }
    }

    private func repairLaunchAtLoginPath() {
        guard launchAtLoginEnabled, let executableURL = Bundle.main.executableURL else { return }
        do {
            try launchAtLoginManager.refreshExecutablePathIfEnabled(executableURL)
        } catch {
            setError("Launch at login needs attention: \(error.localizedDescription)")
            logger.error("Launch at login path repair failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deliverThresholdNotifications(for snapshot: UsageSnapshot) {
        guard supportsUserNotifications else { return }
        let evaluation = NotificationThresholdTracker().evaluate(
            snapshot: snapshot,
            sentTokens: sentNotificationTokens
        )
        sentNotificationTokens = evaluation.sentTokens
        preferences.notificationTokens = evaluation.sentTokens
        for event in evaluation.events {
            let content = UNMutableNotificationContent()
            content.title = "Claude \(event.windowLabel) usage is \(Int(event.usedPercentage.rounded()))%"
            content.body = event.threshold == 90 ? "You are close to the usage limit." : "Usage passed \(event.threshold)%."
            content.sound = .default
            let request = UNNotificationRequest(identifier: event.identifier, content: content, trigger: nil)
            Task { [logger] in
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private var supportsUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
