import Foundation

public enum LaunchAtLoginError: LocalizedError, Equatable {
    case symbolicLinkRejected(String)
    case missingExecutable
    case invalidExistingConfiguration

    public var errorDescription: String? {
        switch self {
        case .symbolicLinkRejected(let path):
            "For safety, a symbolic link was not modified: \(path)"
        case .missingExecutable:
            "Barometer could not locate its application executable."
        case .invalidExistingConfiguration:
            "The existing Barometer launch-at-login file is invalid and was not overwritten."
        }
    }
}

public struct LaunchAtLoginManager: Sendable {
    public let launchAgentsDirectoryURL: URL
    public let plistURL: URL
    private let label: String

    public init(
        launchAgentsDirectoryURL: URL? = nil,
        label: String = AppIdentity.current.bundleIdentifier
    ) {
        let directory = launchAgentsDirectoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        self.launchAgentsDirectoryURL = directory
        self.plistURL = directory.appendingPathComponent("\(label).plist")
        self.label = label
    }

    public var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public func setEnabled(_ enabled: Bool, executableURL: URL) throws {
        if enabled {
            try enable(executableURL: executableURL)
        } else {
            try disable()
        }
    }

    public func disable() throws {
        try removeLaunchAgent()
    }

    public func refreshExecutablePathIfEnabled(_ executableURL: URL) throws {
        guard isEnabled else { return }
        try enable(executableURL: executableURL)
    }

    private func enable(executableURL: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw LaunchAtLoginError.missingExecutable
        }
        try ensureSecureDirectory()
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try rejectSymbolicLink(plistURL)
            guard let existing = try? PropertyListSerialization.propertyList(
                from: Data(contentsOf: plistURL),
                options: [],
                format: nil
            ) as? [String: Any], existing["Label"] as? String == label else {
                throw LaunchAtLoginError.invalidExistingConfiguration
            }
        }

        let propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try atomicWrite(data)
    }

    private func removeLaunchAgent() throws {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try rejectSymbolicLink(plistURL)
        let existing = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            options: [],
            format: nil
        ) as? [String: Any]
        guard existing?["Label"] as? String == label else {
            throw LaunchAtLoginError.invalidExistingConfiguration
        }
        try FileManager.default.removeItem(at: plistURL)
    }

    private func ensureSecureDirectory() throws {
        if FileManager.default.fileExists(atPath: launchAgentsDirectoryURL.path) {
            try rejectSymbolicLink(launchAgentsDirectoryURL)
        } else {
            try FileManager.default.createDirectory(
                at: launchAgentsDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw LaunchAtLoginError.symbolicLinkRejected(url.path)
        }
    }

    private func atomicWrite(_ data: Data) throws {
        let temporaryURL = launchAgentsDirectoryURL.appendingPathComponent(".barometer-login-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            _ = try FileManager.default.replaceItemAt(plistURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: plistURL)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL.path)
    }
}
