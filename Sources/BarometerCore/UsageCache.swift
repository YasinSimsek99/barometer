import Darwin
import Foundation

public enum UsageCacheError: Error, Equatable {
    case symbolicLinkRejected
    case oversized
    case invalidSchema
}

public struct UsageCache: Sendable {
    public let fileURL: URL
    public let directoryURL: URL

    public init(fileURL: URL? = nil) {
        let identity = AppIdentity.current
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(identity.bundleIdentifier, isDirectory: true)
        self.directoryURL = fileURL?.deletingLastPathComponent() ?? defaultDirectory
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("usage.json")
    }

    public func read() throws -> UsageSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        try rejectSymbolicLink(fileURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > 64 * 1024 {
            throw UsageCacheError.oversized
        }
        let snapshot = try JSONDecoder.barometer.decode(UsageSnapshot.self, from: Data(contentsOf: fileURL))
        guard snapshot.schemaVersion == AppIdentity.current.schemaVersion else {
            throw UsageCacheError.invalidSchema
        }
        return snapshot
    }

    /// Reads a compatible cache and rewrites it with the current allowlisted
    /// schema, removing fields retained by older Barometer builds.
    public func readSanitized() throws -> UsageSnapshot? {
        try withExclusiveLock {
            guard let snapshot = try read() else { return nil }
            let sanitizedData = try JSONEncoder.barometer.encode(snapshot)
            let storedData = try Data(contentsOf: fileURL)
            if storedData != sanitizedData {
                try write(snapshot)
            }
            return snapshot
        }
    }

    public func write(_ snapshot: UsageSnapshot) throws {
        try ensureSecureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try rejectSymbolicLink(fileURL)
        }

        let data = try JSONEncoder.barometer.encode(snapshot)
        let temporaryURL = directoryURL.appendingPathComponent(".usage-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Locks the cache across helper processes, reads its current value, and
    /// atomically persists the transformed snapshot.
    public func update(
        _ transform: (UsageSnapshot?) throws -> UsageSnapshot
    ) throws {
        try withExclusiveLock {
            try write(transform(try read()))
        }
    }

    /// Locks the cache across helper processes and removes the persisted snapshot.
    public func erase() throws {
        try withExclusiveLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try rejectSymbolicLink(fileURL)
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        try ensureSecureDirectory()
        let lockURL = directoryURL.appendingPathComponent(".usage.lock")
        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(descriptor) }

        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw currentPOSIXError()
        }
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
            throw currentPOSIXError()
        }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }

        return try operation()
    }

    private func ensureSecureDirectory() throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try rejectSymbolicLink(directoryURL)
        } else {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw UsageCacheError.symbolicLinkRejected
        }
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

extension JSONEncoder {
    fileprivate static var barometer: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var barometer: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
