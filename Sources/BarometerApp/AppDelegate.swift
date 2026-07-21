import AppKit
import Combine
import BarometerCore
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var hostingController: NSHostingController<ContentView>?
    private var cancellable: AnyCancellable?
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }

        let host = NSHostingController(rootView: ContentView(model: model))
        hostingController = host
        panel = MenuBarPanel(contentViewController: host)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        cancellable = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
                self?.schedulePanelLayout()
            }
        }
        updateStatusItem()

        if CommandLine.arguments.contains("--show-panel") {
            let settings = CommandLine.arguments.contains("--show-settings")
            DispatchQueue.main.async { [weak self] in self?.showPanel(settings: settings ? true : nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitors()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePanel()
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel(settings: Bool? = nil) {
        if let settings { model.showingSettings = settings }
        model.refresh()
        layoutPanel()
        panel?.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeEventMonitors()
    }

    private func layoutPanel() {
        guard let button = statusItem?.button,
              let panel,
              let host = hostingController,
              let screen = button.window?.screen ?? NSScreen.main
        else { return }

        host.view.layoutSubtreeIfNeeded()
        let fittingSize = host.view.fittingSize
        let width: CGFloat = 400
        let height = min(max(fittingSize.height, 220), screen.visibleFrame.height - 24)
        panel.setContentSize(NSSize(width: width, height: height))

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = button.window?.convertToScreen(buttonRectInWindow)
            ?? NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY, width: 1, height: 1)
        let margin: CGFloat = 8
        let proposedX = buttonRectOnScreen.midX - width / 2
        let x = min(
            max(proposedX, screen.visibleFrame.minX + margin),
            screen.visibleFrame.maxX - width - margin
        )
        let y = screen.visibleFrame.maxY - height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func schedulePanelLayout() {
        guard panel?.isVisible == true else { return }
        DispatchQueue.main.async { [weak self] in self?.layoutPanel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.layoutPanel()
        }
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                Task { @MainActor in self.closePanel() }
                return nil
            }
            if event.window !== self.panel {
                Task { @MainActor in self.closePanel() }
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = makeContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: button.bounds.minY), in: button)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Show Usage", action: #selector(showUsage), symbol: "gauge.with.dots.needle.67percent"))
        menu.addItem(item("Refresh Now", action: #selector(refreshUsage), key: "r", symbol: "arrow.clockwise"))

        let metricParent = NSMenuItem(title: "Displayed Metric", action: nil, keyEquivalent: "")
        let metricMenu = NSMenu()
        for mode in MetricMode.allCases {
            let entry = item(mode.label, action: #selector(selectMetric))
            entry.representedObject = mode.rawValue
            entry.state = model.preferences.metricMode == mode ? .on : .off
            metricMenu.addItem(entry)
        }
        metricParent.submenu = metricMenu
        menu.addItem(metricParent)

        let styleParent = NSMenuItem(title: "Menu Bar Appearance", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in DisplayStyle.allCases {
            let entry = item(style.label, action: #selector(selectDisplayStyle))
            entry.representedObject = style.rawValue
            entry.state = model.preferences.displayStyle == style ? .on : .off
            styleMenu.addItem(entry)
        }
        styleParent.submenu = styleMenu
        menu.addItem(styleParent)

        let countdown = item("Show Reset Countdown", action: #selector(toggleResetCountdown), symbol: "clock.arrow.circlepath")
        countdown.state = model.preferences.showResetCountdown ? .on : .off
        menu.addItem(countdown)

        menu.addItem(.separator())
        let notifications = item("Usage Notifications", action: #selector(toggleNotifications), symbol: "bell")
        notifications.state = model.preferences.notificationsEnabled ? .on : .off
        notifications.isEnabled = !model.notificationRequestInFlight
        menu.addItem(notifications)
        let login = item("Launch at Login", action: #selector(toggleLaunchAtLogin), symbol: "power")
        login.state = model.launchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let connectionTitle = model.integrationStatus == .connected ? "Claude Code: Connected" : "Claude Code Connection…"
        let connection = item(connectionTitle, action: #selector(showConnectionSettings), symbol: "terminal")
        menu.addItem(connection)
        menu.addItem(item("Settings…", action: #selector(showSettings), key: ",", symbol: "slider.horizontal.3"))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(AppIdentity.current.appName)", action: #selector(quit), key: "q", symbol: "power"))
        return menu
    }

    private func item(
        _ title: String,
        action: Selector,
        key: String = "",
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func showUsage() { showPanel(settings: false) }
    @objc private func showSettings() { showPanel(settings: true) }
    @objc private func showConnectionSettings() {
        if model.integrationStatus != .connected { model.prepareIntegrationPreview() }
        showPanel(settings: true)
    }
    @objc private func refreshUsage() {
        model.refresh()
        if panel?.isVisible == true { layoutPanel() }
    }
    @objc private func selectMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = MetricMode(rawValue: raw) else { return }
        model.preferences.metricMode = mode
    }
    @objc private func selectDisplayStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = DisplayStyle(rawValue: raw) else { return }
        model.preferences.displayStyle = style
    }
    @objc private func toggleResetCountdown() {
        model.preferences.showResetCountdown.toggle()
    }
    @objc private func toggleNotifications() {
        model.setNotificationsEnabled(!model.preferences.notificationsEnabled)
    }
    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLoginEnabled)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let formatter = StatusDisplayFormatter()
        let formattedTitle = formatter.title(
            snapshot: model.snapshot,
            metricMode: model.preferences.metricMode
        )
        let countdownValue = model.preferences.showResetCountdown
            ? ResetCountdownFormatter().menuBarValue(
                snapshot: model.snapshot,
                metricMode: model.preferences.metricMode
            )
            : nil
        let isStale = model.snapshot?.isStale() ?? true
        button.attributedTitle = NSAttributedString(string: "")
        if model.preferences.displayStyle == .icon || model.preferences.displayStyle == .ring {
            let metrics = statusRingMetrics(snapshot: model.snapshot)
            button.image = StatusRingImage.make(
                metrics: metrics,
                isStale: isStale,
                countdown: countdownValue.map {
                    StatusRingImage.Countdown(metricLabel: $0.windowLabel, text: $0.text)
                },
                style: model.preferences.displayStyle == .ring ? .ring : .needle
            )
        } else {
            let title: String
            if model.preferences.metricMode == .both {
                // Appending the countdown at the end (e.g. "5h 71% · 7d 30% ·
                // 5h↻50m") reads as detached from whichever window it belongs
                // to. Interleave it next to that window's own percentage
                // instead ("5h 71%↻50m · 7d 30%").
                title = bothMetricTitle(snapshot: model.snapshot, countdown: countdownValue)
            } else {
                let countdown = countdownValue.map { value in
                    switch model.preferences.metricMode {
                    case .fiveHour, .sevenDay:
                        return value.text
                    case .both, .highest:
                        return "\(value.windowLabel)\(value.text)"
                    }
                }
                title = countdown.map { "\(formattedTitle) · \($0)" } ?? formattedTitle
            }
            button.image = StatusTextImage.make(text: title, isStale: isStale)
        }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = .white
        button.toolTip = statusToolTip
    }

    private func bothMetricTitle(snapshot: UsageSnapshot?, countdown: ResetCountdownValue?) -> String {
        func percentageText(_ window: RateLimitWindow?) -> String {
            window.map { "\(Int($0.usedPercentage.rounded()))%" } ?? "—"
        }
        var fivePart = "5h \(percentageText(snapshot?.fiveHour))"
        var sevenPart = "7d \(percentageText(snapshot?.sevenDay))"
        if let countdown {
            switch countdown.windowLabel {
            case "5h": fivePart += countdown.text
            case "7d": sevenPart += countdown.text
            default: break
            }
        }
        return "\(fivePart) · \(sevenPart)"
    }

    private func statusRingMetrics(snapshot: UsageSnapshot?) -> [StatusRingImage.Metric] {
        switch model.preferences.metricMode {
        case .both:
            return [
                StatusRingImage.Metric(label: "5h", percentage: snapshot?.fiveHour?.usedPercentage),
                StatusRingImage.Metric(label: "7d", percentage: snapshot?.sevenDay?.usedPercentage),
            ]
        case .fiveHour:
            return [StatusRingImage.Metric(label: "5h", percentage: snapshot?.fiveHour?.usedPercentage)]
        case .sevenDay:
            return [StatusRingImage.Metric(label: "7d", percentage: snapshot?.sevenDay?.usedPercentage)]
        case .highest:
            return [StatusRingImage.Metric(label: "max", percentage: snapshot?.highestUsage)]
        }
    }

    private var statusToolTip: String {
        guard let snapshot = model.snapshot else {
            return "Barometer · Waiting for Claude Code"
        }
        let fiveHour = snapshot.fiveHour.map { "5-hour \(Int($0.usedPercentage.rounded()))%" } ?? "5-hour —"
        let sevenDay = snapshot.sevenDay.map { "7-day \(Int($0.usedPercentage.rounded()))%" } ?? "7-day —"
        let state = snapshot.isStale() ? "stale" : "live"
        return "Barometer · \(fiveHour) · \(sevenDay) · \(state)"
    }

}
