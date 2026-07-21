import CryptoKit
import Darwin
import Foundation
import BarometerCore

public struct ClaudeIntegrationPaths: Sendable {
    public let settingsURL: URL
    public let supportDirectoryURL: URL

    public init(settingsURL: URL? = nil, supportDirectoryURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.settingsURL = settingsURL ?? home.appendingPathComponent(".claude/settings.json")
        self.supportDirectoryURL = supportDirectoryURL ?? home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppIdentity.current.bundleIdentifier, isDirectory: true)
    }

    public var stateURL: URL { supportDirectoryURL.appendingPathComponent("integration.json") }
    public var backupDirectoryURL: URL { supportDirectoryURL.appendingPathComponent("backups", isDirectory: true) }
}

public enum IntegrationStatus: Equatable, Sendable {
    case disconnected
    case connected
    case conflict
}

public struct IntegrationPreview: Equatable, Sendable {
    public let existingCommand: String?
    public let proposedCommand: String

    public var summary: String {
        if let existingCommand {
            return "Barometer will capture rate-limit percentages, then run your existing status line:\n\(existingCommand)"
        }
        return "Barometer will add a Claude Code status line that only captures rate-limit percentages."
    }
}

public enum ClaudeIntegrationError: LocalizedError, Equatable {
    case settingsTooLarge
    case invalidSettings
    case symbolicLinkRejected(String)
    case settingsChangedDuringInstall
    case integrationConflict
    case noIntegrationState
    case unsupportedStatusLine

    public var errorDescription: String? {
        switch self {
        case .settingsTooLarge: "Claude settings are unexpectedly large. No changes were made."
        case .invalidSettings: "Claude settings.json is not a valid JSON object."
        case .symbolicLinkRejected(let path): "For safety, symbolic links are not modified: \(path)"
        case .settingsChangedDuringInstall: "Claude settings changed while connecting. Try again."
        case .integrationConflict: "Claude settings changed after Barometer connected. Disconnect was stopped to preserve your changes."
        case .noIntegrationState: "Barometer is not connected to Claude Code."
        case .unsupportedStatusLine: "The existing Claude status line is not a supported command configuration."
        }
    }
}

public struct ClaudeIntegrationState: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let originalStatusLine: JSONValue?
    public let installedStatusLine: JSONValue
    public let installedAt: Date
}

public struct ClaudeSettingsManager: Sendable {
    public let paths: ClaudeIntegrationPaths
    private let maximumSettingsSize = 1_048_576
    private let beforeCommit: @Sendable () throws -> Void

    public init(
        paths: ClaudeIntegrationPaths = ClaudeIntegrationPaths(),
        beforeCommit: @escaping @Sendable () throws -> Void = {}
    ) {
        self.paths = paths
        self.beforeCommit = beforeCommit
    }

    public func preview(helperExecutableURL: URL) throws -> IntegrationPreview {
        let root = try readSettings().root
        let existing = root["statusLine"]
        let existingCommand = try command(from: existing)
        return IntegrationPreview(
            existingCommand: existingCommand,
            proposedCommand: Self.shellQuote(helperExecutableURL.path)
        )
    }

    public func status() -> IntegrationStatus {
        guard let state = try? readState() else {
            return .disconnected
        }
        guard let settings = try? readSettings() else { return .conflict }
        return settings.root["statusLine"] == state.installedStatusLine ? .connected : .conflict
    }

    public func install(helperExecutableURL: URL, now: Date = Date()) throws {
        try ensureSecureDirectories()
        let settings = try readSettings()
        if let state = try? readState(), settings.root["statusLine"] == state.installedStatusLine {
            return
        }

        let originalStatusLine = settings.root["statusLine"]
        _ = try command(from: originalStatusLine)

        var installedObject: [String: JSONValue]
        if case .object(let existingObject) = originalStatusLine {
            installedObject = existingObject
        } else {
            installedObject = [:]
        }
        installedObject["type"] = .string("command")
        installedObject["command"] = .string(Self.shellQuote(helperExecutableURL.path))
        if installedObject["refreshInterval"] == nil {
            installedObject["refreshInterval"] = .number(60)
        }
        let installedStatusLine = JSONValue.object(installedObject)

        let state = ClaudeIntegrationState(
            schemaVersion: AppIdentity.current.schemaVersion,
            originalStatusLine: originalStatusLine,
            installedStatusLine: installedStatusLine,
            installedAt: now
        )

        try writeBackup(settings.data, now: now)
        try writeState(state)

        var updatedRoot = settings.root
        updatedRoot["statusLine"] = installedStatusLine
        try beforeCommit()
        let currentData = try currentSettingsData()
        guard digest(currentData) == digest(settings.data) else {
            try? FileManager.default.removeItem(at: paths.stateURL)
            throw ClaudeIntegrationError.settingsChangedDuringInstall
        }
        do {
            try atomicWrite(encode(updatedRoot), to: paths.settingsURL, permissions: 0o600)
        } catch {
            try? FileManager.default.removeItem(at: paths.stateURL)
            throw error
        }
    }

    public func disconnect() throws {
        let state = try readState()
        let settings = try readSettings()
        guard settings.root["statusLine"] == state.installedStatusLine else {
            throw ClaudeIntegrationError.integrationConflict
        }

        var updatedRoot = settings.root
        if let original = state.originalStatusLine {
            updatedRoot["statusLine"] = original
        } else {
            updatedRoot.removeValue(forKey: "statusLine")
        }
        try atomicWrite(encode(updatedRoot), to: paths.settingsURL, permissions: 0o600)
        try FileManager.default.removeItem(at: paths.stateURL)
    }

    public func originalStatusLineCommand() throws -> String? {
        try command(from: readState().originalStatusLine)
    }

    /// Disconnects Claude Code when connected, then removes locally stored
    /// integration state and settings backups. Leaves `settings.json` untouched
    /// when a conflict means Barometer no longer owns the active status line.
    public func eraseAllLocalData() throws {
        switch status() {
        case .connected:
            try disconnect()
        case .disconnected, .conflict:
            try? FileManager.default.removeItem(at: paths.stateURL)
        }
        try eraseBackups()
    }

    private func eraseBackups() throws {
        guard FileManager.default.fileExists(atPath: paths.backupDirectoryURL.path) else { return }
        try rejectSymbolicLink(paths.backupDirectoryURL)
        let backups = try FileManager.default.contentsOfDirectory(
            at: paths.backupDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for backup in backups {
            try? FileManager.default.removeItem(at: backup)
        }
    }

    private func command(from value: JSONValue?) throws -> String? {
        guard let value else { return nil }
        guard case .object(let object) = value else { throw ClaudeIntegrationError.unsupportedStatusLine }
        guard case .string(let type) = object["type"], type == "command",
              case .string(let command) = object["command"], !command.isEmpty
        else {
            throw ClaudeIntegrationError.unsupportedStatusLine
        }
        return command
    }

    private func readSettings() throws -> (data: Data, root: [String: JSONValue]) {
        let data = try currentSettingsData()
        guard data.count <= maximumSettingsSize else { throw ClaudeIntegrationError.settingsTooLarge }
        if data.isEmpty { return (Data("{}".utf8), [:]) }
        do {
            return (data, try JSONDecoder().decode([String: JSONValue].self, from: data))
        } catch {
            throw ClaudeIntegrationError.invalidSettings
        }
    }

    private func currentSettingsData() throws -> Data {
        guard FileManager.default.fileExists(atPath: paths.settingsURL.path) else { return Data("{}".utf8) }
        try rejectSymbolicLink(paths.settingsURL)
        return try Data(contentsOf: paths.settingsURL, options: [.mappedIfSafe])
    }

    private func readState() throws -> ClaudeIntegrationState {
        guard FileManager.default.fileExists(atPath: paths.stateURL.path) else {
            throw ClaudeIntegrationError.noIntegrationState
        }
        try rejectSymbolicLink(paths.stateURL)
        return try JSONDecoder.integration.decode(ClaudeIntegrationState.self, from: Data(contentsOf: paths.stateURL))
    }

    private func writeState(_ state: ClaudeIntegrationState) throws {
        try atomicWrite(JSONEncoder.integration.encode(state), to: paths.stateURL, permissions: 0o600)
    }

    private func writeBackup(_ data: Data, now: Date) throws {
        let formatter = ISO8601DateFormatter()
        let safeTimestamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let url = paths.backupDirectoryURL.appendingPathComponent("settings-\(safeTimestamp).json")
        try atomicWrite(data, to: url, permissions: 0o600)
    }

    private func ensureSecureDirectories() throws {
        let settingsDirectory = paths.settingsURL.deletingLastPathComponent()
        for directory in [settingsDirectory, paths.supportDirectoryURL, paths.backupDirectoryURL] {
            if FileManager.default.fileExists(atPath: directory.path) {
                try rejectSymbolicLink(directory)
            } else {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.supportDirectoryURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.backupDirectoryURL.path)
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw ClaudeIntegrationError.symbolicLinkRejected(url.path)
        }
    }

    private func atomicWrite(_ data: Data, to destination: URL, permissions: Int) throws {
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".barometer-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: permissions]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        if FileManager.default.fileExists(atPath: destination.path) {
            try rejectSymbolicLink(destination)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
    }

    private func encode(_ object: [String: JSONValue]) throws -> Data {
        try JSONEncoder.settings.encode(object)
    }

    private func digest(_ data: Data) -> SHA256.Digest { SHA256.hash(data: data) }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension JSONEncoder {
    static var settings: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var integration: JSONEncoder {
        let encoder = settings
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var integration: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
