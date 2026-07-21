#if DEBUG
import AppKit
import ClaudeCodeBridge
import BarometerCore
import SwiftUI

@MainActor
enum DebugPreviewRenderer {
    static func renderIfRequested(arguments: [String]) -> Bool {
        guard let flagIndex = arguments.firstIndex(of: "--render-preview"),
              arguments.indices.contains(flagIndex + 1)
        else { return false }

        do {
            try render(to: URL(fileURLWithPath: arguments[flagIndex + 1]), showSettings: arguments.contains("--settings"))
        } catch {
            FileHandle.standardError.write(Data("Preview rendering failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        return true
    }

    private static func render(to outputURL: URL, showSettings: Bool) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("barometer-preview-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let suiteName = "io.github.yasinsimsek.barometer.preview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CocoaError(.featureUnsupported)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "onboarding.completed")
        defaults.set(DisplayStyle.icon.rawValue, forKey: "display.style")

        let cache = UsageCache(fileURL: root.appendingPathComponent("Cache/usage.json"))
        try cache.write(UsageSnapshot(
            capturedAt: Date(),
            fiveHour: RateLimitWindow(usedPercentage: 74, resetsAt: Date().addingTimeInterval(10_800)),
            sevenDay: RateLimitWindow(usedPercentage: 18, resetsAt: Date().addingTimeInterval(432_000))
        ))

        let integrationPaths = ClaudeIntegrationPaths(
            settingsURL: root.appendingPathComponent("Claude/settings.json"),
            supportDirectoryURL: root.appendingPathComponent("Support", isDirectory: true)
        )
        let settingsManager = ClaudeSettingsManager(paths: integrationPaths)
        try settingsManager.install(helperExecutableURL: URL(fileURLWithPath: argumentsExecutablePath()))

        let model = AppModel(
            preferences: AppPreferences(defaults: defaults),
            cache: cache,
            settingsManager: settingsManager,
            launchAtLoginManager: LaunchAtLoginManager(
                launchAgentsDirectoryURL: root.appendingPathComponent("LaunchAgents", isDirectory: true)
            )
        )
        model.showingSettings = showSettings

        let preview = ContentView(model: model)
            .environment(\.colorScheme, .dark)
            .padding(36)
            .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: outputURL, options: .atomic)
    }

    private static func argumentsExecutablePath() -> String {
        URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    }
}
#endif
