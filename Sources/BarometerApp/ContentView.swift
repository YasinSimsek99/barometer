import AppKit
import ClaudeCodeBridge
import BarometerCore
import SwiftUI

/// Fixed dark palette for the popup, matching the "Turn 1a" design.
private enum Palette {
    static let panelBackground = Color(red: 0x1c / 255, green: 0x1c / 255, blue: 0x1f / 255)
    static let border = Color.white.opacity(0.08)
    static let borderSubtle = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.06)

    static let textPrimary = Color(red: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf7 / 255)
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.4)
    static let textQuaternary = Color.white.opacity(0.35)

    static let cardBackground = Color.white.opacity(0.04)
    static let chipBackground = Color.white.opacity(0.08)
    static let rowHover = Color.white.opacity(0.04)

    static let ringTrack = Color.white.opacity(0.08)
    static let ringValue = Color(red: 0xe8 / 255, green: 0xe8 / 255, blue: 0xea / 255)
    static let barTrack = Color.white.opacity(0.1)

    static let statusGreen = Color(red: 0x4a / 255, green: 0xde / 255, blue: 0x80 / 255)

    static let dangerText = Color(red: 1, green: 107 / 255, blue: 107 / 255)
    static let dangerBackground = Color(red: 1, green: 80 / 255, blue: 80 / 255).opacity(0.06)
    static let dangerBorder = Color(red: 1, green: 80 / 255, blue: 80 / 255).opacity(0.15)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showingClaudeDataHelp = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

            Hairline()

            Group {
                if !model.preferences.onboardingCompleted {
                    onboarding
                } else if model.showingSettings {
                    settings
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    dashboard
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .padding(14)

            if let error = model.lastError {
                errorBanner(error)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            Hairline()
            footer
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
        }
        .frame(width: 340)
        .background(Palette.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.18), value: model.showingSettings)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if model.showingSettings {
            settingsHeader
        } else {
            brandHeader
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            AppMark(size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(AppIdentity.current.appName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(freshnessText)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if model.preferences.onboardingCompleted {
                Button {
                    model.showingSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle())
                .help("Settings")
                .accessibilityLabel("Open settings")
            }
        }
    }

    private var settingsHeader: some View {
        ZStack {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            HStack {
                Button {
                    model.showingSettings = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Usage").font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Spacer()

                Button("Done") { model.showingSettings = false }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityHint("Returns to usage")
            }
        }
    }

    // MARK: - Dashboard (Turn 1a)

    private var dashboard: some View {
        VStack(spacing: 4) {
            heroRing

            VStack(spacing: 2) {
                HeroQuotaRow(title: "5 hour", window: model.snapshot?.fiveHour)
                HeroQuotaRow(title: "7 day", window: model.snapshot?.sevenDay)
            }

            if model.integrationStatus != .connected {
                connectionNudge
                    .padding(.top, 8)
            }
        }
    }

    private var heroRing: some View {
        let highest = model.snapshot?.highestUsage
        let progress = max(0, min((highest ?? 0) / 100, 1))
        return ZStack {
            Circle()
                .stroke(Palette.ringTrack, lineWidth: 9)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.ringValue, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)

            VStack(spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(highest.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textTertiary)
                }
                Text("highest usage")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(width: 148, height: 148)
        .padding(.vertical, 10)
    }

    private var connectionNudge: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.24), lineWidth: 1)
                Image(systemName: connectionSymbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(connectionTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(connectionDetail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Open") {
                model.prepareIntegrationPreview()
                model.showingSettings = true
            }
            .buttonStyle(GhostButtonStyle(compact: true))
        }
        .padding(11)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.borderSubtle, lineWidth: 0.75)
        }
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        VStack(spacing: 14) {
            VStack(spacing: 11) {
                AppMark(size: 60)
                VStack(spacing: 4) {
                    Text("Claude usage. Nothing else.")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text("A private, local window into your account limits.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 4)

            Card {
                VStack(alignment: .leading, spacing: 11) {
                    PrivacyLine(symbol: "key.slash", text: "No credentials, cookies, or API keys")
                    Hairline()
                    PrivacyLine(symbol: "text.bubble", text: "No prompts, conversations, or transcripts")
                    Hairline()
                    PrivacyLine(symbol: "network.slash", text: "No background network requests or analytics")
                }
            }

            Card {
                VStack(spacing: 10) {
                    settingsToggleRow(
                        title: "Launch at login",
                        systemImage: "power",
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    .popover(isPresented: loginItemsSettingsPopover, arrowEdge: .top) {
                        settingsPopover(
                            message: "Barometer was added to Login Items. If it doesn't launch automatically next time, allow it here.",
                            destination: .loginItems
                        )
                    }
                    Hairline()
                    settingsToggleRow(
                        title: "Notify at 70% and 90%",
                        systemImage: "bell",
                        isOn: Binding(
                            get: { model.preferences.notificationsEnabled },
                            set: { model.setNotificationsEnabled($0) }
                        )
                    )
                    .disabled(model.notificationRequestInFlight)
                    .popover(isPresented: notificationsSettingsPopover, arrowEdge: .top) {
                        settingsPopover(
                            message: "Notifications are disabled in System Settings for Barometer.",
                            destination: .notifications
                        )
                    }
                }
            }

            if let preview = model.integrationPreview {
                Card {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Review change", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(preview.summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.textTertiary)
                            .textSelection(.enabled)
                    }
                }
                Button("Connect Claude Code") { model.connect() }
                    .buttonStyle(FilledButtonStyle())
                    .frame(maxWidth: .infinity)
            } else {
                Button("Review local connection") { model.prepareIntegrationPreview() }
                    .buttonStyle(FilledButtonStyle())
                    .frame(maxWidth: .infinity)
            }

            Button("Skip for now") { model.preferences.onboardingCompleted = true }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - Settings (Turn 1d)

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "MENU BAR") {
                pickerRow(
                    title: "Metric",
                    selection: Binding(
                        get: { model.preferences.metricMode },
                        set: { model.preferences.metricMode = $0 }
                    ),
                    values: MetricMode.allCases
                ) { $0.label }

                RowDivider()

                pickerRow(
                    title: "Appearance",
                    selection: Binding(
                        get: { model.preferences.displayStyle },
                        set: { model.preferences.displayStyle = $0 }
                    ),
                    values: DisplayStyle.allCases
                ) { $0.label }

                RowDivider()

                settingsToggleRow(
                    title: "Reset countdown",
                    systemImage: "clock.arrow.circlepath",
                    isOn: Binding(
                        get: { model.preferences.showResetCountdown },
                        set: { model.preferences.showResetCountdown = $0 }
                    )
                )
            }

            SettingsSection(title: "AUTOMATION") {
                settingsToggleRow(
                    title: "Usage notifications",
                    systemImage: "bell",
                    isOn: Binding(
                        get: { model.preferences.notificationsEnabled },
                        set: { model.setNotificationsEnabled($0) }
                    )
                )
                .disabled(model.notificationRequestInFlight)
                .popover(isPresented: notificationsSettingsPopover, arrowEdge: .top) {
                    settingsPopover(
                        message: "Notifications are disabled in System Settings for Barometer.",
                        destination: .notifications
                    )
                }

                RowDivider()

                settingsToggleRow(
                    title: "Launch at login",
                    systemImage: "power",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .popover(isPresented: loginItemsSettingsPopover, arrowEdge: .top) {
                    settingsPopover(
                        message: "Barometer was added to Login Items. If it doesn't launch automatically next time, allow it here.",
                        destination: .loginItems
                    )
                }
            }

            SettingsSection(title: "CLAUDE CODE", accessory: { AnyView(claudeDataHelpButton) }) {
                integrationSettings
            }

            SettingsSection(title: "UPDATES") {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Version \(currentVersionText)")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textPrimary)
                        if let updateStatusText {
                            Text(updateStatusText)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    Spacer()
                    updateActionButton
                }
                .padding(.vertical, 9)

                RowDivider()

                settingsToggleRow(
                    title: "Check automatically once a day",
                    systemImage: "arrow.triangle.2.circlepath",
                    isOn: Binding(
                        get: { model.preferences.autoCheckForUpdatesEnabled },
                        set: { model.preferences.autoCheckForUpdatesEnabled = $0 }
                    )
                )
            }

            dataSection
        }
    }

    private var currentVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var updateStatusText: String? {
        if model.updateCheckInFlight { return "Checking…" }
        switch model.updateCheckResult {
        case nil: return nil
        case .upToDate: return "You're up to date"
        case .updateAvailable(let version, _): return "\(version) is available"
        case .failed(let message): return message
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        if case .updateAvailable = model.updateCheckResult {
            Button("Update") { model.openLatestRelease() }
                .buttonStyle(GhostButtonStyle(compact: true))
        } else {
            Button("Check") { model.checkForUpdates() }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(model.updateCheckInFlight)
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DATA")
            VStack(alignment: .leading, spacing: 9) {
                Text("Erases the usage cache and saved status-line backups on this Mac, and disconnects Claude Code. Requires Touch ID or your Mac password.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Erase All Local Data") { model.eraseAllData() }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(model.eraseRequestInFlight)
            }
        }
    }

    private var claudeDataHelpButton: some View {
        Button {
            showingClaudeDataHelp.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textTertiary)
        .help("What Barometer reads from Claude Code")
        .accessibilityLabel("What Barometer reads from Claude Code")
        .popover(isPresented: $showingClaudeDataHelp, arrowEdge: .top) {
            claudeDataHelpContent
        }
    }

    private var claudeDataHelpContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How usage is read")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Claude Code sends its status-line JSON to Barometer's helper on your Mac. The helper keeps only the 5-hour and 7-day usage percentages and their reset times — everything else, including model details, context usage, prompts, transcripts, token counts, cost, and credentials, is discarded before it reaches the app.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("No network requests are made.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(12)
        .frame(width: 260)
    }

    @ViewBuilder
    private var integrationSettings: some View {
        switch model.integrationStatus {
        case .connected:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Palette.statusGreen).frame(width: 6, height: 6)
                    Text("Connected locally")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text("PRIVATE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Palette.textQuaternary)
                }
                Text("Barometer keeps only account-limit percentages and reset times on this Mac.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Disconnect and restore previous status line") { model.disconnect() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
        case .disconnected:
            VStack(alignment: .leading, spacing: 9) {
                Text("Connect through Claude Code's local status line. No account login is required.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                if let preview = model.integrationPreview {
                    Text(preview.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.textTertiary)
                        .textSelection(.enabled)
                    Button("Connect Claude Code") { model.connect() }
                        .buttonStyle(FilledButtonStyle(compact: true))
                } else {
                    Button("Review connection") { model.prepareIntegrationPreview() }
                        .buttonStyle(GhostButtonStyle(compact: true))
                }
            }
        case .conflict:
            Label(
                "Claude settings changed after connection. Barometer left them untouched.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if model.preferences.onboardingCompleted && !model.showingSettings {
                HStack(spacing: 6) {
                    Circle().fill(footerStatusColor).frame(width: 6, height: 6)
                    Text(footerStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refresh")
            .accessibilityLabel("Refresh")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .keyboardShortcut("q", modifiers: [.command])
            .help("Quit")
            .accessibilityLabel("Quit")
        }
    }

    // MARK: - Shared rows & popovers

    private func settingsToggleRow(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            CustomToggle(isOn: isOn)
        }
        .padding(.vertical, 9)
    }

    private func pickerRow<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        values: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            ValueChip(values: values, selection: selection, label: label)
        }
        .padding(.vertical, 9)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Palette.textTertiary)
            .padding(.leading, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(10)
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.borderSubtle, lineWidth: 0.75)
        }
    }

    private func settingsLink(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 10.5, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textPrimary)
    }

    private func settingsPopover(message: String, destination: SystemSettingsDestination) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            settingsLink(title: destination.buttonTitle) {
                model.openSettingsDestination(destination)
            }
        }
        .padding(12)
        .frame(width: 230)
    }

    private var notificationsSettingsPopover: Binding<Bool> {
        Binding(
            get: { model.showsNotificationsSettingsPopover },
            set: { if !$0 { model.dismissNotificationsSettingsPopover() } }
        )
    }

    private var loginItemsSettingsPopover: Binding<Bool> {
        Binding(
            get: { model.showsLoginItemsSettingsPopover },
            set: { if !$0 { model.dismissLoginItemsSettingsPopover() } }
        )
    }

    private var connectionTitle: String {
        switch model.integrationStatus {
        case .connected: "Claude Code connected"
        case .disconnected: "Claude Code not connected"
        case .conflict: "Connection needs attention"
        }
    }

    private var connectionDetail: String {
        switch model.integrationStatus {
        case .connected: "Limits and session summary stay on this Mac"
        case .disconnected: "Connect the local status line to receive usage"
        case .conflict: "Your Claude settings were not overwritten"
        }
    }

    private var connectionSymbol: String {
        switch model.integrationStatus {
        case .connected: "checkmark"
        case .disconnected: "link"
        case .conflict: "exclamationmark"
        }
    }

    private var footerStatusColor: Color {
        switch model.integrationStatus {
        case .connected: Palette.statusGreen
        case .disconnected: Color.white.opacity(0.25)
        case .conflict: Color.orange
        }
    }

    private var footerStatusText: String {
        switch model.integrationStatus {
        case .connected: "Claude Code · local"
        case .disconnected: "Claude Code not connected"
        case .conflict: "Connection needs attention"
        }
    }

    private var freshnessText: String {
        guard let snapshot = model.snapshot else { return "Waiting for Claude Code" }
        let time = snapshot.capturedAt.formatted(date: .omitted, time: .shortened)
        if snapshot.isStale() {
            return "Stale · \(time)"
        }
        return "Updated · \(time)"
    }
}

private struct HeroQuotaRow: View {
    let title: String
    let window: RateLimitWindow?
    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(resetText)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                MiniBar(value: window?.usedPercentage ?? 0)
                    .frame(width: 72, height: 4)
                Text(window.map { "\(Int($0.usedPercentage.rounded()))%" } ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(isHovering ? Palette.rowHover : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }

    private var resetText: String {
        guard let reset = window?.resetsAt else { return "Reset unavailable" }
        if reset <= Date() { return "Reset complete · waiting for Claude" }
        let remaining = ResetCountdownFormatter().duration(until: reset)
        return "Resets in \(remaining)"
    }
}

private struct CustomToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Palette.textPrimary : Color.white.opacity(0.12))
                Circle()
                    .fill(isOn ? Palette.panelBackground : Color(red: 0xa8 / 255, green: 0xa8 / 255, blue: 0xad / 255))
                    .padding(2)
            }
            .frame(width: 38, height: 23)
        }
        .buttonStyle(.plain)
    }
}

/// A custom dropdown chip, deliberately not `Picker`/`Menu` — both wrap a
/// native AppKit control that a plain SwiftUI `Button` + `.popover` avoids.
private struct ValueChip<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @State private var showingOptions = false

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            HStack(spacing: 4) {
                Text(label(selection))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Palette.chipBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingOptions, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection = value
                        showingOptions = false
                    } label: {
                        HStack {
                            Text(label(value))
                            Spacer()
                            if value == selection {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.textPrimary)
            .padding(.vertical, 4)
            .frame(width: 170)
        }
    }
}

private struct MiniBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.barTrack)
                Capsule()
                    .fill(Palette.ringValue)
                    .frame(width: proxy.size.width * max(0, min(value / 100, 1)))
            }
        }
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

private struct AppMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0x2c / 255, green: 0x2c / 255, blue: 0x30 / 255), Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x26 / 255)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(Palette.ringValue, style: StrokeStyle(lineWidth: max(1.5, size * 0.09), lineCap: .round))
                .rotationEffect(.degrees(45))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
    }
}

private struct PrivacyLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.textQuaternary)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var accessory: (() -> AnyView)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                accessory?()
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.borderSubtle, lineWidth: 0.75)
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.borderSubtle, lineWidth: 0.75)
            }
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.75)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.75)
    }
}

private struct FilledButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(Palette.panelBackground)
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 7 : 10)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(
                Palette.ringValue.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct GhostButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 6 : 10)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.14 : 0.08),
                in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.dangerText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Palette.dangerBackground,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Palette.dangerBorder, lineWidth: 0.75)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.16 : 0.1),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.textPrimary)
            .frame(width: 28, height: 26)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.12 : 0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}
