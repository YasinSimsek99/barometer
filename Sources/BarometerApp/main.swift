import AppKit
import ClaudeCodeBridge
import Darwin
import BarometerCore

#if DEBUG
if DebugPreviewRenderer.renderIfRequested(arguments: CommandLine.arguments) {
    exit(0)
}
#endif

if CommandLine.arguments.contains("--prepare-uninstall") {
    do {
        do {
            try ClaudeSettingsManager().disconnect()
        } catch ClaudeIntegrationError.noIntegrationState {
            // There is no Claude Code integration to restore.
        }
        try LaunchAtLoginManager().disable()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Barometer could not prepare a safe uninstall: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.contains("--disconnect-integration") {
    do {
        try ClaudeSettingsManager().disconnect()
        exit(0)
    } catch ClaudeIntegrationError.noIntegrationState {
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Barometer could not disconnect safely: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.contains("--version") {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    print("\(AppIdentity.current.appName) \(version)")
    exit(0)
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
