import Foundation
import BarometerCore

public struct BridgeRunner: Sendable {
    public let cache: UsageCache
    public let settingsManager: ClaudeSettingsManager
    public let maximumInputSize: Int

    public init(
        cache: UsageCache = UsageCache(),
        settingsManager: ClaudeSettingsManager = ClaudeSettingsManager(),
        maximumInputSize: Int = 2 * 1_048_576
    ) {
        self.cache = cache
        self.settingsManager = settingsManager
        self.maximumInputSize = maximumInputSize
    }

    @discardableResult
    public func capture(_ input: Data, now: Date = Date()) -> Bool {
        guard input.count <= maximumInputSize,
              let snapshot = try? RateLimitParser().parse(input, capturedAt: now)
        else { return false }
        do {
            let normalizedSnapshot = snapshot.normalized(at: now)
            try cache.update { existing in
                existing?
                    .normalized(at: now)
                    .merging(normalizedSnapshot) ?? normalizedSnapshot
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func runPreviousStatusLine(input: Data) -> Int32 {
        guard let command = try? settingsManager.originalStatusLineCommand() else {
            return 0
        }

        let process = Process()
        let standardInput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardInput = standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            standardInput.fileHandleForWriting.write(input)
            try standardInput.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            try? standardInput.fileHandleForWriting.close()
            return 1
        }
    }
}
