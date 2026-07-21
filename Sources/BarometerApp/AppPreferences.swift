import Combine
import Foundation
import BarometerCore

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let metricMode = "display.metricMode"
        static let displayStyle = "display.style"
        static let showResetCountdown = "display.showResetCountdown"
        static let notificationsEnabled = "notifications.enabled"
        static let onboardingCompleted = "onboarding.completed"
        static let notificationTokens = "notifications.sentTokens"
        static let autoCheckForUpdatesEnabled = "updates.autoCheckEnabled"
        static let lastUpdateCheckDate = "updates.lastCheckDate"
    }

    private let defaults: UserDefaults

    @Published var metricMode: MetricMode { didSet { defaults.set(metricMode.rawValue, forKey: Key.metricMode) } }
    @Published var displayStyle: DisplayStyle { didSet { defaults.set(displayStyle.rawValue, forKey: Key.displayStyle) } }
    @Published var showResetCountdown: Bool { didSet { defaults.set(showResetCountdown, forKey: Key.showResetCountdown) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) } }
    @Published var autoCheckForUpdatesEnabled: Bool { didSet { defaults.set(autoCheckForUpdatesEnabled, forKey: Key.autoCheckForUpdatesEnabled) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: "display.percentageTintColor")
        defaults.removeObject(forKey: "display.iconTintColor")
        metricMode = MetricMode(rawValue: defaults.string(forKey: Key.metricMode) ?? "") ?? .fiveHour
        let previousDisplayStyle = defaults.string(forKey: Key.displayStyle)
        let migratedDisplayStyle: DisplayStyle
        switch previousDisplayStyle {
        case DisplayStyle.icon.rawValue:
            migratedDisplayStyle = .icon
        case DisplayStyle.ring.rawValue:
            migratedDisplayStyle = .ring
        default:
            // Also covers a fresh install (nil) and retired legacy values
            // ("labeled", "percentage") — Ring is the default appearance.
            migratedDisplayStyle = .ring
        }
        displayStyle = migratedDisplayStyle
        defaults.set(migratedDisplayStyle.rawValue, forKey: Key.displayStyle)
        defaults.removeObject(forKey: "display.ringContentStyle")
        showResetCountdown = defaults.bool(forKey: Key.showResetCountdown)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        autoCheckForUpdatesEnabled = defaults.bool(forKey: Key.autoCheckForUpdatesEnabled)
    }

    var notificationTokens: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.notificationTokens) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.notificationTokens) }
    }

    var lastUpdateCheckDate: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheckDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheckDate) }
    }
}
