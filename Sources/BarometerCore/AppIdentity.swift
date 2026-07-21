import Foundation

public struct AppIdentity: Codable, Equatable, Sendable {
    public let appName: String
    public let bundleIdentifier: String
    public let executableName: String
    public let bridgeExecutableName: String
    public let repository: String
    public let schemaVersion: Int

    public static let current: AppIdentity = {
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let executableResources = executableURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let resourceDirectories = [Bundle.main.resourceURL, executableResources].compactMap { $0 }
        var candidates = resourceDirectories.map { $0.appendingPathComponent("AppIdentity.json") }
        for directory in resourceDirectories {
            if let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                candidates.append(contentsOf: children
                    .filter { $0.pathExtension == "bundle" }
                    .map { $0.appendingPathComponent("AppIdentity.json") })
            }
        }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let value = try? JSONDecoder().decode(AppIdentity.self, from: data) {
                return value
            }
        }

        // Last resort only: SwiftPM's generated Bundle.module accessor assumes
        // the resource bundle sits beside the executable (true for `swift run`/
        // `swift test`), and calls fatalError if it doesn't — which is exactly
        // what happens once build-app.sh repackages the executable into
        // Contents/MacOS with resources under Contents/Resources. Never touch
        // Bundle.module unless every path-based candidate above has failed.
        if let packageResource = Bundle.module.url(forResource: "AppIdentity", withExtension: "json"),
           let data = try? Data(contentsOf: packageResource),
           let value = try? JSONDecoder().decode(AppIdentity.self, from: data) {
            return value
        }

        preconditionFailure("AppIdentity.json is missing or invalid")
    }()
}
