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
        if let packageResource = Bundle.module.url(forResource: "AppIdentity", withExtension: "json") {
            candidates.append(packageResource)
        }

        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let value = try? JSONDecoder().decode(AppIdentity.self, from: data) {
                return value
            }
        }
        preconditionFailure("AppIdentity.json is missing or invalid")
    }()
}
